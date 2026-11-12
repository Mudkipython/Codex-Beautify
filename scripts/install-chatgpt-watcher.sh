#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
watcher_root="$HOME/Library/Application Support/DragonChatGPTLaunch"
agent_file="$HOME/Library/LaunchAgents/local.dragon.chatgpt-watcher.plist"
mkdir -p "$watcher_root" "$(dirname "$agent_file")"
xcrun swiftc -O -framework AppKit -module-cache-path "$repo_root/build/macos/module-cache" "$repo_root/src/macos/LaunchWatcher.swift" -o "$repo_root/build/macos/DragonLaunchWatcher"
codesign --force --sign - "$repo_root/build/macos/DragonLaunchWatcher"
launchctl bootout "gui/$(id -u)/local.dragon.chatgpt-watcher" 2>/dev/null || true
cp "$repo_root/build/macos/DragonLaunchWatcher" "$watcher_root/DragonLaunchWatcher"
/usr/bin/python3 - "$agent_file" "$watcher_root/DragonLaunchWatcher" "$HOME/Applications/Dragon Codex Boot.app" <<'PY'
import plistlib,sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({'Label':'local.dragon.chatgpt-watcher','ProgramArguments':[sys.argv[2],'com.openai.codex',sys.argv[3]],'RunAtLoad':True,'KeepAlive':True,'ProcessType':'Background','LimitLoadToSessionType':'Aqua'}))
PY
plutil -lint "$agent_file"
launchctl bootstrap "gui/$(id -u)" "$agent_file"
launchctl print "gui/$(id -u)/local.dragon.chatgpt-watcher"
