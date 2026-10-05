# Template PRD — POC Spark client

> Gabarit fillable pour rédiger un PRD de POC Spark à déployer chez un client.
> **Usage** : copier ce fichier vers `<repo-client>/discovery/prds/prd-NNN-<slug>.md`, puis remplir les `{{placeholders}}`.
> Les sections marquées *(facultatif)* peuvent être omises sur un POC trivial — mais expliquer pourquoi en haut du document.
> Inspiré du PRD bien structuré `wiki/topics/veille-prd.md`. Lire avant rédaction : `wiki/topics/manifeste-spark.md` (vision, niveaux 1-7) et la ou les fiches-logiciel des systèmes touchés (`discovery/fiches/*.md`).

> **Frontmatter = source unique de vérité du PRD.** Le frontmatter YAML ci-dessous contient toutes les métadonnées d'identité, de contexte, de cycle de vie et d'affichage. Un tracker NocoDB optionnel peut lire ces frontmatters pour produire un miroir Kanban/Liste via un workflow n8n de sync — il ne stocke jamais d'info que le `.md` ne porte pas. Conséquence : pour changer le statut d'un PRD, on édite ici et on commit. Pas d'UI Kanban à éditer.

---

```markdown
---
# === Identite ===
title: "PRD POC — {{Nom court du POC}}"
slug: "prd-NNN-{{slug-court}}"           # ex: prd-007-wms-pieces. Doit matcher le nom du fichier.
version: 0.1

# === Contexte projet ===
client: "{{Nom du client}}"
site: "{{site/prefix Spark, ex: acme}}"
owner: "{{Atelier B - prénom}}"
champion: "{{prénom du champion interne client}}"
niveau_spark: {{N}}                       # 1..7 — cf. manifeste Spark §"niveaux d'intervention"
domaine: [{{wms|erp|crm|integration|meta|tracabilite|cs}}]   # liste, multi possible
tags: [prd, poc, niveau-{{N}}, {{domaine}}]               # tags d'affichage libres (legacy + recherche)
depends_on: []                            # PRD prérequis, ex: ["prd-005", "prd-013"]

# === Cycle de vie ===
status: draft                             # idea | draft | review | approved | implementing | live | retired | rejected
date: {{YYYY-MM-DD}}                      # date de rédaction initiale
promoted_at:                              # rempli quand `idea` → `draft`
approved_at:                              # rempli quand `review` → `approved`
started_at:                               # rempli quand `approved` → `implementing`
live_at:                                  # rempli quand `implementing` → `live`
retired_at:                               # rempli quand `live` → `retired` ou `* → rejected`
amended_at: []                            # dates des amendements (§12), ex: [2026-10-05] — le status ne change pas
---

# PRD POC — {{Nom du POC}}

> Spec courte (3-10 pages) d'un POC Spark à construire pour {{client}}.

---

## 1. Contexte et objectif

### 1.1 Le client en 3 lignes
- **Activité** : {{ex: reconditionnement smartphones, 25 personnes, 3000 unités/mois}}
- **Pain ciblé** : {{ex: copier-coller IMEI entre MonLogiciel et Google Sheets, ~2h/jour perdues}}
- **Niveau Spark visé** : niveau {{N}} ({{nom du niveau, cf. manifeste-spark §"niveaux d'intervention"}})

### 1.2 Objectif du POC en 1 phrase
{{Une seule phrase. Si elle dépasse 25 mots, le POC est trop large — découper en plusieurs PRD.}}

### 1.3 Pourquoi maintenant
{{Trigger métier : montée en charge, nouveau client, perte mesurée, compliance, échéance externe...}}

---

## 2. Périmètre

### Dans le périmètre (v1)
- {{...}}
- {{...}}

### Hors périmètre (v1)
- {{...}}
- {{...}}

> Discipline anti-scope-creep : tout ce qui n'est pas listé "in" est traité comme "out", même si "ce serait bien". On ouvre une v2 si le besoin se confirme après 2-4 semaines de run.

---

## 3. Sources de vérité et flux de données

> ⚠️ Rappel archi (cf. [`spark-kit/spark-kit` README §2.2](https://github.com/spark-kit/spark-kit)) : les sources de vérité business sont **les systèmes métier du client**. NocoDB est staging / nouvelle source pour des données qui n'existaient nulle part. n8n est le bridge contrôlé.

### 3.1 Systèmes métier touchés (sources de vérité business)

| Système | Rôle métier | Surface d'intégration | Direction du flux | Fiche |
|---|---|---|---|---|
| {{ex: MonLogiciel}} | {{diagnostic phones}} | {{webhook sortant JSON}} | legacy → Spark | `discovery/fiches/mon-logiciel.md` |
| {{ex: Google Sheets ERP}} | {{ERP de fortune}} | {{Sheets API v4}} | bidirectionnel | `discovery/fiches/google-sheets-erp.md` |

### 3.2 Surface NocoDB (staging / écrans côté Spark)

**Tables nouvelles ou modifiées** :

| Table | Type | Rôle |
|---|---|---|
| {{ex: phones_diag}} | nouvelle | {{cache des résultats MonLogiciel, append-only}} |
| {{ex: phones_state}} | nouvelle | {{état courant + historique par IMEI}} |

**Vues / écrans** :
- {{ex: Vue "À traiter aujourd'hui" — filtre statut=pending, ordre=date}}
- {{ex: Écran tablette poste réception — formulaire de scan IMEI + résumé}}

### 3.3 Workflows n8n (high-level)

| Workflow | Trigger | Action | Brique playbook |
|---|---|---|---|
| {{ex: mon-logiciel-ingest}} | {{webhook MonLogiciel}} | {{INSERT NocoDB phones_diag + UPDATE phones_state}} | `n8n-webhook-in` + `n8n-nocodb-bridge` *(chantier A — à créer)* |

> Détailler en pseudo-code uniquement à l'échelle qui sert la décision archi. L'implémentation détaillée ne va pas dans le PRD — elle vit dans le repo de site (workflows n8n exportés JSON, scripts).

---

## 4. Utilisateurs et rôles

| Rôle | Personnes | Action attendue | Surface |
|---|---|---|---|
| {{ex: Opérateur réception}} | {{3 techniciens}} | {{scanner les IMEI à l'arrivée}} | {{tablette → écran NocoDB form}} |
| {{ex: Chef d'atelier}} | {{prenom}} | {{voir le pipeline de la journée}} | {{vue "Aujourd'hui"}} |
| {{ex: Direction}} | {{dirigeant}} | {{stats hebdo}} | {{vue analytics}} |

---

## 5. Critères de succès

### 5.1 KPIs mesurables
*(s'inspirer de Q3.5 du questionnaire onboarding)*

- {{ex: temps gagné par jour : objectif 1h30, mesuré par chrono champion semaine 1 et semaine 4}}
- {{ex: élimination du copier-coller : 0 saisie manuelle sur ≥ 95 % des cas mesurés}}
- {{ex: latence event → NocoDB visible : < 30 s sur 99e percentile}}

### 5.2 Critères qualitatifs
- {{ex: champion interne dit "je gagne du temps" sans qu'on le sollicite}}
- {{ex: zéro escalade IT en 4 semaines de run}}

### 5.3 Critères d'acceptation testables

> **Definition of done exécutable.** Chaque critère = **une assertion** d'un script `validate-*.sh` nommé (nouveau ou existant à étendre). Un critère qu'on ne sait pas écrire comme assertion (HTTP, SQL, comptage) n'est pas un critère : le reformuler ou le déplacer en §5.2. Couvrir le nominal **et** les refus (validation, doublon, statut interdit). Tous verts avant `live`.

| # | Critère (observable) | Assertion | Script |
|---|---|---|---|
| CA1 | {{ex: un scan IMEI inconnu crée 1 dossier et 1 seul, statut `recu`}} | {{POST /api/... → 200 ; count(dossiers where imei=X) = 1}} | `validate-{{poc}}.sh` [1] |
| CA2 | {{ex: un 2e scan du même IMEI est refusé sans doublon}} | {{200 + success:false ; count reste 1}} | `validate-{{poc}}.sh` [1] |
| CA3 | {{ex: non-régression — l'export X sort à l'identique avant/après}} | {{diff des colonnes = 0 sur N jours}} | `validate-{{existant}}.sh` (étendu) |

---

## 6. Contraintes non-fonctionnelles

| Contrainte | Cible | Mesure |
|---|---|---|
| Volume {{event/jour}} | {{ex: ≤ 200}} | {{logs n8n}} |
| Latence | {{ex: < 30s p99}} | {{Uptime Kuma + n8n exec time}} |
| Fenêtre de maintenance | {{ex: nuit + WE}} | {{accord avec champion}} |
| Disponibilité | {{ex: heures ouvrées 7h-18h, lundi-vendredi}} | {{monitoring}} |

---

## 7. Sécurité et confidentialité

- **Données sensibles touchées** : {{ex: IMEI = identifiants techniques, pas perso. RGPD : N/A pour ce POC}}
- **Stockage** : LAN-only, NocoDB sur Spark Mac Mini, pas de cloud externe
- **Auth/secrets côté Spark** : credentials chiffrés via `N8N_ENCRYPTION_KEY` (cf. archi-technique §4.1)
- **Auth côté legacy** : {{ex: token API MonLogiciel, scope minimal lecture, rotation manuelle tous les 6 mois}}
- **Backup** : couvert par la stratégie 3-2-1 du site (cf. archi-technique §2.3)

---

## 8. Risques et hypothèses

| # | Risque / Hypothèse | Probabilité | Impact | Mitigation |
|---|---|---|---|---|
| R1 | {{ex: MonLogiciel change son format webhook sans préavis}} | basse | haut | {{tests automatiques sur structure de payload, alerte Kuma}} |
| R2 | {{ex: réseau Wi-Fi sature pendant les pics de réception}} | moyenne | moyen | {{cf. archi §1.5, switch + IP fixe + Ethernet pour le poste atelier}} |
| H1 | {{Hypothèse : champion dispo 2h/sem pour valider}} | — | — | {{si fausse → POC mort, escalade direction}} |

---

## 8bis. Impact sur la prod

> **Obligatoire dès que le site a au moins un module en prod**, même pour un outil « neuf » (il peut lire ou écrire des tables partagées). Sinon écrire « N/A — premier module du site ». Périmètre : **ce site uniquement** (les sites sont indépendants).
>
> Deux règles : **pas de source, pas de ligne** (chaque élément cite le fichier, la section du PRD, l'id du workflow ou le script) ; **le métier tranche** — un conflit se formule en question à l'owner (§10), jamais en correction implicite. Seuls les ⛔ bloquent le passage en `approved`.

| Élément en prod touché | Classe | Ce qui change / casserait | Source | Question (§10) |
|---|---|---|---|---|
| {{ex: endpoint `api/.../stock`}} | ✅ ajout pur | {{nouvelle route, rien d'existant modifié}} | {{infra/workflows/<id>.json}} | — |
| {{ex: énum `dossiers.statut`}} | ⚠️ modifie | {{nouvelle valeur ; procédure d'évolution d'énum à suivre}} | {{doc statuts §0}} | {{Q<NNN>-1}} |
| {{ex: PRD-0XX « hors périmètre »}} | ⛔ contredit | {{l'objectif reprend un point exclu par PRD-0XX §5}} | {{prd-0XX §5}} | {{Q<NNN>-2}} |
| {{ex: `validate-xxx.sh` invariant 3}} | 🔁 casse un test | {{l'invariant suppose que …}} | {{validate-xxx.sh l.NN}} | {{Q<NNN>-3}} |

---

## 9. Plan d'implémentation

### 9.1 Briques playbooks utilisées

- {{`n8n-webhook-in`}} *(chantier A — à créer)*
- {{`n8n-nocodb-bridge`}} *(chantier A — à créer)*
- {{...}}

### 9.2 Étapes

| # | Étape | Durée | Livrable | Owner |
|---|---|---|---|---|
| 1 | {{Setup credentials MonLogiciel côté n8n}} | {{30 min}} | {{credential vault entry}} | {{Atelier B}} |
| 2 | {{Création tables NocoDB}} | {{1h}} | {{schéma + données fictives}} | {{Atelier B}} |
| 3 | {{Workflow n8n ingest}} | {{2h}} | {{flow JSON exporté + commité}} | {{Atelier B}} |
| 4 | {{Test bout-en-bout avec champion}} | {{1h}} | {{validation sur 5 cas réels}} | {{champion + Atelier B}} |
| 5 | {{Mise en service + monitoring 1 semaine}} | {{1 sem}} | {{rapport hebdo + ajustements}} | {{champion}} |

### 9.3 Durée totale estimée
{{ex: ~1 jour de dev + 1 semaine de monitoring}}

### 9.4 Ordre de mise en prod et non-régression
*(obligatoire si §8bis contient un ⚠️ ou un 🔁)*

- **Ordre** : {{ex: 1. lecture des prix par clé (sans effet visible) → 2. changement de format → 3. nouvelle intégration}}. Une étape ne part en prod que si la précédente y est **et** que son banc est vert.
- **Bancs de non-régression** : pour chaque sortie existante qui doit rester identique (export, écran, rapport), un instantané **avant** et une comparaison **après** la mise en prod — critère §5.3 dédié.
- **Retour arrière** : {{ex: échange des chemins de webhook en sens inverse ; sauvegarde du workflow avant patch}}.

---

## 10. Décisions ouvertes

> Numéroter **par PRD** (`Q<NNN>-1`, `Q<NNN>-2`…) pour éviter les collisions entre documents. En rédaction autonome (agent), toute hypothèse non validée par l'owner vit ici ou en §8 (H*n*), jamais dans le corps du PRD comme un fait.

| # | Décision | Options | Reco | Bloquant pour | Échéance |
|---|---|---|---|---|---|
| Q<NNN>-1 | {{ex: format de phones_diag : 1 ligne par diag ou 1 ligne par phone avec dernière diag ?}} | a / b | {{a, parce que…}} | {{`approved` / étape 2 / rien}} | {{avant étape 2}} |

---

## 11. Annexes

### Sources documentaires
- Rapport d'onboarding : {{lien interne, ex: `discovery/onboarding/visite-2026-MM-DD.md`}}
- Fiches-logiciel : `discovery/fiches/{{...}}.md`
- Manifeste & archi : `wiki/topics/manifeste-spark.md`, `wiki/topics/architecture-technique.md`

### Glossaire client *(facultatif)*
- {{IMEI}} : {{International Mobile Equipment Identity, identifiant unique téléphone}}

---

## 12. Amendements

> Ajouts **après** passage en `live` (ou en `approved`), dans le périmètre de ce PRD. On n'efface pas l'historique : on ajoute. Signaler aussi chaque amendement par un bandeau en tête du document (`> ⚠️ Amendement YYYY-MM-DD : résumé — cf. §12`) et sa date dans `amended_at`. Le `status` ne change pas.

### {{YYYY-MM-DD}} — {{titre court}}
- **Demande** : {{qui, quoi, pourquoi}}
- **Décision** : {{ce qui est retenu ; décisions numérotées A1…An}}
- **Impact prod** : {{tableau §8bis restreint à l'amendement}}
- **Critères ajoutés** : {{CA… → script}}
- **Ordre / non-régression** : {{si §9.4 s'applique}}

---

*PRD v0.1 rédigé le {{YYYY-MM-DD}}. À réviser après chaque jalon (`approved`, `implementing`, `live`).*
```

