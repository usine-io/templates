---
name: spark-n8n-pseudo-api
description: Construire un endpoint backend Spark = webhook n8n adossé à NocoDB (pseudo-API derrière Caddy). Use when creating/editing an n8n webhook endpoint, designing a Spark backend route, wiring a front to NocoDB via n8n, or debugging "invalid syntax"/"Unmatched expression brackets" on a jsonBody, IF node validation errors, parallel-branch fan-in returning undefined, or webhook path params. Complète les skills `n8n-*` (qui couvrent un node isolé) par l'assemblage bout-en-bout.
metadata:
  spark:
    layer: backend
    source: spark-pitfalls-catalog (W1-W23, P1-P2)
    arch: "Caddy → n8n (pseudo-API) → NocoDB"
---

# n8n pseudo-API — patterns d'endpoint Spark

> L'architecture Spark : **Caddy** sert un front statique + reverse-proxy → **n8n** expose des webhooks qui orchestrent → **NocoDB** stocke.
> Un « endpoint » Spark = un workflow webhook. Cette skill explique comment **assembler** un endpoint correct du premier coup. Les skills `n8n-node-configuration` / `n8n-expression-syntax` couvrent un node isolé ; ici on couvre la **route entière**.
> Voir aussi `spark-nocodb-v3-patterns` pour la couche data (Links, Lookups, bulk).

---

## 🚨 Le bug n°1 : jsonBody avec struct complexe (W3/W4/W22)

