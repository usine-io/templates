# Skills Spark

Skills Claude Code **propres au kit Spark** — la couche empirique et architecturale du combo `NocoDB v3 + n8n + Caddy + Cloudflare`. Elles **complètent** (ne remplacent pas) les skills tierces génériques `nocodb` et `n8n-*`.

> Pourquoi des skills et pas seulement de la doc/mémoire : une skill se charge **par trigger** pendant le build, est **versionnée dans le kit** (donc transférable à tout nouveau site), là où la mémoire `spark-pitfalls-catalog` reste per-machine et les `docs/*.md` ne s'ouvrent pas spontanément.

La stack agent Spark s'appuie sur **deux familles** de skills, complémentaires :
le **socle générique tiers** (référence des API n8n / NocoDB) et la **couche Spark** (pièges empiriques + patterns d'assemblage du combo). Les deux doivent être installées sur le poste.

## 1. Socle générique (skills tierces — `n8n-*` + `nocodb`)

Référence des API et des nodes, **génériques** (pas propres à Spark). La skill `nocodb` est embarquée dans ce répertoire ; les 7 skills `n8n-*` sont fournies automatiquement par le serveur MCP n8n (préfixe `n8n-mcp-skills:`).

| Skill | Rôle |
|-------|------|
| `nocodb` | Référence API NocoDB v3 (data CRUD, meta, links, filters, sorts, attachments) **+ CLI `nocodb.sh`** (canal d'action NocoDB) |
| `n8n-workflow-patterns` | Patterns architecturaux de workflow (webhook, CRUD, scheduling, AI agents) |
| `n8n-node-configuration` | Configuration des nodes par type et opération |
| `n8n-expression-syntax` | Syntaxe `{{ }}`, `$json`, `$node`, troubleshooting expressions |
| `n8n-code-javascript` | Code nodes JS (`$input`, `$helpers`, `DateTime`) |
| `n8n-code-python` | Code nodes Python (`_input`, `_json`, limitations) |
| `n8n-validation-expert` | Interprétation des erreurs/warnings de validation |
| `n8n-mcp-tools-expert` | Guide d'utilisation des outils MCP n8n |

## 2. Couche Spark (ce répertoire)

| Skill | Couche | Quand elle se déclenche |
|-------|--------|-------------------------|
| `spark-nocodb-v3-patterns` | data | modélisation, tables/champs NocoDB, workflows lisant/écrivant NocoDB, debug Links/Lookups/filtres |
| `spark-n8n-pseudo-api` | backend | créer/éditer un endpoint webhook n8n adossé à NocoDB, debug jsonBody/IF/parallèle |
| `spark-frontend-patterns` | frontend | créer/éditer une page front, câbler un front aux webhooks, debug bouton inerte / 302 CF / JS périmé |
| `spark-stack-ops` | ops | compose/Caddyfile/volumes, tunnel, secrets, sizing Colima, diagnostic container |
| `spark-poc-method` | méthode | cadrer un POC, écrire une fiche/PRD, choisir une approche d'intégration ou Form vs pseudo-API |

Contenu source : mémoire `spark-pitfalls-catalog` (pièges N/W/C/F/P) + `LESSONS-LEARNED` (bilans PRD) + feedback memories + `docs/*.md`.

**Articulation** : le socle dit *comment marche l'API/le node* ; la couche Spark dit *quel piège t'attend et comment assembler*. En build, charger d'abord les 2 skills Spark P1 (cf. Règle d'or du `CLAUDE.md`), elles renvoient vers le socle au besoin.

## Backlog

Les 5 skills proposées sont livrées. Pistes d'enrichissement futur : `spark-zpl-labels` (gabarits ZPL + impression), `spark-external-connectors` (PhoneCheck/NSYS/Utopya une fois les connecteurs stabilisés).

## Installation

La skill `nocodb` et les skills Spark sont embarquées dans ce répertoire. Les skills `n8n-*` sont fournies par le serveur MCP n8n (pas besoin de les copier). Installation en une commande (une fois par poste) :

```bash
cd ~/spark/templates/skills
cp -R nocodb spark-* ~/.claude/skills/
```

Vérifier : au démarrage d'une session Claude Code dans un repo Spark, `/skill spark-nocodb-v3-patterns` et `/skill nocodb` doivent toutes deux être listées.

## Convention

Une skill Spark = un dossier `spark-<sujet>/` avec un `SKILL.md` (frontmatter `name` + `description`-trigger). Elle porte des **patterns confirmés et généralisables** — pas des incidents ponctuels (→ `spark-kit/INCIDENTS.md`) ni la référence API brute (→ skills `nocodb`/`n8n-*`). Tout nouveau piège transverse se promeut ici **et** dans `INCIDENTS.md`.