---

## Notes pour le rédacteur

- **Numéro PRD** : 3 chiffres incrémental par-site (`prd-001`, `prd-002`...). Le numéro reste figé même si le statut évolue. Le `slug` du frontmatter doit matcher le nom du fichier.
- **Si le POC est trivial** (<2h dev, 1 brique, 1 utilisateur) : un PRD ultra-court à 4 sections (1, 2, 5 dont 5.3, 9) suffit. Plutôt qu'éliminer la spec, on la compresse.
- **Faire évoluer un module existant — amender ou ouvrir un PRD ?**

  | Cas | Action |
  |---|---|
  | Correction de bug | Pas de PRD : commit + bloc daté dans `LESSONS-LEARNED.md` si instructif |
  | Ajustement **dans le périmètre** et les parcours d'un PRD (règle, déclenchement, champ) | **Amendement** (§12) du PRD concerné + mise à jour de son script `validate` |
  | Nouvelle fonctionnalité, nouveau parcours utilisateur, nouvelle donnée, ou point listé « hors périmètre » | **Nouveau PRD** (`prd-NNN+1-<slug>`), `depends_on` vers l'ancien ; l'ancien reçoit un bandeau de renvoi |

  C'est l'analyse d'impact (§8bis) qui dit quels PRD sont touchés, donc lequel des trois cas s'applique.
