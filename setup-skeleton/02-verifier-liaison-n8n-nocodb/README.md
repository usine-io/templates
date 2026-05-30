# Step 02 — Vérifier la liaison n8n ↔ NocoDB

> Smoke test bidirectionnel qui valide que les **3 routes fondamentales** entre n8n et NocoDB fonctionnent. C'est le substrat de **toute** feature qu'on construira ensuite (CRM, WMS, sync legacy, etc.) — si l'une des 3 routes ne passe pas, aucun POC métier n'est possible.

## Pourquoi cette étape

Avant de construire un mini-CRM (ou n'importe quel POC), on vérifie que :
- n8n peut **écrire** dans NocoDB (créer/modifier des lignes via l'API)
- NocoDB peut **déclencher** un workflow n8n (webhook sortant sur événement de table)
- n8n peut **lire** dans NocoDB (utile pour "sur événement, va chercher la ligne complète et fais quelque chose")

Si ces 3 routes marchent, on a la base. Si l'une plante, le débogage métier ultérieur sera pollué. **Ce step découple infra de feature.**

## Les 3 routes à valider

| # | Route | Mécanisme | Ce qu'on prouve |
|---|---|---|---|
| **R1** | `n8n → NocoDB` (write) | n8n HTTP Request `POST /api/v2/tables/<id>/records` avec `xc-token` | Le credential NocoDB stocké dans n8n est valide, l'écriture passe. |
| **R2** | `NocoDB → n8n` (trigger) | NocoDB webhook outgoing `AFTER INSERT` sur table `_t_pings` → URL n8n webhook | NocoDB peut joindre n8n (réseau interne `spark` dans Docker), payload exploitable. |
| **R3** | `n8n → NocoDB` (read) | n8n HTTP Request `GET /api/v2/tables/<id>/records?where=...` | Lecture filtrée fonctionne — utile pour enrichir un payload depuis le contexte. |

## Scénario E2E (boucle complète)

```
   ┌──────────────────────────────────────────────────────────────┐
   │  NocoDB                                n8n                    │
   │                                                               │
   │  ┌────────────┐                        ┌─────────────────┐    │
   │  │ _t_pings   │ ◀──── (R1) ───────────┤ flow:_t_ping    │    │
   │  │ id         │   POST /records       │  webhook in     │ ◀─ curl POST
   │  │ source     │                        │  → POST NocoDB │    │
   │  │ payload    │                        └─────────────────┘    │
   │  │ created_at │                                                │
   │  └────────────┘                                                │
   │       │                                                        │
   │       │ AFTER INSERT (NocoDB webhook)                          │
   │       ▼                                                        │
   │  ┌─────────────────┐         ┌──────────────────────────┐     │
   │  │  webhook out    │ ─(R2)─▶ │ flow:_t_echo             │     │
   │  │  payload JSON   │         │  webhook in              │     │
   │  └─────────────────┘         │  → READ ping             │ ─(R3)
   │                              │     row from NocoDB      │     │
   │                              │  → INSERT _t_echoes row  │ ──┐ │
   │                              └──────────────────────────┘   │ │
   │                                                              ▼ │
   │                              ┌────────────┐                    │
   │                              │ _t_echoes  │                    │
   │                              │ id         │                    │
   │                              │ ping_id    │                    │
   │                              │ note       │                    │
   │                              │ created_at │                    │
   │                              └────────────┘                    │
   └──────────────────────────────────────────────────────────────┘
```

**Critère de validation finale** : un seul `curl POST` sur le webhook `_t_ping` doit produire :
1. 1 ligne dans `_t_pings` (R1 OK)
2. 1 ligne dans `_t_echoes` avec `ping_id` correspondant (R2 + R3 OK)

Si les deux lignes apparaissent en moins de ~5 s : step 02 = ✅.

## Schémas de tables (NocoDB)

### `_t_pings`
| Colonne | Type | Notes |
|---|---|---|
| `Id` | auto-increment | clé primaire NocoDB par défaut |
| `source` | SingleLineText | qui a déclenché (`smoke-test`, `manual-ui`, ...) |
| `payload` | LongText | JSON arbitraire, pour vérifier que les données passent |
| `CreatedAt` | DateTime | auto NocoDB |

### `_t_echoes`
| Colonne | Type | Notes |
|---|---|---|
| `Id` | auto-increment | |
| `ping_id` | Number | référence à `_t_pings.Id` (foreign key logique, pas relationnelle pour simplifier) |
| `note` | LongText | trace du workflow n8n (ex: "echo'd ping #42 at 14:32") |
| `CreatedAt` | DateTime | auto NocoDB |

## Prérequis

- [ ] Step 00 ✅ et step 01 ✅ (`infra/.env` contient les tokens API)
- [ ] La validation `curl` du step 01 a renvoyé HTTP 200 sur les 2

## Procédure (à dérouler en mode interactif Claude)

À ce stade, le `run.sh` n'est **pas** écrit à l'avance. Il sera assemblé étape par étape pendant la session, en gardant trace de ce qui marche. Plan de marche :

1. **Découverte de l'état** côté NocoDB : Claude liste les bases existantes via API. Si pas de base par-défaut utilisable, Claude en crée une (`smoke-test` ou `${SPARK_PREFIX}`).
2. **Création des 2 tables** `_t_pings` et `_t_echoes` via API NocoDB.
3. **Création du credential NocoDB** dans n8n via API n8n (pour que les nodes HTTP de n8n puissent écrire dans NocoDB sans hardcoder le token dans chaque node).
4. **Création du flow `_t_ping`** dans n8n :
   - Trigger : Webhook (path : `/_t_ping`, méthode POST, auth basique header)
   - Action : HTTP Request → POST `/api/v2/tables/<_t_pings_id>/records` avec body construit depuis le payload entrant
   - Activer le flow.
5. **Création du flow `_t_echo`** dans n8n :
   - Trigger : Webhook (path : `/_t_echo`)
   - Action 1 : HTTP Request GET le record `_t_pings` correspondant (R3)
   - Action 2 : HTTP Request POST dans `_t_echoes` avec `ping_id` extrait
   - Activer le flow.
6. **Configuration du webhook outgoing NocoDB** sur `_t_pings` AFTER INSERT → URL du flow `_t_echo` (sur `${SPARK_PREFIX}-n8n.${SPARK_DOMAIN}/webhook/_t_echo` avec auth header `secret-shared`).
7. **Test E2E** : `curl POST` vers `${SPARK_PREFIX}-n8n.${SPARK_DOMAIN}/webhook/_t_ping` avec un payload exemple → vérifier que 1 ligne apparaît dans `_t_pings` ET 1 ligne dans `_t_echoes` corrélée.
8. **Capture des artefacts** dans ce dossier :
   - `nocodb-schema.json` : schéma des 2 tables (export ou requête)
   - `n8n-flow-ping.json` : export du flow
   - `n8n-flow-echo.json` : export du flow
9. **Rédaction du `run.sh`** : assembler les commandes qui ont marché, idempotent (re-créer = no-op si déjà là).
10. **Rédaction du `teardown.sh`** : supprimer flows + tables + webhook + credential. Ne pas supprimer les exports JSON.

## Statut du step

- [ ] Base `_t_smoke` + tables `_t_pings` + `_t_echoes` créées dans NocoDB (cf. `nocodb-schema.json`)
- [ ] Credential NocoDB (`httpHeaderAuth` "NocoDB API _t_smoke") enregistré dans n8n
- [ ] Flow `_t_ping` créé et activé (cf. `n8n-flow-ping.json`)
- [ ] Flow `_t_echo` créé et activé (cf. `n8n-flow-echo.json`, version finale avec R3 GET + R1 POST)
- [ ] Webhook outgoing NocoDB configuré (`_t_pings_after_insert`, version v3)
- [ ] Test E2E : R1, R2, R3
- [ ] Artefacts capturés (`nocodb-schema.json`, `n8n-flow-ping.json`, `n8n-flow-echo.json` — JSONs avec placeholders `__NOCODB_HOST__`, `__PINGS_TABLE_ID__`, etc., substitués au runtime par `run.sh`)
- [ ] `run.sh` idempotent (3+ runs validés : 1er = full create, 2e+ = "exists" partout, E2E toujours passe)
- [ ] `teardown.sh` idempotent (DELETE silencieux sur 404, strip `.env` final)

→ Step 02 ⏳ à valider. Pour rejouer le test sur un autre site Spark, adapter les variables d'URL en haut de `run.sh` et `teardown.sh` (`NOCODB_HOST`, `N8N_HOST` — lues depuis `SPARK_PREFIX` et `SPARK_DOMAIN`).

## Comment rejouer

```bash
# Cycle complet (clean + recréer + tester)
./teardown.sh && ./run.sh

# Re-test seul (pas de modif d'objets)
./run.sh
```

## Limitation connue — credentials n8n

L'API publique n8n **n'expose pas** `GET /credentials` (ni liste ni individual — tous renvoient 405 par design pour pas leak les secrets). On ne peut donc pas vérifier si un credential ID est encore valide, ni rechercher par nom. `run.sh` se fie aveuglément à `N8N_CRED_ID_NOCODB` dans `.env` :
- présent → utilisé tel quel (pas de validation)
- absent → un nouveau credential est créé, l'ID est persisté

Si quelqu'un supprime un credential dans l'UI sans toucher `.env`, les flows planteront à l'exécution avec une erreur d'auth. Dans ce cas : `unset N8N_CRED_ID_NOCODB` dans `.env` puis re-run.

## Découvertes pendant le step

1. **NocoDB v2 hooks ont migré vers v3** sur les versions récentes de NocoDB. L'ancien format renvoie `"hook version is deprecated / not supported anymore"`. Format v3 : `version: "v3"`, `operation: ["insert"]` (array, pas string), notification avec `body: "{{ json data }}"` pour que les rows soient envoyés.
2. **Format payload webhook v3** : `body.data.rows[0]` contient l'objet inséré. Cf. `nocodb-schema.json` section `_payload_format_v3_after_insert`.
3. **n8n self-hosted derrière cloudflared** : le `WEBHOOK_URL` configuré dans `infra/.env` (`https://${SPARK_PREFIX}-app.${SPARK_DOMAIN}/`) est utilisé par n8n pour signer les webhooks dans son UI, mais NocoDB peut appeler n8n indifféremment via `${SPARK_PREFIX}-app` ou `${SPARK_PREFIX}-n8n` puisque cloudflared route les deux vers le même container. On recommande `${SPARK_PREFIX}-n8n` dans la config du hook.
4. **Auth des nodes HTTP Request** : utiliser un credential `httpHeaderAuth` générique (header `xc-token`) plutôt que le node NocoDB natif → plus flexible, moins de surface d'incompatibilité avec les versions self-hosted.

## Promotion vers la template

Une fois ce step validé sur un déploiement Spark, l'extraire vers `spark-kit/templates/setup-skeleton/02-verifier-liaison-n8n-nocodb/` en s'assurant que toutes les URLs utilisent `${SPARK_PREFIX}-*.${SPARK_DOMAIN}` et non des valeurs hardcodées.
