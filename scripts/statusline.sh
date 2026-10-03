#!/bin/bash
# Claude Code Statusline Script
# Reads the status line payload from stdin, writes ~/.claude/rate_limits.json for the
# StatusBar plugin, and prints a compact status line.
#
# Claude Code runs this for every open session, each passing the figures from its own last
# request, so idle sessions carry old numbers. The plan windows are therefore taken from the
# claude.ai usage endpoint, which is account-wide: a detached refresh snapshots it at most once
# a minute and is the only writer of the export.
# Without a snapshot (the keychain read was denied, say) the export falls back to this
# session's payload; with several sessions open, whichever rendered last wins.
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
REFRESH_AFTER=60
# Age at which the snapshot says nothing useful, so its windows are dropped.
DISCARD_AFTER=86400

# Usage endpoint body -> export. Expects --arg fetched_at.
# ISO8601DateFormatter rejects the microsecond precision the endpoint emits, so reset times are
# normalised to whole seconds in UTC. Windows the endpoint does not report are left out.
EXPORT_FROM_USAGE='
    def whole_seconds: if type == "string" then sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") else null end;
    def drop_nulls: with_entries(select(.value != null));
    def window($kind):
        [ (.limits // [])[] | select(.kind == $kind and .percent != null) ][0]
        | if . == null then null
          else {used_percentage: .percent, resets_at: (.resets_at | whole_seconds)} | drop_nulls
          end;
    {
        rate_limits: (
            {fetched_at: $fetched_at}
            + (window("session") | if . then {five_hour: .} else {} end)
            + (window("weekly_all") | if . then {seven_day: .} else {} end)
            + ([ (.limits // [])[]
                 | select(.kind == "weekly_scoped" and .scope.model.display_name != null and .percent != null)
                 | {
                     display_name: .scope.model.display_name,
                     used_percentage: .percent,
                     resets_at: (.resets_at | whole_seconds)
                   }
                 | drop_nulls
               ]
               | if length > 0 then {model_scoped: .} else {} end)
        )
    }
'

# Status line payload -> export, for when there is no snapshot. A payload without rate_limits
# stays null, so the plugin keeps its last reading. resets_at arrives as epoch seconds, which the
# plugin does not read, so it is converted to ISO 8601.
EXPORT_FROM_PAYLOAD='
    def iso: if type == "number" then floor | todate else . end;
    def window: if type == "object" then (.resets_at |= iso) else . end;
    {
        rate_limits: (
            if .rate_limits == null then null
            else .rate_limits | (.five_hour |= window) | (.seven_day |= window)
            end
        )
    }
'

# Seconds since a file was last written, or a very large number when missing.
file_age() {
    local mtime
    mtime=$(stat -f %m "$1" 2>/dev/null) || { echo 999999999; return; }
    echo $(( $(date +%s) - mtime ))
}

# Modification time of a file as ISO 8601 UTC, whole seconds.
file_mtime_iso() {
    date -u -r "$(stat -f %m "$1")" +%Y-%m-%dT%H:%M:%SZ
}

# Replace a file from stdin without a reader ever seeing it half-written. The temp name is
# per-process because several sessions may write at once.
write_atomic() {
    cat > "$1.$$.tmp" 2>/dev/null && mv -f "$1.$$.tmp" "$1" 2>/dev/null
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
    local token body export_json
    token=$(access_token) || return
    [ -n "$token" ] || return

    body=$(curl -sS -m 5 \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $token" \
        "$USAGE_URL" 2>/dev/null) || return

    # An in-band error body parses fine but carries none of the windows.
    echo "$body" | jq -e 'type == "object" and (has("limits") or has("five_hour"))' >/dev/null 2>&1 || return

    echo "$body" | write_atomic "$USAGE_CACHE"

    # The only writer of the export while a snapshot exists: every session reads the same answer.
    export_json=$(echo "$body" | jq --arg fetched_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$EXPORT_FROM_USAGE" 2>/dev/null)
    [ -n "$export_json" ] && echo "$export_json" | write_atomic "$OUTPUT_FILE"
}

# Kick off a refresh when the snapshot has aged out. The attempt marker is
# touched first so a failing refresh still backs off for a full cycle.
maybe_refresh_usage() {
    [ "$(file_age "$USAGE_CACHE")" -gt "$REFRESH_AFTER" ] || return
    [ "$(file_age "$USAGE_ATTEMPT")" -gt "$REFRESH_AFTER" ] || return
    : > "$USAGE_ATTEMPT" 2>/dev/null || return
    ( refresh_usage ) >/dev/null 2>&1 &
}

maybe_refresh_usage

# The snapshot is account-wide, so every session shows the same numbers. The refresh writes the
# export; here it is only read for the terminal line.
RATE_JSON=""
if [ "$(file_age "$USAGE_CACHE")" -lt "$DISCARD_AFTER" ]; then
    RATE_JSON=$(jq --arg fetched_at "$(file_mtime_iso "$USAGE_CACHE")" "$EXPORT_FROM_USAGE" "$USAGE_CACHE" 2>/dev/null)
fi

# No snapshot: fall back to this session's own payload, and write it out.
if [ -z "$RATE_JSON" ]; then
    RATE_JSON=$(echo "$INPUT" | jq "$EXPORT_FROM_PAYLOAD" 2>/dev/null)
    [ -n "$RATE_JSON" ] && echo "$RATE_JSON" | write_atomic "$OUTPUT_FILE"
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

FIVE_HOUR=$(echo "$RATE_JSON" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
SEVEN_DAY=$(echo "$RATE_JSON" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)

LINE=""
append_part() {
    local label=$1 pct=$2
    LINE="${LINE:+$LINE │ }$(color_for_pct "$pct")${label}: $(printf '%.0f' "$pct")%${RESET}"
}

[ -n "$FIVE_HOUR" ] && append_part "5h" "$FIVE_HOUR"
[ -n "$SEVEN_DAY" ] && append_part "7d" "$SEVEN_DAY"
while IFS=$'\t' read -r NAME PCT; do
    [ -n "$NAME" ] || continue
    append_part "$NAME" "$PCT"
done < <(echo "$RATE_JSON" | jq -r '.rate_limits.model_scoped // [] | .[] | "\(.display_name)\t\(.used_percentage)"' 2>/dev/null)

if [ -z "$LINE" ]; then
    echo "Claude Code | No rate limit data"
    exit 0
fi

printf '%b\n' "$LINE"
