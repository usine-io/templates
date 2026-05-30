# Step 00 — Générer les secrets `.env`

> Génère les secrets de la stack (5 entrées) avec un alphabet **URL-safe ET JSON-safe** (`A-Za-z0-9-_`, 32 caractères).
> **Pourquoi cet alphabet** : les secrets `openssl rand -base64` peuvent contenir `&`, `=`, `+`, `/`, `%` qui cassent les confs URL-based (cf. INC-2026-05-05 dans `spark-kit/spark-kit/INCIDENTS.md`). Cet alphabet survit à : URL, query string, JSON inline, shell, ligne de commande.

## Quand l'utiliser

À l'**installation initiale** d'un nouveau site Spark, **avant** le premier `docker-compose up`.

Pour un site déjà déployé, c'est terminé — ne pas relancer (ça ne touche pas le `.env` existant, mais ne sert à rien).

## Procédure

```bash
cd setup/00-generer-secrets-env
./generate.sh
```

Le script imprime 5 lignes `KEY=valeur` sur stdout. À toi de les rediriger vers `.env` :

```bash
./generate.sh >> ../../infra/.env
```

⚠️ **Ne JAMAIS** lancer ça sur une `.env` existante peuplée — ça doublerait les clés (Docker prendrait la dernière mais c'est désordre). Vérifier `cat ../../infra/.env` avant.

## Variables générées

- `POSTGRES_ROOT_PASSWORD`
- `N8N_DB_PASSWORD`
- `NOCODB_DB_PASSWORD`
- `N8N_ENCRYPTION_KEY`
- `NC_AUTH_JWT_SECRET`

## Variables **non** générées (à compléter à la main)

Voir `infra/.env.example` :
- `SPARK_DOMAIN`, `SPARK_PREFIX`, `SPARK_TUNNEL_ID`, `SPARK_TUNNEL_CONFIG`, `SPARK_HOST_HTTP_PORT` — config par-site
- `CF_API_TOKEN`, `CF_ZONE_ID` — Cloudflare API (créés en UI)

## Validation

```bash
./generate.sh | grep -Ec '^[A-Z0-9_]+=[A-Za-z0-9_-]{32}$'
# attendu : 5
```

Compatible BSD grep (macOS) — utilise `-E` (ERE) pour `+` et `{32}` sans backslashes. La classe `[A-Z0-9_]` côté clé est nécessaire parce que certaines vars contiennent des chiffres (ex: `N8N_DB_PASSWORD`).
