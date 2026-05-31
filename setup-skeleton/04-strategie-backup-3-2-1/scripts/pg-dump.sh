#!/usr/bin/env bash
# pg-dump.sh — dump logique de TOUTES les bases + rôles (pg_dumpall) -> .sql.gz.
#
# Couvre n8n (workflows, credentials, exécutions) ET les métadonnées NocoDB,
# qui vivent dans Postgres (NC_DB_JSON). pg_dumpall (et pas pg_dump) car on veut
# les 3 bases + les rôles en un seul fichier restaurable d'un coup.
# Auth locale = trust dans le conteneur (pg_hba `local all all trust`) -> pas de
# mot de passe à manipuler.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BACKUP_TAG="pg-dump"

C="$(compose_container postgres)"
[[ -n "$C" ]] || die "conteneur postgres non démarré pour le projet '$PROJECT'"

dest="$BACKUP_ROOT/postgres"
mkdir -p "$dest"
stamp="$(date '+%Y%m%d-%H%M%S')"
out="$dest/pg-$stamp.sql.gz"
tmp="$out.partial"

log "pg_dumpall (toutes bases + rôles) depuis $C -> $out"
if docker exec -u postgres "$C" pg_dumpall -U postgres | gzip -c > "$tmp"; then
  mv "$tmp" "$out"
  log "ok: $out ($(du -h "$out" | cut -f1))"
else
  rm -f "$tmp"
  die "pg_dumpall a échoué"
fi

prune_old "$dest" 'pg-*.sql.gz'
log "rétention: fichiers > ${RETENTION_DAYS}j purgés"
