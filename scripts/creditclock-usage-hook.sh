#!/bin/bash
# CreditClock Claude Code Hook - Bash Wrapper
# Fast cache-age check in pure bash; invokes Python only when cache is stale.
# This minimizes overhead since PostToolUse fires frequently.

CACHE_FILE="$HOME/.creditclock/usage-cache.json"

# Quick exit if cache is fresh (< 30 seconds old)
if [ -f "$CACHE_FILE" ]; then
    file_mod=$(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    age=$(( now - file_mod ))
    if [ "$age" -lt 30 ]; then
        exit 0
    fi
fi

# Cache is stale or missing — invoke the Python fetcher
exec python3 "$HOME/.creditclock/hooks/fetch-usage.py" &
