#!/usr/bin/env bash
# lib.sh — helpers communs aux scripts de backup Spark.
#
# GÉNÉRIQUE : aucun nom de client en dur. Le nom de projet Compose est résolu
# depuis `name:` dans docker-compose.yml, et les conteneurs/volumes sont
# retrouvés via les LABELS Docker Compose (robuste, indépendant du nommage
# hyphen/underscore selon la version de compose). Vocation : remonter tel quel
# dans spark-kit/templates.
#
# Surcouches d'env (toutes optionnelles) :
#   SPARK_PROJECT                  nom de projet compose (défaut: champ `name:`)
#   SPARK_BACKUP_DIR               racine des backups (défaut: $HOME/spark-backups)
#   SPARK_BACKUP_RETENTION_DAYS    rétention locale en jours (défaut: 7)
set -euo pipefail

# --- chemins -----------------------------------------------------------------
BACKUP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$BACKUP_LIB_DIR/../.." && pwd)"      # infra/scripts/backup -> infra
COMPOSE_FILE="$INFRA_DIR/docker-compose.yml"

# --- nom de projet -----------------------------------------------------------
PROJECT="${SPARK_PROJECT:-$(awk '/^name:/{print $2; exit}' "$COMPOSE_FILE" 2>/dev/null)}"
[[ -n "${PROJECT:-}" ]] || { echo "FATAL: projet compose introuvable (renseigner SPARK_PROJECT ou 'name:' dans $COMPOSE_FILE)" >&2; exit 1; }

# --- destination -------------------------------------------------------------
BACKUP_ROOT="${SPARK_BACKUP_DIR:-$HOME/spark-backups}/$PROJECT"
RETENTION_DAYS="${SPARK_BACKUP_RETENTION_DAYS:-7}"

# --- logging -----------------------------------------------------------------
log() { printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${BACKUP_TAG:-backup}" "$*"; }
die() { log "FATAL: $*"; exit 1; }

# --- helpers docker ----------------------------------------------------------
# Conteneur d'un service compose (par label) -> id du conteneur running, ou vide.
compose_container() {
  docker ps -q \
    --filter "label=com.docker.compose.project=$PROJECT" \
    --filter "label=com.docker.compose.service=$1"
}

# Tous les volumes nommés du projet (par label).
project_volumes() {
  docker volume ls -q --filter "label=com.docker.compose.project=$PROJECT"
}

# Supprime dans $1 les fichiers matchant $2 plus vieux que RETENTION_DAYS.
prune_old() {
  local dir="$1" pattern="$2"
  [[ -d "$dir" ]] || return 0
  find "$dir" -maxdepth 1 -type f -name "$pattern" -mtime "+$RETENTION_DAYS" -print -delete 2>/dev/null || true
}
