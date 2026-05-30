#!/usr/bin/env bash
# run.sh — Step 02 smoke test n8n ↔ NocoDB.
# Idempotent : crée les objets manquants, skip ce qui existe, lance toujours le test E2E.
#
# Pré-requis : step 01 fait (infra/.env contient N8N_API_KEY, NOCODB_API_TOKEN, NOCODB_WORKSPACE_ID,
#              SPARK_PREFIX, SPARK_DOMAIN).
# Variables persistées au fur et à mesure dans infra/.env (gitignored).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPO_ROOT/infra/.env"
[[ -f "$ENV_FILE" ]] || { echo "✗ $ENV_FILE introuvable — step 00 + 01 d'abord" >&2; exit 1; }

set -a; source "$ENV_FILE"; set +a

# Vars requises
for v in NOCODB_API_TOKEN N8N_API_KEY NOCODB_WORKSPACE_ID SPARK_PREFIX SPARK_DOMAIN; do
    [[ -n "${!v:-}" ]] || { echo "✗ $v manquant dans $ENV_FILE — step 01 d'abord" >&2; exit 1; }
done

# URLs (construites depuis SPARK_PREFIX et SPARK_DOMAIN)
NOCODB_HOST="${SPARK_PREFIX}-db.${SPARK_DOMAIN}"
N8N_HOST="${SPARK_PREFIX}-n8n.${SPARK_DOMAIN}"
NOCODB="https://$NOCODB_HOST"
N8N="https://$N8N_HOST"

log() { echo "[run.sh] $*" >&2; }

upsert_env() {
    local key="$1" val="$2"
    if grep -q "^$key=" "$ENV_FILE"; then
        sed -i.bak "s|^$key=.*|$key=$val|" "$ENV_FILE" && rm "$ENV_FILE.bak"
    else
        echo "$key=$val" >> "$ENV_FILE"
    fi
    export "$key=$val"
}

nocodb_get()  { curl -sS -H "xc-token: $NOCODB_API_TOKEN" "$@"; }
nocodb_post() { curl -sS -X POST -H "xc-token: $NOCODB_API_TOKEN" -H "Content-Type: application/json" "$@"; }
n8n_get()     { curl -sS -H "X-N8N-API-KEY: $N8N_API_KEY" "$@"; }
n8n_post()    { curl -sS -X POST -H "X-N8N-API-KEY: $N8N_API_KEY" -H "Content-Type: application/json" "$@"; }

# ─── 1. Base _t_smoke ───
log "Base _t_smoke..."
existing=$(nocodb_get "$NOCODB/api/v2/meta/workspaces/$NOCODB_WORKSPACE_ID/bases" \
           | jq -r '.list[] | select(.title=="_t_smoke") | .id' | head -1)
if [[ -n "$existing" ]]; then
    BASE_ID="$existing"
    log "  exists ($BASE_ID)"
else
    BASE_ID=$(nocodb_post -d '{"title":"_t_smoke","type":"database"}' \
              "$NOCODB/api/v2/meta/workspaces/$NOCODB_WORKSPACE_ID/bases" | jq -r '.id')
    log "  created ($BASE_ID)"
fi
upsert_env NOCODB_BASE_ID_SMOKE "$BASE_ID"

# ─── 2. Tables _t_pings et _t_echoes ───
ensure_table() {
    local tbl="$1" c1n="$2" c1t="$3" c2n="$4" c2t="$5"
    log "Table $tbl..."
    local existing
    existing=$(nocodb_get "$NOCODB/api/v2/meta/bases/$BASE_ID/tables" \
               | jq -r ".list[] | select(.title==\"$tbl\") | .id" | head -1)
    if [[ -n "$existing" ]]; then
        log "  exists ($existing)"
        printf '%s' "$existing"
    else
        local body
        body=$(jq -nc --arg t "$tbl" --arg n1 "$c1n" --arg t1 "$c1t" --arg n2 "$c2n" --arg t2 "$c2t" \
            '{title:$t, columns:[{title:$n1,uidt:$t1},{title:$n2,uidt:$t2}]}')
        local tbl_id
        tbl_id=$(nocodb_post -d "$body" "$NOCODB/api/v2/meta/bases/$BASE_ID/tables" | jq -r '.id')
        log "  created ($tbl_id)"
        printf '%s' "$tbl_id"
    fi
}

PINGS_ID=$(ensure_table  "_t_pings"  "source"  "SingleLineText" "payload" "LongText")
ECHOES_ID=$(ensure_table "_t_echoes" "ping_id" "Number"         "note"    "LongText")
upsert_env NOCODB_TABLE_ID_PINGS  "$PINGS_ID"
upsert_env NOCODB_TABLE_ID_ECHOES "$ECHOES_ID"

