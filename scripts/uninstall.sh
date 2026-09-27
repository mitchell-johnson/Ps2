#!/bin/bash
set -euo pipefail

LABEL="com.dualsense-trackpad"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.local/bin/dualsense-trackpad"
echo "Uninstalled. You can remove dualsense-trackpad from Privacy & Security settings."
