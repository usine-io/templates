# Step 05 — Versionning des workflows n8n (placeholder)

> ⏳ **Pas encore implémenté.** Spec à fleshout, pas de scripts.

## Pourquoi cette étape

Les workflows n8n vivent dans la DB Postgres (table `workflow_entity`) — donc couverts par le backup 3-2-1 du step 04. Mais ça ne suffit pas pour :

- **Voir l'historique fonctionnel** d'un workflow (qui a changé quoi, quand, pourquoi)
- **Code review** des changements de logique métier
- **Rollback ciblé** sur une seule modification (sans restore complet de DB)
- **Promotion entre instances** (dev → prod, ou copie d'un workflow d'un site Spark à un autre)

`wiki/topics/architecture-technique.md` §5.3 flag ce sujet "provisoire" — il faut un système de **sync workflow ↔ git**.

## Prérequis

- step 02 ✅ (l'API n8n marche)

## Plan d'action (à dérouler quand on attaquera)

### Phase 1 — Stratégie à arbitrer

Trois patterns possibles :

| Pattern | Pro | Contre |
|---|---|---|
| **(a) Export-on-demand** : script `n8n-export.sh` que l'humain lance manuellement après avoir édité un flow → commit dans `infra/workflows/` | simple, sous contrôle | discipline humaine requise, oublis fréquents |
| **(b) Cron périodique** : toutes les heures, export tous les flows → diff → commit auto si changements | aucun oubli | bruit dans l'historique, commits sans contexte ("auto-export 14:00") |
| **(c) Hook UI** : webhook sur "save workflow" côté n8n → trigger un export commit | propre, un commit par changement | n8n n'expose pas de hook "save", il faut bricoler |

**Reco a priori** : (a) — simple, suffisant pour 1-5 workflows, low-tech. Si on dépasse 20 workflows on bascule (b).

### Phase 2 — Scripts à livrer

- `infra/scripts/workflows/export-all.sh` : `GET /api/v1/workflows` → pour chaque flow, `GET /api/v1/workflows/{id}` → écrit `infra/workflows/<flow-name>.json` (filename = sanitized name)
- `infra/scripts/workflows/import-one.sh` : prend un fichier JSON en argument → POST/PUT vers n8n
- `infra/scripts/workflows/diff.sh` : compare l'état n8n vs `infra/workflows/` → liste les flows qui ont divergé

### Phase 3 — Convention git

- Les exports sont **committés dans le repo client** (`infra/workflows/<flow>.json`)
- Pas dans le repo template — chaque site a ses propres workflows
- Branche : `main` directement (changements rarement gros), ou `feat/workflow-X` si l'auteur veut review

### Phase 4 — Validation

- Modifier un workflow en UI → exporter → diff montre la différence
- Importer un workflow exporté sur une instance vierge → fonctionne identique
- Re-importer un workflow déjà existant (par nom ou ID) → idempotent

## Découvertes anticipées

- Exports n8n ne contiennent **pas** les credentials (les IDs sont référencés mais les secrets restent côté n8n vault). Donc safe pour git.
- Les IDs des nodes/credentials peuvent varier entre instances — d'où le système de placeholders du step 02 (`__NOCODB_CRED_ID__` etc.). À étendre comme convention.
- Si on synchronise un même workflow entre 2 sites Spark, les références à des tables/credentials seront différentes. C'est le problème de la **promotion cross-site** — différer pour l'instant.

## Sources

- `wiki/topics/architecture-technique.md` §5.3 (flag provisoire)
- Doc n8n API : https://docs.n8n.io/api/api-reference/
