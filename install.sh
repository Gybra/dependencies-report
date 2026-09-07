#!/usr/bin/env bash
#
# install.sh — installs dependencies-report.sh and schedules it at login via launchd.
#
#   ./install.sh              install + load the agent (runs at login)
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

    <key>StandardOutPath</key>
    <string>$STATE_DIR/last-run.log</string>
    <key>StandardErrorPath</key>
    <string>$STATE_DIR/last-run.log</string>

    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "Installed: $BIN"
echo "Scheduled: at login ($PLIST)"
echo "Run it now with: launchctl kickstart -p gui/$(id -u)/$LABEL"
