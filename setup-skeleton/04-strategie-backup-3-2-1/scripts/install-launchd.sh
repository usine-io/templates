#!/usr/bin/env bash
# install-launchd.sh — installe les jobs launchd (macOS) pour planifier les backups.
#
# Écrit 3 LaunchAgents dans ~/Library/LaunchAgents :
#   - pg-dump        toutes les 6h         (StartInterval 21600)
#   - volumes-tar    chaque jour à 03:00
#   - restore-drill  dimanche à 04:00       (drill de validation)
# Par défaut : ÉCRIT les plists et affiche la commande de chargement (pas de
# load automatique — installer des jobs persistants est une action explicite).
# Avec --load : charge aussi les jobs via launchctl.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BACKUP_TAG="install-launchd"

[[ "$(uname)" == "Darwin" ]] || die "launchd = macOS uniquement (sur Linux: cron/systemd timer)"

LOAD=0
[[ "${1:-}" == "--load" ]] && LOAD=1

LA="$HOME/Library/LaunchAgents"
mkdir -p "$LA"
logdir="$BACKUP_ROOT/logs"
mkdir -p "$logdir"

DOCKER_BIN_DIR="$(dirname "$(command -v docker)")"
PATHV="$DOCKER_BIN_DIR:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# write_plist <suffixe> <script> <bloc_schedule_xml>
write_plist() {
  local suffix="$1" script="$2" schedule="$3"
  local label="com.spark.${PROJECT}.${suffix}"
  local plist="$LA/${label}.plist"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${BACKUP_LIB_DIR}/${script}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>${PATHV}</string>
    <key>HOME</key><string>${HOME}</string>
  </dict>
${schedule}
  <key>StandardOutPath</key><string>${logdir}/${suffix}.log</string>
  <key>StandardErrorPath</key><string>${logdir}/${suffix}.log</string>
</dict>
</plist>
EOF
  log "écrit: $plist"
  if [[ "$LOAD" -eq 1 ]]; then
    launchctl unload "$plist" >/dev/null 2>&1 || true
    launchctl load -w "$plist" && log "chargé: $label"
  fi
}

write_plist "pg-dump" "pg-dump.sh" \
  '  <key>StartInterval</key><integer>21600</integer>'

write_plist "volumes-tar" "volumes-tar.sh" \
  '  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>'

write_plist "restore-drill" "restore-drill.sh" \
  '  <key>StartCalendarInterval</key>
  <dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>4</integer><key>Minute</key><integer>0</integer></dict>'

if [[ "$LOAD" -eq 0 ]]; then
  echo
  log "plists écrites mais NON chargées. Pour activer :"
  echo "    for p in $LA/com.spark.${PROJECT}.*.plist; do launchctl load -w \"\$p\"; done"
  log "ou relancer: $0 --load"
fi
