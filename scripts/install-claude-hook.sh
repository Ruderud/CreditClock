#!/bin/bash
# CreditClock Claude Code Hook Installer
#
# Installs the CreditClock usage cache hook into Claude Code.
# This hook runs inside Claude Code sessions and periodically caches
# subscription usage data to ~/.creditclock/usage-cache.json.
#
# Usage:
#   ./scripts/install-claude-hook.sh          # Install
#   ./scripts/install-claude-hook.sh remove   # Uninstall

set -euo pipefail

HOOK_DIR="$HOME/.creditclock/hooks"
HOOK_PY="$HOOK_DIR/fetch-usage.py"
HOOK_SH="$HOOK_DIR/fetch-usage.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_CMD="bash ~/.creditclock/hooks/fetch-usage.sh"

install_hook() {
    echo "Installing CreditClock Claude Code hook..."

    # Copy hook scripts
    mkdir -p "$HOOK_DIR"
    cp "$SCRIPT_DIR/creditclock-usage-hook.py" "$HOOK_PY"
    cp "$SCRIPT_DIR/creditclock-usage-hook.sh" "$HOOK_SH"
    chmod +x "$HOOK_PY" "$HOOK_SH"

    # Ensure Claude settings file exists
    if [ ! -f "$SETTINGS_FILE" ]; then
        mkdir -p "$(dirname "$SETTINGS_FILE")"
        echo '{}' > "$SETTINGS_FILE"
    fi

    # Add hooks to Claude Code settings
    python3 << 'PYEOF'
import json
import os

settings_path = os.path.expanduser("~/.claude/settings.json")
hook_cmd = "bash ~/.creditclock/hooks/fetch-usage.sh"

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.setdefault("hooks", {})

# Add to PostToolUse (periodic refresh during sessions)
post_tool = hooks.setdefault("PostToolUse", [])
if not any(h.get("command") == hook_cmd for h in post_tool):
    post_tool.append({"command": hook_cmd})

# Add to SessionStart (immediate data on session start)
session_start = hooks.setdefault("SessionStart", [])
if not any(h.get("command") == hook_cmd for h in session_start):
    session_start.append({"command": hook_cmd})

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print("Hook configuration added to ~/.claude/settings.json")
PYEOF

    echo ""
    echo "CreditClock hook installed successfully!"
    echo "  Hook scripts: $HOOK_DIR/"
    echo "  Cache output: ~/.creditclock/usage-cache.json"
    echo ""
    echo "The hook will automatically run during Claude Code sessions"
    echo "and cache your subscription usage data for CreditClock to read."
}

remove_hook() {
    echo "Removing CreditClock Claude Code hook..."

    # Remove hook scripts
    rm -f "$HOOK_PY" "$HOOK_SH"
    rmdir "$HOOK_DIR" 2>/dev/null || true

    # Remove from Claude Code settings
    if [ -f "$SETTINGS_FILE" ]; then
        python3 << 'PYEOF'
import json
import os

settings_path = os.path.expanduser("~/.claude/settings.json")
hook_cmd = "bash ~/.creditclock/hooks/fetch-usage.sh"

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})

for event in ["PostToolUse", "SessionStart"]:
    if event in hooks:
        hooks[event] = [h for h in hooks[event] if h.get("command") != hook_cmd]
        if not hooks[event]:
            del hooks[event]

if not hooks:
    del settings["hooks"]

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print("Hook configuration removed from ~/.claude/settings.json")
PYEOF
    fi

    # Remove cache file
    rm -f "$HOME/.creditclock/usage-cache.json"

    echo "CreditClock hook removed successfully."
}

case "${1:-}" in
    remove|uninstall)
        remove_hook
        ;;
    *)
        install_hook
        ;;
esac
