#!/usr/bin/env bash
# rclone-push.sh — couche OFFSITE du 3-2-1 : pousse les backups locaux vers
# n'IMPORTE QUEL backend supporté par rclone (S3, Backblaze B2, Google Drive,
# OneDrive, Dropbox, SFTP, WebDAV… ~70 backends). Le script est AGNOSTIQUE au
# provider : c'est l'installateur qui configure son remote « à sa sauce ».
#
# CHOIX DE CONCEPTION :
#  1. `rclone copy` (additif), PAS `rclone sync`. sync mirroir-erait les
#     suppressions locales (le pruning local court effacerait l'offsite) → on
#     perdrait la rétention longue. La rétention offsite est gérée séparément par
#     `rclone delete --min-age`.
#  2. Aucun backend en dur. La destination est un remote rclone donné par
#     SPARK_OFFSITE_REMOTE. L'auth est au choix de l'installateur :
#       a) `rclone config` → remote nommé dans ~/.config/rclone/rclone.conf, OU
#       b) variables RCLONE_CONFIG_<NOM>_* dans infra/.env (créds gardés au
#          même endroit que le reste, rien écrit dans ~/.config/rclone).
#     Le script charge automatiquement les lignes `RCLONE_*` de .env pour
#     supporter (b) — sans jamais afficher de secret.
#
# Variables (env ou infra/.env) :
#   SPARK_OFFSITE_REMOTE          remote rclone PARENT, ex: "b2:mybucket",
#                                 "s3:bucket/backups", "gdrive:spark", "sftp:/srv".
#                                 Le script y ajoute "/<projet>". OBLIGATOIRE.
#   SPARK_OFFSITE_RETENTION_DAYS  rétention offsite en jours (défaut 30).
#
# Tant que SPARK_OFFSITE_REMOTE n'est pas défini, le script est INERTE (exit 1
# explicite) — sans danger s'il est planifié avant configuration.
#
# Usage : rclone-push.sh [--dry-run]
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BACKUP_TAG="rclone-push"

command -v rclone >/dev/null 2>&1 || die "rclone absent (brew install rclone)"

ENV_FILE="$INFRA_DIR/.env"
[[ -f "$ENV_FILE" ]] || die "infra/.env introuvable ($ENV_FILE)"
read_env() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^"//; s/"$//' || true; }

# Charge la config rclone éventuellement portée par .env (option b) — créds inclus,
# jamais affichés. Supporte les valeurs avec espaces ou '='.
while IFS= read -r _l; do [[ -n "$_l" ]] && export "$_l"; done \
  < <(grep -E '^RCLONE_[A-Za-z0-9_]+=' "$ENV_FILE" 2>/dev/null || true)

DEST="${SPARK_OFFSITE_REMOTE:-$(read_env SPARK_OFFSITE_REMOTE)}"
RET="${SPARK_OFFSITE_RETENTION_DAYS:-$(read_env SPARK_OFFSITE_RETENTION_DAYS)}"; RET="${RET:-30}"

if [[ -z "$DEST" ]]; then
  die "offsite non configuré : définir SPARK_OFFSITE_REMOTE (remote rclone, ex 'b2:bucket' / 's3:bucket/prefix' / 'gdrive:spark') dans $ENV_FILE. Voir setup/04 (recettes par provider)."
fi

[[ -d "$BACKUP_ROOT" ]] || die "rien à pousser : $BACKUP_ROOT n'existe pas (lancer pg-dump.sh / volumes-tar.sh d'abord)"

DRY=""
[[ "${1:-}" == "--dry-run" ]] && { DRY="--dry-run"; log "MODE DRY-RUN (aucune écriture offsite)"; }

DEST="${DEST%/}"            # pas de slash final en double
TARGET="$DEST/$PROJECT"     # un sous-dossier par site → un même bucket peut héberger plusieurs sites

# mkdir idempotent = vérifie l'accès (auth/remote) ET garantit le chemin (1er run).
log "vérification accès remote '$DEST'..."
rclone mkdir "$TARGET" $DRY 2>/dev/null \
  || die "remote inaccessible : '$DEST'. Vérifier la config rclone (remote nommé ou RCLONE_CONFIG_* dans .env)."

log "copy $BACKUP_ROOT -> $TARGET (logs/ exclus)"
rclone copy "$BACKUP_ROOT" "$TARGET" \
  --exclude "logs/**" \
  --fast-list --transfers 4 --log-level NOTICE $DRY \
  || die "rclone copy a échoué"

log "rétention offsite : suppression > ${RET}j sur $TARGET"
rclone delete "$TARGET" --min-age "${RET}d" --log-level NOTICE $DRY \
  || log "WARN: delete --min-age a renvoyé != 0 (non bloquant)"

# Pour les backends versionnés (B2, S3+versioning, Drive corbeille), delete ne
# fait que masquer ; cleanup purge réellement. Best-effort, no-op ailleurs.
if [[ -z "$DRY" ]]; then
  rclone cleanup "$TARGET" --log-level NOTICE 2>/dev/null \
    || log "WARN: cleanup ignoré (backend sans versions, ou non supporté — la lifecycle du provider prend le relais)"
fi

log "✅ offsite à jour ($TARGET, rétention ${RET}j)"