- **Rédaction par un agent (mode autonome)** : le PRD s'arrête à `review` ; le passage `review → approved` est la validation de l'owner. Exigences : §8bis rempli (sources citées), §5.3 entièrement en assertions, hypothèses en §8/§10, aucune décision métier inventée.
- **Statuts (lifecycle complet)** :
  - `idea` : capture brute, pas encore promue. Pas obligé d'avoir un `slug` ou un fichier — peut vivre uniquement dans le tracker NocoDB en attendant.
  - `draft` (rédaction) → `review` (relu champion + Atelier B) → `approved` (go pour implémenter) → `implementing` (en cours) → `live` (en prod, monitoring) → `retired` (POC arrêté ou remplacé).
  - `rejected` : terminal alternatif depuis `idea` ou `draft` — note la raison dans une §11 Annexes ou en commentaire.
- **Dates de transition (`*_at`)** : à remplir à chaque transition. Convention ISO `YYYY-MM-DD` ou `YYYY-MM-DDTHH:MM:SSZ`. Ce sont elles que le tracker NocoDB lit pour son timeline / calendar.
- **Frontmatter complet = condition d'apparition propre dans le tracker.** Un champ manquant n'est pas bloquant (le tracker affiche `null`), mais c'est moins lisible. Au minimum : `title`, `slug`, `status`, `niveau_spark`, `domaine`, `owner`.
