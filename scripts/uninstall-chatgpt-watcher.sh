#!/bin/bash
set -euo pipefail
launchctl bootout "gui/$(id -u)/local.dragon.chatgpt-watcher" 2>/dev/null || true
agent_file="$HOME/Library/LaunchAgents/local.dragon.chatgpt-watcher.plist"
if [[ -f "$agent_file" ]]; then
    mv "$agent_file" "$HOME/Library/Application Support/DragonChatGPTLaunch/disabled-watcher.plist"
fi
printf 'ChatGPT startup animation monitor disabled.\n'
