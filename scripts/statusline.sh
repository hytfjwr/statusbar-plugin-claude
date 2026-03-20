#!/bin/bash
# Claude Code Statusline Script
# Reads JSON from stdin, extracts rate_limits, and saves to ~/.claude/rate_limits.json
# Also outputs a compact status line for the terminal.
#
# Setup: Add to ~/.claude/settings.json:
#   "statusLine": {
#     "type": "command",
#     "command": "~/.claude/statusline_ratelimit.sh"
#   }

INPUT=$(cat)

# Save full JSON with rate_limits to file for StatusBar plugin
echo "$INPUT" | jq '{rate_limits: .rate_limits}' > ~/.claude/rate_limits.json 2>/dev/null

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

printf "${C5}5h: %.0f%%${RESET} │ ${C7}7d: %.0f%%${RESET}\n" "$FIVE_HOUR" "$SEVEN_DAY"
