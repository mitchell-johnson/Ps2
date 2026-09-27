#!/bin/bash
# Builds dualsense-trackpad and installs it as a LaunchAgent that starts at login.
set -euo pipefail

cd "$(dirname "$0")/.."

LABEL="com.dualsense-trackpad"
INSTALL_DIR="$HOME/.local/bin"
BINARY="$INSTALL_DIR/dualsense-trackpad"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

swift build -c release
mkdir -p "$INSTALL_DIR" "$(dirname "$PLIST")"
install -m 755 .build/release/dualsense-trackpad "$BINARY"
# Stable ad-hoc signature so macOS privacy permissions attach to this binary.
codesign --force --sign - --identifier "$LABEL" "$BINARY"

sed "s|__BINARY__|$BINARY|" Resources/$LABEL.plist > "$PLIST"
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST"

cat <<MSG
Installed $BINARY and started it as a LaunchAgent.

macOS will ask for two permissions for "dualsense-trackpad":
  • Input Monitoring  (System Settings → Privacy & Security → Input Monitoring)
  • Accessibility     (System Settings → Privacy & Security → Accessibility)
If it isn't listed, click + and add $BINARY (Cmd-Shift-. shows hidden folders).
After granting, restart it with:  launchctl kickstart -k $DOMAIN/$LABEL
Logs: /tmp/dualsense-trackpad.log
MSG
