#!/usr/bin/env bash
# rclone-push.sh — couche OFFSITE du 3-2-1 : pousse les backups locaux vers
# Backblaze B2 avec une rétention propre (par défaut 30j, indépendante du 7j local).
#
# CHOIX DE CONCEPTION :
#  1. `rclone copy` (additif), PAS `rclone sync`. sync mirroir-erait les
#     suppressions locales (le pruning 7j local effacerait l'offsite) → on perdrait
#     la rétention longue. copy n'ajoute que les nouveaux fichiers ; la rétention
#     B2 est gérée séparément par `rclone delete --min-age`.
#  2. Remote rclone monté via VARIABLES D'ENV (RCLONE_CONFIG_*), pas via
#     `rclone config`. Les creds restent dans infra/.env (source unique), aucun
#     secret écrit dans ~/.config/rclone, jamais affiché.
#
# Creds attendus dans infra/.env :
#   B2_ACCOUNT_ID         keyID Backblaze (Application Key ID)
#   B2_APPLICATION_KEY    applicationKey
#   B2_BUCKET             nom du bucket
#   B2_RETENTION_DAYS     optionnel (défaut 30)
#
# Usage : rclone-push.sh [--dry-run]
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BACKUP_TAG="rclone-push"

command -v rclone >/dev/null 2>&1 || die "rclone absent (brew install rclone)"

ENV_FILE="$INFRA_DIR/.env"
[[ -f "$ENV_FILE" ]] || die "infra/.env introuvable ($ENV_FILE)"
# Lit une clé de .env sans l'afficher.
read_env() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^"//; s/"$//' || true; }

B2_KEY_ID="$(read_env B2_ACCOUNT_ID)"
B2_APP_KEY="$(read_env B2_APPLICATION_KEY)"
B2_BUCKET="$(read_env B2_BUCKET)"
B2_RETENTION_DAYS="$(read_env B2_RETENTION_DAYS)"; B2_RETENTION_DAYS="${B2_RETENTION_DAYS:-30}"

if [[ -z "$B2_KEY_ID" || -z "$B2_APP_KEY" || -z "$B2_BUCKET" ]]; then
  die "creds B2 manquants dans $ENV_FILE. Renseigner B2_ACCOUNT_ID / B2_APPLICATION_KEY / B2_BUCKET (cf. setup/04 — Phase humaine B2)."
fi

[[ -d "$BACKUP_ROOT" ]] || die "rien à pousser : $BACKUP_ROOT n'existe pas (lancer pg-dump.sh / volumes-tar.sh d'abord)"

DRY=""
[[ "${1:-}" == "--dry-run" ]] && { DRY="--dry-run"; log "MODE DRY-RUN (aucune écriture B2)"; }

# Remote éphémère piloté par l'env — les creds ne touchent jamais le disque.
export RCLONE_CONFIG_SPARKB2_TYPE="b2"
export RCLONE_CONFIG_SPARKB2_ACCOUNT="$B2_KEY_ID"
export RCLONE_CONFIG_SPARKB2_KEY="$B2_APP_KEY"
REMOTE="sparkb2:${B2_BUCKET}/${PROJECT}"

log "vérification accès bucket '$B2_BUCKET'..."
rclone lsd "sparkb2:${B2_BUCKET}" >/dev/null 2>&1 || die "accès B2 KO (creds/bucket invalides, ou key pas autorisée sur ce bucket)"

log "copy $BACKUP_ROOT -> $REMOTE (logs/ exclus)"
rclone copy "$BACKUP_ROOT" "$REMOTE" \
  --exclude "logs/**" \
  --fast-list --transfers 4 --log-level NOTICE $DRY \
  || die "rclone copy a échoué"

log "rétention offsite : suppression > ${B2_RETENTION_DAYS}j sur $REMOTE"
rclone delete "$REMOTE" --min-age "${B2_RETENTION_DAYS}d" --rmdirs --log-level NOTICE $DRY \
  || log "WARN: delete --min-age a renvoyé != 0 (non bloquant)"

# B2 versionne : delete ne fait que masquer. cleanup purge réellement les versions cachées.
if [[ -z "$DRY" ]]; then
  rclone cleanup "$REMOTE" --log-level NOTICE 2>/dev/null \
    || log "WARN: cleanup non effectué (lifecycle bucket prendra le relais)"
fi

log "✅ offsite à jour ($REMOTE, rétention ${B2_RETENTION_DAYS}j)"
