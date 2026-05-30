# Skills Spark

Skills Claude Code **propres au kit Spark** — la couche empirique et architecturale du combo `NocoDB v3 + n8n + Caddy + Cloudflare`. Elles **complètent** (ne remplacent pas) les skills tierces génériques `nocodb` et `n8n-*`.

> Pourquoi des skills et pas seulement de la doc/mémoire : une skill se charge **par trigger** pendant le build, est **versionnée dans le kit** (donc transférable à tout nouveau site), là où la mémoire `spark-pitfalls-catalog` reste per-machine et les `docs/*.md` ne s'ouvrent pas spontanément.

## Disponibles

| Skill | Couche | Quand elle se déclenche |
|-------|--------|-------------------------|
| `spark-nocodb-v3-patterns` | data | modélisation, tables/champs NocoDB, workflows lisant/écrivant NocoDB, debug Links/Lookups/filtres |
| `spark-n8n-pseudo-api` | backend | créer/éditer un endpoint webhook n8n adossé à NocoDB, debug jsonBody/IF/parallèle |

Contenu source : mémoire `spark-pitfalls-catalog` (pièges N1-N25, W1-W23, P1-P2) + `docs/pieges-nocodb-n8n.md`.

## Backlog (P2/P3, à créer)

- `spark-frontend-patterns` — fronts statiques (F1 noms réservés, skeleton+slot, login localStorage, download Blob, webhooks relatifs CF Access, anti-pattern iframe, cache CF `?v=N`).
- `spark-stack-ops` — Caddy/Docker/Cloudflare/secrets (bind mounts C1-C6, `NC_DB_JSON`, Colima, tunnel pattern A).
- `spark-poc-method` — discovery → fiche → PRD → script E2E ; prepare-then-connect ; référentiel-cible vs entité 1er ordre ; Form natif vs pseudo-API.

## Installation

Les skills sont globales (`~/.claude/skills/`, une fois par poste). Copier les dossiers `spark-*` de ce répertoire vers `~/.claude/skills/` :

```bash
cp -R spark-* ~/.claude/skills/
```

Vérifier : au démarrage d'une session Claude Code dans un repo Spark, `/skill spark-nocodb-v3-patterns` doit être listée.

## Convention

Une skill Spark = un dossier `spark-<sujet>/` avec un `SKILL.md` (frontmatter `name` + `description`-trigger). Elle porte des **patterns confirmés et généralisables** — pas des incidents ponctuels (→ `spark-kit/INCIDENTS.md`) ni la référence API brute (→ skills `nocodb`/`n8n-*`). Tout nouveau piège transverse se promeut ici **et** dans `INCIDENTS.md`.
