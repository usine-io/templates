#!/usr/bin/env bash
# volumes-tar.sh — archive tar.gz des volumes Docker nommés du projet.
#
# Complément indispensable au pg-dump : NocoDB stocke ses MÉTADONNÉES dans
# Postgres mais ses PIÈCES JOINTES dans le volume nocodb_data ; n8n_data porte
# la clé de chiffrement + binaryData. Donc le dump SQL seul ne suffit pas.
#
# Exclusions par défaut :
#   - postgres_data : couvert (logiquement) par pg-dump ; un tar à chaud serait
#     incohérent. Pour l'inclure quand même : SPARK_BACKUP_VOLUME_EXCLUDE="caddy_logs"
#   - caddy_logs    : régénérable (logs d'accès).
# Surcharge via SPARK_BACKUP_VOLUME_EXCLUDE="short_name1 short_name2".
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BACKUP_TAG="volumes-tar"

EXCLUDE="${SPARK_BACKUP_VOLUME_EXCLUDE:-postgres_data caddy_logs}"
TAR_IMAGE="${SPARK_TAR_IMAGE:-alpine:3}"

dest="$BACKUP_ROOT/volumes"
mkdir -p "$dest"
stamp="$(date '+%Y%m%d-%H%M%S')"

is_excluded() { local s="$1" e; for e in $EXCLUDE; do [[ "$s" == "$e" ]] && return 0; done; return 1; }

count=0
for vol in $(project_volumes); do
  short="$(docker volume inspect "$vol" --format '{{index .Labels "com.docker.compose.volume"}}' 2>/dev/null)"
  [[ -n "$short" ]] || short="${vol#"${PROJECT}_"}"
  if is_excluded "$short"; then log "skip $short (exclu)"; continue; fi

  fname="vol-${short}-${stamp}.tar.gz"
  log "tar volume $vol ($short) -> $fname"
  # Helper container : monte le volume en RO et le dossier de dest, tar dedans.
  if docker run --rm -v "$vol":/src:ro -v "$dest":/dest "$TAR_IMAGE" \
       tar czf "/dest/$fname.partial" -C /src . ; then
    mv "$dest/$fname.partial" "$dest/$fname"
    log "ok: $fname ($(du -h "$dest/$fname" | cut -f1))"
    count=$((count+1))
  else
    rm -f "$dest/$fname.partial"
    log "WARN: échec tar de $vol"
  fi
  prune_old "$dest" "vol-${short}-*.tar.gz"
done

log "terminé: $count volume(s) archivé(s), rétention ${RETENTION_DAYS}j"