# ─── 3. Credential n8n NocoDB ───
# Note : l'API publique n8n ne permet PAS GET sur /credentials (ni liste ni individual,
# tous renvoient 405 — par design pour pas leak les secrets). On ne peut pas vérifier
# qu'un credential ID est encore valide. On se fie aveuglément à infra/.env :
#   - si N8N_CRED_ID_NOCODB y est, on l'utilise tel quel
#   - sinon on crée + on persiste
# Si quelqu'un a supprimé le credential côté UI sans toucher .env, run.sh continuera de
# référencer un ID périmé et les flows planteront à l'exécution → réponse :
# soit teardown.sh + run.sh, soit unset N8N_CRED_ID_NOCODB dans .env et re-run.
log "Credential n8n NocoDB..."
if [[ -n "${N8N_CRED_ID_NOCODB:-}" ]]; then
    CRED_ID="$N8N_CRED_ID_NOCODB"
    log "  trust .env ($CRED_ID)"
else
    body=$(jq -nc --arg t "$NOCODB_API_TOKEN" \
        '{name:"NocoDB API _t_smoke",type:"httpHeaderAuth",data:{name:"xc-token",value:$t}}')
    CRED_ID=$(n8n_post -d "$body" "$N8N/api/v1/credentials" | jq -r '.id')
    log "  created ($CRED_ID)"
fi
upsert_env N8N_CRED_ID_NOCODB "$CRED_ID"

# ─── 4. Flows n8n ───
prep_flow() {
    sed -e "s|__NOCODB_HOST__|$NOCODB_HOST|g" \
        -e "s|__PINGS_TABLE_ID__|$PINGS_ID|g" \
        -e "s|__ECHOES_TABLE_ID__|$ECHOES_ID|g" \
        -e "s|__NOCODB_CRED_ID__|$CRED_ID|g" \
        "$1"
}

ensure_flow() {
    local flow="$1"
    local flow_name="_t_$flow"
    log "Flow $flow_name..."
    local existing
    existing=$(n8n_get "$N8N/api/v1/workflows" \
               | jq -r ".data[] | select(.name==\"$flow_name\") | .id" | head -1)
    local flow_id
    if [[ -n "$existing" ]]; then
        flow_id="$existing"
        log "  exists ($flow_id)"
    else
        flow_id=$(prep_flow "$SCRIPT_DIR/n8n-flow-$flow.json" \
                  | n8n_post -d @- "$N8N/api/v1/workflows" | jq -r '.id')
        log "  created ($flow_id)"
    fi
    n8n_post "$N8N/api/v1/workflows/$flow_id/activate" >/dev/null
    printf '%s' "$flow_id"
}

PING_FLOW_ID=$(ensure_flow ping)
ECHO_FLOW_ID=$(ensure_flow echo)
upsert_env N8N_FLOW_ID_PING "$PING_FLOW_ID"
upsert_env N8N_FLOW_ID_ECHO "$ECHO_FLOW_ID"

# ─── 5. Hook NocoDB AFTER INSERT sur _t_pings ───
log "Hook NocoDB _t_pings_after_insert..."
existing=$(nocodb_get "$NOCODB/api/v2/meta/tables/$PINGS_ID/hooks" \
           | jq -r '.list[] | select(.title=="_t_pings_after_insert") | .id' | head -1)
if [[ -n "$existing" ]]; then
    HOOK_ID="$existing"
    log "  exists ($HOOK_ID)"
else
    body=$(jq -nc --arg url "$N8N/webhook/_t_echo" '{
        title: "_t_pings_after_insert",
        event: "after",
        operation: ["insert"],
        version: "v3",
        notification: {type:"URL", payload:{method:"POST", path:$url, body:"{{ json data }}"}},
        active: true
    }')
    HOOK_ID=$(nocodb_post -d "$body" \
              "$NOCODB/api/v2/meta/tables/$PINGS_ID/hooks" | jq -r '.id')
    log "  created ($HOOK_ID)"
fi
upsert_env NOCODB_HOOK_ID_PINGS_INSERT "$HOOK_ID"

# ─── 6. Test E2E ───
log "Test E2E..."
ping_resp=$(curl -sS -X POST -H "Content-Type: application/json" \
            -d '{"source":"run.sh-E2E","payload":"automated re-run"}' \
            "$N8N/webhook/_t_ping")
ping_id=$(echo "$ping_resp" | jq -r '.Id // empty')
[[ -n "$ping_id" ]] || { log "✗ R1 FAIL (réponse: $ping_resp)"; exit 1; }
log "  R1 ✓ ping créé Id=$ping_id"

# Attendre que le hook NocoDB → n8n → echo se propage
sleep 4
last_echo=$(nocodb_get "$NOCODB/api/v2/tables/$ECHOES_ID/records?limit=1&sort=-CreatedAt" | jq '.list[0]')
echo_ping_id=$(echo "$last_echo" | jq -r '.ping_id // empty')

if [[ "$echo_ping_id" == "$ping_id" ]]; then
    log "  R2+R3 ✓ echo a ping_id=$ping_id (extrait via GET, donc R3 ✓ aussi)"
    log ""
    log "✓ Toutes les routes validées (R1 + R2 + R3)"
else
    log "✗ R2+R3 FAIL — last echo ping_id='$echo_ping_id', attendu '$ping_id'"
    log "  last_echo: $last_echo"
    exit 1
fi
