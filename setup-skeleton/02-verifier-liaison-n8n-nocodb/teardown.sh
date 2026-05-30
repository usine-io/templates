#!/usr/bin/env bash
# teardown.sh — Step 02 cleanup. Idempotent : ré-exécutable, ignore les objets déjà supprimés.
#
# Supprime dans cet ordre (pour stopper les triggers d'abord) :
#   1. Hook NocoDB AFTER INSERT
#   2. Flows n8n (deactivate puis delete)
#   3. Credential n8n
#   4. Tables NocoDB
#   5. Base NocoDB _t_smoke
#   6. Strip des vars de step 02 dans infra/.env
#
# Garde les exports JSON (n8n-flow-*.json, nocodb-schema.json) — c'est de la doc.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="$REPO_ROOT/infra/.env"
[[ -f "$ENV_FILE" ]] || { echo "✗ $ENV_FILE introuvable" >&2; exit 1; }
set -a; source "$ENV_FILE"; set +a

# URLs construites depuis SPARK_PREFIX et SPARK_DOMAIN
NOCODB="https://${SPARK_PREFIX}-db.${SPARK_DOMAIN}"
N8N="https://${SPARK_PREFIX}-n8n.${SPARK_DOMAIN}"

log() { echo "[teardown.sh] $*"; }

# Helper: DELETE silencieux, ignore les 404
delete_silent() {
    local url="$1" auth_h="$2"
    local code
    code=$(curl -sS -o /dev/null -w "%{http_code}" -X DELETE -H "$auth_h" "$url" || echo "000")
    [[ "$code" =~ ^(200|204|404)$ ]]
}

# ─── 1. Hook NocoDB ───
if [[ -n "${NOCODB_HOOK_ID_PINGS_INSERT:-}" ]]; then
    log "Suppression hook $NOCODB_HOOK_ID_PINGS_INSERT..."
    delete_silent "$NOCODB/api/v2/meta/hooks/$NOCODB_HOOK_ID_PINGS_INSERT" "xc-token: $NOCODB_API_TOKEN" \
        && log "  ✓"
fi

# ─── 2. Flows n8n ───
for var in N8N_FLOW_ID_PING N8N_FLOW_ID_ECHO; do
    fid="${!var:-}"
    [[ -n "$fid" ]] || continue
    log "Suppression flow n8n $fid..."
    curl -sS -X POST -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N/api/v1/workflows/$fid/deactivate" >/dev/null 2>&1 || true
    delete_silent "$N8N/api/v1/workflows/$fid" "X-N8N-API-KEY: $N8N_API_KEY" \
        && log "  ✓"
done

# ─── 3. Credential n8n ───
if [[ -n "${N8N_CRED_ID_NOCODB:-}" ]]; then
    log "Suppression credential n8n $N8N_CRED_ID_NOCODB..."
    delete_silent "$N8N/api/v1/credentials/$N8N_CRED_ID_NOCODB" "X-N8N-API-KEY: $N8N_API_KEY" \
        && log "  ✓"
fi

# ─── 4. Tables NocoDB ───
for var in NOCODB_TABLE_ID_PINGS NOCODB_TABLE_ID_ECHOES; do
    tid="${!var:-}"
    [[ -n "$tid" ]] || continue
    log "Suppression table NocoDB $tid..."
    delete_silent "$NOCODB/api/v2/meta/tables/$tid" "xc-token: $NOCODB_API_TOKEN" \
        && log "  ✓"
done

# ─── 5. Base NocoDB ───
if [[ -n "${NOCODB_BASE_ID_SMOKE:-}" ]]; then
    log "Suppression base NocoDB $NOCODB_BASE_ID_SMOKE..."
    delete_silent "$NOCODB/api/v2/meta/bases/$NOCODB_BASE_ID_SMOKE" "xc-token: $NOCODB_API_TOKEN" \
        && log "  ✓"
fi

# ─── 6. Cleanup .env ───
log "Strip des vars step 02 dans $ENV_FILE..."
for v in NOCODB_BASE_ID_SMOKE NOCODB_SOURCE_ID_SMOKE \
         NOCODB_TABLE_ID_PINGS NOCODB_TABLE_ID_ECHOES \
         NOCODB_HOOK_ID_PINGS_INSERT \
         N8N_FLOW_ID_PING N8N_FLOW_ID_ECHO N8N_CRED_ID_NOCODB; do
    sed -i.bak "/^$v=/d" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
done
log "  ✓"

log ""
log "✓ Teardown step 02 complet. Les artefacts JSON restent committés dans le repo."
