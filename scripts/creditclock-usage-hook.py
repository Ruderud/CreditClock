#!/usr/bin/env python3
"""CreditClock Usage Cache Hook for Claude Code.

Fetches Anthropic subscription usage data via OAuth and caches it locally
at ~/.creditclock/usage-cache.json for CreditClock to read.

Installed as a Claude Code hook (PostToolUse / SessionStart).
"""

import json
import os
import subprocess
import sys
import time
import urllib.request

CACHE_DIR = os.path.expanduser("~/.creditclock")
CACHE_FILE = os.path.join(CACHE_DIR, "usage-cache.json")
CACHE_TTL_MS = 30_000  # 30 seconds
API_URL = "https://api.anthropic.com/api/oauth/usage"
API_TIMEOUT = 10  # seconds


def main():
    # Check cache freshness
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE) as f:
                cache = json.load(f)
            age_ms = time.time() * 1000 - cache.get("timestamp", 0)
            if age_ms < CACHE_TTL_MS:
                return  # Cache is fresh
        except (json.JSONDecodeError, OSError):
            pass

    # Read OAuth token from macOS Keychain
    token = read_access_token()
    if not token:
        return  # No credentials, skip silently

    # Fetch usage data
    try:
        req = urllib.request.Request(
            API_URL,
            headers={
                "Authorization": f"Bearer {token}",
                "anthropic-beta": "oauth-2025-04-20",
                "Content-Type": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=API_TIMEOUT) as resp:
            data = json.loads(resp.read())
    except Exception:
        write_cache(None, error=True)
        return

    # Transform API response to cache format
    five_hour = data.get("five_hour") or {}
    seven_day = data.get("seven_day") or {}

    usage = {
        "fiveHourPercent": int(five_hour.get("utilization", 0)),
        "weeklyPercent": int(seven_day.get("utilization", 0)),
        "fiveHourResetsAt": five_hour.get("resets_at"),
        "weeklyResetsAt": seven_day.get("resets_at"),
        "subscriptionType": data.get("subscription_type"),
        "rateLimitTier": data.get("rate_limit_tier"),
    }
    write_cache(usage, error=False)


def read_access_token():
    """Read OAuth access token from macOS Keychain."""
    try:
        result = subprocess.run(
            ["security", "find-generic-password",
             "-s", "Claude Code-credentials", "-w"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return None

        creds = json.loads(result.stdout.strip())
        oauth = creds.get("claudeAiOauth", creds)
        return oauth.get("accessToken") or oauth.get("access_token")
    except Exception:
        return None


def write_cache(data, error=False):
    """Write usage data to CreditClock cache file."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    cache = {
        "timestamp": int(time.time() * 1000),
        "data": data,
        "error": error,
        "source": "creditclock",
    }
    try:
        tmp = CACHE_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(cache, f)
        os.replace(tmp, CACHE_FILE)  # Atomic write
    except OSError:
        pass


if __name__ == "__main__":
    main()
