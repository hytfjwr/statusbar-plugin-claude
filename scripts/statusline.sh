#!/bin/bash
# Claude Code Statusline Script
# Reads JSON from stdin, extracts rate_limits, and saves to ~/.claude/rate_limits.json
# Also outputs a compact status line for the terminal.
#
# The stdin payload only carries five_hour and seven_day. The per-model weekly
# windows (Fable) come from the claude.ai usage endpoint, which this script
# snapshots in the background at most once every 5 minutes.
#
# Setup: Add to ~/.claude/settings.json:
#   "statusLine": {
#     "type": "command",
#     "command": "~/.claude/statusline_ratelimit.sh"
#   }

INPUT=$(cat)

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
OUTPUT_FILE="$CLAUDE_DIR/rate_limits.json"
USAGE_CACHE="$CLAUDE_DIR/rate_limits_usage.json"
USAGE_ATTEMPT="$CLAUDE_DIR/rate_limits_usage.attempt"
USAGE_URL="https://api.anthropic.com/api/oauth/usage"
KEYCHAIN_SERVICE="Claude Code-credentials"

# Age at which the snapshot is refreshed, and the floor between two attempts.
REFRESH_AFTER=300
# Age at which the snapshot says nothing useful, so its windows are dropped.
DISCARD_AFTER=86400

# Seconds since a file was last written, or a very large number when missing.
file_age() {
    local mtime
    mtime=$(stat -f %m "$1" 2>/dev/null) || { echo 999999999; return; }
    echo $(( $(date +%s) - mtime ))
}

# The claude.ai access token. Keychain first — the plain file is a leftover from
# older versions and is often expired.
access_token() {
    local creds
    creds=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null)
    if [ -z "$creds" ] && [ -f "$CLAUDE_DIR/.credentials.json" ]; then
        creds=$(<"$CLAUDE_DIR/.credentials.json")
    fi
    [ -n "$creds" ] || return 1
    # A stale token would only earn a 401; let Claude Code refresh it.
    echo "$creds" | jq -r '.claudeAiOauth | select(.expiresAt > (now * 1000)) | .accessToken // empty' 2>/dev/null
}

# Fetch the usage snapshot and store it. Runs detached, so it reports failure by
# leaving the previous snapshot in place.
refresh_usage() {
    local token body
    token=$(access_token) || return
    [ -n "$token" ] || return

    body=$(curl -sS -m 5 \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        "$USAGE_URL" 2>/dev/null) || return

    # An in-band error body parses fine but carries none of the windows.
    echo "$body" | jq -e 'type == "object" and (has("limits") or has("five_hour"))' >/dev/null 2>&1 || return

    # Write-then-rename so a reader never sees a half-written snapshot.
    echo "$body" > "$USAGE_CACHE.tmp" 2>/dev/null && mv -f "$USAGE_CACHE.tmp" "$USAGE_CACHE" 2>/dev/null
}

# Kick off a refresh when the snapshot has aged out. The attempt marker is
# touched first so a failing refresh still backs off for a full cycle.
maybe_refresh_usage() {
    [ "$(file_age "$USAGE_CACHE")" -gt "$REFRESH_AFTER" ] || return
    [ "$(file_age "$USAGE_ATTEMPT")" -gt "$REFRESH_AFTER" ] || return
    : > "$USAGE_ATTEMPT" 2>/dev/null || return
    ( refresh_usage ) >/dev/null 2>&1 &
}

# The weekly windows scoped to a model bucket, as a JSON array. Empty when the
# snapshot is missing, aged out, or carries no such window.
model_scoped_json() {
    [ "$(file_age "$USAGE_CACHE")" -lt "$DISCARD_AFTER" ] || { echo "[]"; return; }
    jq -c '
        [ (.limits // [])[]
          | select(.kind == "weekly_scoped" and .scope.model.display_name != null)
          | {
              display_name: .scope.model.display_name,
              used_percentage: (.percent // 0),
              # ISO8601DateFormatter rejects the microsecond precision the
              # endpoint emits, so normalise to whole seconds in UTC.
              resets_at: (.resets_at | if . then (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z")) else null end)
            }
        ]
    ' "$USAGE_CACHE" 2>/dev/null
}

maybe_refresh_usage

MODEL_SCOPED=$(model_scoped_json)
[ -n "$MODEL_SCOPED" ] || MODEL_SCOPED="[]"

# Save rate limits to file for the StatusBar plugin
# A payload without rate_limits stays null, so the plugin keeps its last reading
# and lets it go stale rather than reporting a fresh 0%.
echo "$INPUT" | jq --argjson model_scoped "$MODEL_SCOPED" '
    {
        rate_limits: (
            if .rate_limits == null then null
            else .rate_limits
                + (if ($model_scoped | length) > 0 then {model_scoped: $model_scoped} else {} end)
            end
        )
    }
' > "$OUTPUT_FILE.tmp" 2>/dev/null && mv -f "$OUTPUT_FILE.tmp" "$OUTPUT_FILE" 2>/dev/null

# Extract values for terminal display
FIVE_HOUR=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
SEVEN_DAY=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)

if [ -z "$FIVE_HOUR" ]; then
    echo "Claude Code | No rate limit data"
    exit 0
fi

# Color based on usage
color_for_pct() {
    local pct=$1
    if (( $(echo "$pct < 50" | bc -l) )); then
        echo "\033[32m" # green
    elif (( $(echo "$pct < 80" | bc -l) )); then
        echo "\033[33m" # yellow
    else
        echo "\033[31m" # red
    fi
}

RESET="\033[0m"
C5=$(color_for_pct "$FIVE_HOUR")
C7=$(color_for_pct "$SEVEN_DAY")

MODEL_PART=""
while IFS=$'\t' read -r NAME PCT; do
    [ -n "$NAME" ] || continue
    CM=$(color_for_pct "$PCT")
    MODEL_PART="${MODEL_PART} │ ${CM}${NAME}: $(printf '%.0f' "$PCT")%${RESET}"
done < <(echo "$MODEL_SCOPED" | jq -r '.[] | "\(.display_name)\t\(.used_percentage)"' 2>/dev/null)

printf "${C5}5h: %.0f%%${RESET} │ ${C7}7d: %.0f%%${RESET}%b\n" "$FIVE_HOUR" "$SEVEN_DAY" "$MODEL_PART"
