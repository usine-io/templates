# Référence de la stack d'un site Spark

> Contenu de référence sorti du `CLAUDE.md` (refonte du harnais) : utile à la demande, pas à chaque session.

## Services

| Service | Rôle | Port interne |
|---|---|---|
| n8n | Orchestration, workflows | 5678 |
| NocoDB | Base visuelle, écrans métier | 8080 |
| PostgreSQL 16 | Base relationnelle partagée (utilisateurs séparés : `n8n`, `nocodb`) | 5432 |
| Caddy | Reverse proxy | 80 (lié à `127.0.0.1` uniquement) |
| cloudflared | Tunnel Cloudflare (TLS, accès distant) | sur l'hôte, pas dans Docker |

Caddy tourne avec `auto_https off` : Cloudflare gère le TLS. Caddy injecte `X-Forwarded-Proto https` pour que les
applications se croient en HTTPS.

## Structure d'un repo de site

```
<entreprise>/
├── infra/
│   ├── .env                  secrets (gitignored)
│   ├── .env.example          modèle sans secrets
│   ├── docker-compose.yml
│   ├── config/
│   │   ├── Caddyfile
│   │   └── postgres/init-db.sh
│   ├── apps/                 apps métier statiques (servies par Caddy sur -app)
│   └── scripts/
│       ├── tunnel-up.sh      routes + CNAME Cloudflare
│       ├── tunnel-down.sh    suppression des routes + CNAME
│       └── validate-*.sh     scripts E2E (définition du « fini » de chaque PRD)
├── discovery/
│   ├── onboarding/           questionnaires entreprise
│   ├── fiches/               fiches-logiciel legacy
│   ├── briefs/               briefs de conception (objectif, décisions de l'owner, impact)
│   └── prds/                 PRD des POC
├── LESSONS-LEARNED.md        notes opérationnelles datées
└── CLAUDE.md                 instance du harnais (renvoie au gabarit, n'ajoute que le propre au site)
```

## Clés API (après le premier accès aux applications)

1. **n8n** : Settings → n8n API → Create API Key → `N8N_API_KEY` dans `infra/.env`.
2. **NocoDB** : Team & Settings → Tokens → Add New Token → `NOCODB_API_TOKEN` dans `infra/.env` (PAT `nc_pat_…`).
   Le CLI `nocodb.sh` le lit au moment de l'appel, sans redémarrage.

## Sizing Colima

4 GiB par défaut. Au-delà (stack lourde, LLM locaux en parallèle) : 6 GiB et plus, **seulement sur un Mac de 16 Go
ou plus**. Sur un Mac de 8 Go, la VM et les sessions d'agents se disputent la RAM : surveiller le débit de swap
(`vm_stat`, Swapins/Swapouts), pas seulement son volume. Diagnostic mémoire dans la VM : `docker run --rm alpine free -h`.

## NocoDB CE : pas de vues par API

Sur NocoDB CE, l'API v3 des vues renvoie `ERR_LICENSE_REQUIRED` : impossible de créer ou lister des vues Kanban,
Calendar, Gallery ou Form par programme. Les créer dans l'interface, ou s'en tenir à la grille. Le reste de l'API meta
(tables, champs) fonctionne.

## n8n : credential NocoDB

Dans un node HTTP Request vers NocoDB, utiliser le credential natif `nocoDbApiToken` (« API Token »), pas un Header
Auth générique avec `xc-token` (refusé par certains endpoints).

## n8n : lire des fichiers du repo

Le node « Read/Write Files from Disk » n'accepte par défaut que `/home/node/.n8n-files/`. Monter le dossier voulu
dessous, en lecture seule :

```yaml
# infra/docker-compose.yml, service n8n
volumes:
  - n8n_data:/home/node/.n8n
  - ../discovery:/home/node/.n8n-files/discovery:ro
```

`N8N_RESTRICT_FILE_ACCESS_TO` existe mais n'est pas toujours respecté : préférer le montage.

## Tunnel Cloudflare (pattern A)

Le YAML cloudflared vit sur l'hôte (`~/.cloudflared/config-*.yml`), édité par `infra/scripts/tunnel-up.sh` entre les
marqueurs `# >>> spark-begin` / `# <<< spark-end`. Ne pas éditer ces blocs à la main. Détail : `docs/cloudflared.md`.