`={{ JSON.stringify({…}) }}` inline → **"invalid syntax"**. Et `={"fields": {"qty": {{ $json.x }}}}` → **"Unmatched expression brackets: 1 opening, 2 closing"** (les `{}` JSON sont confondus avec les `{{}}` d'expression). Vécu 5+ fois.

**Pattern systématique éprouvé** :

```
[Webhook] → [Code node "Prep"] → [HTTP Request]
```

1. **Code node "Prep"** prépare la string body en JS pur :
   ```js
   const body = JSON.stringify({ fields: { qty: $json.body.qty, nom: $json.body.nom } });
   return [{ json: { insert_body: body } }];
   ```
2. **HTTP Request** consomme la string toute prête :
   ```
   jsonBody = ={{ $json.insert_body }}
   ```

> **`={{ $json.X }}` marche systématiquement.** C'est l'imbrication d'objets dans l'expression qui casse, pas l'expression elle-même.
> **W4 (cas plat seulement)** : `={"id": {{ id }}, "fields": {"x": "y"}}` passe pour des structs **plates sans string interpolée**. Au moindre doute → Code node Prep.

---

## Entrée du webhook (W1)

- POST : données dans **`$json.body.X`**.
- GET : query params dans **`$json.query.X`**.
- Jamais `$json.X` direct.
- **W19 — 🚨 pas de path params `:varname`** : `api/grades/:slug/mapping` est enregistré **littéralement** (tout autre URL → 404). Testé n8n 2.51.1. Workaround : `?slug=X` (query) ou body. (Re-tester en 2.56+.)

## Validation & erreurs (W10)

```js
// Dans un Code node : un rejet de validation doit faire un VRAI 500
if (!$json.body.motif) {
  throw new Error("motif requis");        // ✅ → HTTP 500 automatique
}
// ❌ return [{json:{_error:"…"}}]  → CONTINUE la chaîne et casse plus loin
```

## Jamais de branches parallèles (W9)

n8n CE n'a **pas** de merge/wait fiable. Un Code node "Build Response" en aval de branches parallèles s'exécute **avant** que les branches aient fini → `$('NodeName').first().json` = `undefined`.

➡️ Tout en **chaîne séquentielle** : `Fetch A → Fetch B → Fetch C → Build Response`. Légèrement plus lent, 100 % fiable.

## IF node (W5/W21)

- **W5** : `conditions.options = {version:2, leftValue:"", caseSensitive:true, typeValidation:"strict"}` est **obligatoire** (le validator MCP refuse sinon).
- **W21** : en `typeValidation:"strict"` + operator `string`, un `leftValue` numérique (ex. un id) → "Wrong type: '4' is a number…". Forcer en string : `={{ $json.x ? 'yes' : '' }}` ou `.toString()`.

## Method dynamique (upserts) (W17/W20)

```
method = ={{ $json.mode === 'insert' ? 'POST' : 'PATCH' }}
```
**W20** : ça déclenche un faux positif "Invalid value for method" en validation MCP **mais fonctionne au runtime**. Ignorer le warning, activer quand même.

---

## NocoDB depuis n8n (W6/W7/W8)

- **Credential natif** `nocoDbApiToken` (libellé "API Token"), **pas** `httpHeaderAuth` générique (W6).
- HTTP Request node (W7) :
  ```
  authentication      = predefinedCredentialType
  nodeCredentialType  = nocoDbApiToken
  ```
- **URL interne** (W8) : `http://nocodb:8080/api/v3/…` (réseau Docker), **jamais** l'URL publique (qui passe par Cloudflare Access → 302).

## Workflow → workflow comme building blocks (W23)

Un workflow public peut en appeler un autre via HTTP standard sur le réseau interne :

```
HTTP Request → http://n8n:5678/webhook/api/wms/piece/transfer
```

Plus simple que le node `Execute Workflow`, transparent au runtime, permet de réutiliser des endpoints comme briques (`/picking/assign` → `/piece/transfer` ; `/reparation/valider-panne` → `/mouvement-stock`). Latence +~100 ms/hop, acceptable en POC.

---

## Patterns d'architecture (P1/P2)

- **P1 — le front orchestre l'atomicité** : pour une opération multi-tables (commande+lignes, picking+mouvement), faire **N appels séquentiels côté front** avec gestion d'erreur, plutôt qu'un workflow géant atomique. Moins de risque, plus simple à débugger. (POC : la non-atomicité est acceptable.)
- **P2 — résolution FK côté front** : exposer `/{ressource}-detail?id=X` qui résout les FK d'**un** record (via `/links`, cf. `spark-nocodb-v3-patterns`). Le front fait `Promise.all` sur une liste. Tient jusqu'à ~50 records.

---

## Outils MCP n8n — réflexes (W12-W16, W18)

- **Valider avant d'activer** : `n8n_validate_workflow` (errors + warnings).
- **Activer** : `activateWorkflow` via `n8n_update_partial_workflow` (plus pratique que l'UI).
- **Débugger une erreur** : `n8n_executions action=get id=X includeData=true` → payload + erreur node par node. **Outil n°1.**
- **Copier un pattern existant** : `n8n_get_workflow`.
- **W18** : un `n8n_update_partial_workflow` est actif **immédiatement** (pas de reload webhook).
- **W22/N-MCP** : `patchNodeField` ne patche pas `parameters.assignments.assignments` (object) → `updateNode` avec l'array complet. `n8n_update_full_workflow` exige `name` (sinon 422).

---

## Squelette d'un endpoint d'écriture type

```
[Webhook POST /api/wms/commande]
        │  $json.body.{…}
        ▼
[Code "Validate"]   throw Error si invalide (W10)
        ▼
[Code "Prep body"]  insert_body = JSON.stringify({fields:{…}})  (W3)
        ▼
[HTTP POST nocodb:8080 /records]   jsonBody = ={{ $json.insert_body }}  (W7/W8)
        ▼
[HTTP POST /links/{field}/{records[0].id}]   [{id: fk}]   (N3/N4)
        ▼
[Code "Build Response"]   séquentiel, pas de parallèle (W9)
```

> Charger **aussi** `spark-nocodb-v3-patterns` avant de construire : 90 % des bugs d'un endpoint Spark viennent de la couche NocoDB (N3, Links, bulk), pas de n8n.
