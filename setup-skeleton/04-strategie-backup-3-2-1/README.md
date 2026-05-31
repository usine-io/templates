# Step 04 — Stratégie de backup 3-2-1

> ✅ **Couches locales + offsite livrées** dans `scripts/` (génériques, à copier dans `infra/scripts/backup/` du repo client). Drill de restore = critère de validation.
> ⏳ **Reste côté client** : configurer un remote rclone (provider au choix) + `SPARK_OFFSITE_REMOTE` dans `.env` (le script `rclone-push.sh` est prêt), activer le cron/launchd, brancher la notif si la drill échoue.

## Pourquoi cette étape

`wiki/topics/architecture-technique.md` §2.3 spécifie une stratégie 3-2-1 :

| Couche | Méthode | Fréquence | Rétention | État |
|---|---|---|---|---|
| PostgreSQL | `pg_dumpall` → `.sql.gz` | 6h | 7j local | ✅ |
| Volumes Docker | `tar` des volumes nommés | quotidien | 7j local | ✅ |
| Offsite | `rclone copy` → remote au choix (B2/S3/Drive/SFTP…) | quotidien | 30j | ✅ (remote client) |
| USB | copie locale (optionnel) | hebdo | 4 semaines | ⏳ |

Un dump est inutile s'il n'est pas restaurable → la **drill de restore** est le critère de validation, et elle est livrée.

## Installation dans un repo client

Les scripts de `scripts/` sont **génériques** (aucun nom de client en dur). À l'instanciation :

```bash
cp setup-skeleton/04-strategie-backup-3-2-1/scripts/* infra/scripts/backup/
chmod +x infra/scripts/backup/*.sh
```

Ils résolvent le projet via le champ `name:` de `infra/docker-compose.yml`, et retrouvent conteneurs/volumes via les **labels Docker Compose** (`com.docker.compose.project` / `.service` / `.volume`) — robuste quel que soit le nommage hyphen/underscore selon la version de compose. Le chemin relatif `../../` suppose le placement `infra/scripts/backup/`.

Config par variables d'env (toutes optionnelles) :

| Variable | Défaut | Rôle |
|---|---|---|
| `SPARK_PROJECT` | champ `name:` du compose | nom de projet compose |
| `SPARK_BACKUP_DIR` | `$HOME/spark-backups` | racine des backups (hors-repo) |
| `SPARK_BACKUP_RETENTION_DAYS` | `7` | rétention locale |
| `SPARK_BACKUP_VOLUME_EXCLUDE` | `postgres_data caddy_logs` | volumes non tarés |
| `SPARK_OFFSITE_REMOTE` | *(vide → offsite inerte)* | remote rclone parent, ex `b2:bucket` / `s3:bucket/prefix` / `gdrive:spark` |
| `SPARK_OFFSITE_RETENTION_DAYS` | `30` | rétention offsite |

## Scripts livrés (`scripts/`)

