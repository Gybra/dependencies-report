#!/usr/bin/env bash
#
# install.sh — installs dependencies-report.sh and schedules it weekly via launchd.
#
#   ./install.sh              install + load the agent (Mondays 09:00 by default)
#   WEEKDAY=5 HOUR=18 ./install.sh   install on a different schedule (0=Sun … 6=Sat)
#   ./install.sh --uninstall  unload the agent and remove the installed copies
#
# The script is COPIED to ~/.local/bin on purpose: a launchd agent has no TCC
# permission to read ~/Documents, ~/Desktop or ~/Downloads, so running it from a
# checkout inside those folders fails with "Operation not permitted".
# Re-run this installer after editing the script in the repo.

set -euo pipefail

LABEL="com.dependencies-report"
BIN="$HOME/.local/bin/dependencies-report.sh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dependencies-report"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dependencies-report.sh"

WEEKDAY="${WEEKDAY:-1}"   # 0 = Sunday, 1 = Monday …
HOUR="${HOUR:-9}"
MINUTE="${MINUTE:-0}"

if [ "${1:-}" = "--uninstall" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST" "$BIN"
  echo "Uninstalled. State kept in $STATE_DIR (delete it by hand if you want a clean slate)."
  exit 0
fi

mkdir -p "$HOME/.local/bin" "$HOME/Library/LaunchAgents" "$STATE_DIR"
install -m 755 "$SRC" "$BIN"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
    </array>

    <!-- Weekly. If the Mac is asleep or off, launchd runs it on the next wake. -->
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key><integer>$WEEKDAY</integer>
        <key>Hour</key><integer>$HOUR</integer>
        <key>Minute</key><integer>$MINUTE</integer>
    </dict>

    <key>StandardOutPath</key>
    <string>$STATE_DIR/last-run.log</string>
    <key>StandardErrorPath</key>
    <string>$STATE_DIR/last-run.log</string>

    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Installed: $BIN"
echo "Scheduled: weekday $WEEKDAY at $(printf '%02d:%02d' "$HOUR" "$MINUTE") ($PLIST)"
echo "Run it now with: launchctl kickstart -p gui/$(id -u)/$LABEL"
