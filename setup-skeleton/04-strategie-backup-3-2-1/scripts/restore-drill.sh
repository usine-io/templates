#!/usr/bin/env bash
# restore-drill.sh — vérifie qu'un dump est RÉELLEMENT restaurable.
#
# « Un backup non testé n'est pas un backup. » Monte un Postgres jetable, y
# restaure le dernier pg-dump, compte les tables/rows, puis détruit le conteneur.
# NON-DESTRUCTIF : ne touche jamais le Postgres de prod (conteneur séparé,
# volume anonyme), aucun write côté stack live.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BACKUP_TAG="restore-drill"

dest="$BACKUP_ROOT/postgres"
latest="$(ls -1t "$dest"/pg-*.sql.gz 2>/dev/null | head -1 || true)"
[[ -n "$latest" ]] || die "aucun dump pg-*.sql.gz dans $dest (lancer pg-dump.sh d'abord)"
log "drill sur : $latest ($(du -h "$latest" | cut -f1))"

PG_IMAGE="${SPARK_PG_IMAGE:-postgres:16}"
name="spark-restore-drill-$$"
cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

log "démarrage Postgres jetable ($PG_IMAGE, conteneur $name)"
docker run -d --rm --name "$name" -e POSTGRES_PASSWORD=drill "$PG_IMAGE" >/dev/null

for _ in $(seq 1 30); do
  docker exec "$name" pg_isready -U postgres >/dev/null 2>&1 && break
  sleep 1
done
docker exec "$name" pg_isready -U postgres >/dev/null 2>&1 || die "le Postgres jetable n'est jamais devenu prêt"

log "restauration du dump..."
if ! gunzip -c "$latest" | docker exec -i "$name" psql -U postgres -q >/dev/null 2>&1; then
  log "psql a renvoyé un code != 0 (souvent bruit 'role already exists') — vérification des données quand même"
fi

fail=0
for db in n8n nocodb; do
  if docker exec "$name" psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$db'" | grep -q 1; then
    tables="$(docker exec "$name" psql -U postgres -d "$db" -tAc "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" | tr -d '[:space:]')"
    log "base '$db' restaurée : $tables tables (public)"
    [[ "${tables:-0}" -gt 0 ]] || { log "WARN: base '$db' a 0 table"; fail=1; }
  else
    log "FAIL: base '$db' absente après restauration"; fail=1
  fi
done

wf="$(docker exec "$name" psql -U postgres -d n8n -tAc "SELECT count(*) FROM workflow_entity" 2>/dev/null | tr -d '[:space:]' || true)"
log "n8n workflow_entity : ${wf:-n/a} workflow(s)"

[[ "$fail" -eq 0 ]] && log "✅ DRILL PASS — le dump est restaurable" || die "❌ DRILL FAILED"