- `lib.sh` — helpers communs (résolution projet/conteneur/volumes par labels, logging, purge rétention).
- `pg-dump.sh` ✅ — `pg_dumpall` (toutes bases + rôles) → `.sql.gz`. Couvre n8n **et** les métadonnées NocoDB (qui vivent dans Postgres). Auth locale `trust` dans le conteneur → aucun mot de passe manipulé. Rotation 7j.
- `volumes-tar.sh` ✅ — tar.gz de chaque volume nommé. Exclut par défaut `postgres_data` (couvert logiquement par le dump ; un tar à chaud serait incohérent) et `caddy_logs` (régénérable). **`nocodb_data` est tarré** : NocoDB met ses métadonnées dans PG mais ses **pièces jointes** dans ce volume.
- `restore-drill.sh` ✅ — monte un Postgres jetable, restaure le dernier dump, compte tables + workflows, détruit le conteneur. **Non-destructif** (zéro write sur la prod).
- `install-launchd.sh` ✅ (macOS) — écrit 3 LaunchAgents (`com.spark.<projet>.{pg-dump,volumes-tar,restore-drill}`). N'active rien sans `--load`. Sur Linux : transposer en cron/systemd timer.
- `rclone-push.sh` ✅ — offsite **agnostique au provider** (n'importe quel backend rclone : B2, S3/MinIO, Google Drive, OneDrive, SFTP, WebDAV…). **`rclone copy`** (additif), PAS `sync` : sync mirroir-erait le pruning local et casserait la rétention offsite longue. Rétention gérée à part par `rclone delete --min-age` (+ `cleanup` best-effort pour backends versionnés type B2). Cible = `SPARK_OFFSITE_REMOTE` ; auth au choix via `rclone config` **ou** `RCLONE_CONFIG_*` dans `.env` (le script les charge). **Inerte** tant que `SPARK_OFFSITE_REMOTE` absent. `SPARK_OFFSITE_RETENTION_DAYS` (défaut 30). Supporte `--dry-run`.
- `usb-copy.sh` ⏳ (optionnel) — rsync vers `/Volumes/SPARK_BACKUP` si monté.

> ⚠️ Le tableau §2.3 du wiki dit « rclone **sync** » : c'est une approximation. On livre un **copy** + delete-by-age, sinon la rétention offsite longue (30j) est incompatible avec le pruning local court (7j).

## Phase humaine — offsite, provider au choix (préalable à `rclone-push.sh`)

Choisir un provider, exposer un **remote rclone**, pointer le script dessus. Auth au choix :
- **`rclone config`** (interactif) → remote nommé dans `~/.config/rclone/rclone.conf`. Recommandé pour Google Drive / OneDrive / Dropbox (OAuth).
- **`RCLONE_CONFIG_<NOM>_*`** dans `infra/.env` → créds gardés avec le reste, rien dans `~/.config/rclone`. Pratique pour B2 / S3.

Puis `SPARK_OFFSITE_REMOTE=<remote>:<bucket-ou-dossier>` dans `infra/.env` (le script ajoute `/<projet>`). Exemples :
- **Backblaze B2** : `RCLONE_CONFIG_OFF_TYPE=b2` + `_ACCOUNT=<keyID>` + `_KEY=<appKey>` → `SPARK_OFFSITE_REMOTE=off:mon-bucket`
- **S3 / MinIO** : `RCLONE_CONFIG_OFF_TYPE=s3` (+ `_PROVIDER`/`_ACCESS_KEY_ID`/`_SECRET_ACCESS_KEY`) → `SPARK_OFFSITE_REMOTE=off:mon-bucket/backups`
- **Drive / OneDrive / SFTP / …** : `rclone config` puis `SPARK_OFFSITE_REMOTE=<nom>:spark`

> Chaque installateur fait « à sa sauce » — le script ne présuppose aucun provider.

## Planification (cron launchd, livré, à activer côté client)
`install-launchd.sh` écrit dans `~/Library/LaunchAgents` :
- `pg-dump` → toutes les 6h (`StartInterval 21600`)
- `volumes-tar` → quotidien 03:00
- `restore-drill` → dimanche 04:00

Activer : `bash infra/scripts/backup/install-launchd.sh --load`. *(TODO: notifier Kuma si la drill échoue.)*

## Validation (definition of done)
1. `bash infra/scripts/backup/pg-dump.sh` → un `.sql.gz` non vide apparaît.
2. `bash infra/scripts/backup/volumes-tar.sh` → un `.tar.gz` par volume non exclu.
3. `bash infra/scripts/backup/restore-drill.sh` → **PASS** (tables + workflows restaurés dans le conteneur jetable, puis nettoyé).
4. Optionnel : forcer un run sous launchd (`launchctl kickstart -k gui/$(id -u)/com.spark.<projet>.pg-dump`) pour valider l'environnement PATH/HOME — piège n°1 des crons.

## Découvertes / décisions

- `pg_dumpall` plutôt que `pg_dump` : on veut TOUS les rôles + les 3 bases (postgres, n8n, nocodb) en un fichier restaurable d'un coup.
- Résolution par **labels Compose**, pas par nom de conteneur : `${PREFIX}-postgres-1` vs `${PREFIX}_postgres_1` dépend de la version compose → fragile. Le label est stable.
- La drill de restore est **le critère de validation** — un backup non-testé n'est pas un backup.
- rclone gère ~70 backends de façon uniforme (B2, S3, Drive, SFTP…) → on reste **agnostique**, l'installateur choisit son provider (config interactive ou `RCLONE_CONFIG_*`).

## Sources

- `wiki/topics/architecture-technique.md` §2.3 (table des couches)
- Backends rclone (liste + config par provider) : https://rclone.org/overview/
- Best practices PG backup : `pg_dumpall` vs `pg_basebackup` (on reste sur pg_dumpall pour simplicité, basebackup pour PITR un autre jour)
