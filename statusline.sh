#!/bin/bash
# Claude Code Custom Statusline
# Displays: Model | Context% | Tokens | Cost | 5hr% | Weekly% | Git

set -o pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
RESET='\033[0m'
BOLD='\033[1m'

# Cache settings
USAGE_CACHE="/tmp/claude-statusline-usage.json"
USAGE_CACHE_TTL=60  # seconds

# Read stdin
INPUT=$(cat 2>/dev/null) || INPUT="{}"

# Debug: save last input
echo "$INPUT" > /tmp/claude-statusline-last.json 2>/dev/null

# Helper: safe jq extract
jq_get() {
    echo "$INPUT" | jq -r "$1 // empty" 2>/dev/null || echo ""
}

# Extract fields from stdin
CWD=$(jq_get '.workspace.current_dir')
MODEL=$(jq_get '.model.display_name')
COST=$(jq_get '.cost.total_cost_usd')
INPUT_TOKENS=$(jq_get '.context_window.total_input_tokens')
OUTPUT_TOKENS=$(jq_get '.context_window.total_output_tokens')
CONTEXT_SIZE=$(jq_get '.context_window.context_window_size')
USED_PCT=$(jq_get '.context_window.used_percentage')

# Try to get rate limits from stdin first (v1.2.80+)
FIVE_HOUR=$(jq_get '.rate_limits.five_hour.used_percentage')
SEVEN_DAY=$(jq_get '.rate_limits.seven_day.used_percentage')

# Fallback: fetch from OAuth API if not in stdin
fetch_usage_from_api() {
    # Try keychain first (macOS), then fall back to credentials file
    local creds=$(security find-generic-password -s "Claude Code-credentials" -w </dev/null 2>/dev/null)

    if [ -z "$creds" ]; then
        local creds_file="$HOME/.claude/.credentials.json"
        [ ! -f "$creds_file" ] && return 1
        creds=$(cat "$creds_file" 2>/dev/null)
    fi

    local token=$(echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    [ -z "$token" ] && return 1

    # Check cache
    if [ -f "$USAGE_CACHE" ]; then
        local cache_mtime=$(stat -f %m "$USAGE_CACHE" 2>/dev/null || stat -c %Y "$USAGE_CACHE" 2>/dev/null || echo 0)
        local now=$(date +%s)
        if [ $((now - cache_mtime)) -lt $USAGE_CACHE_TTL ]; then
            cat "$USAGE_CACHE" 2>/dev/null
            return 0
        fi
    fi

    # Fetch fresh data (with 2s timeout via curl)
    local response=$(curl -s --max-time 2 "https://api.anthropic.com/api/oauth/usage" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null)

    if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
        echo "$response" > "$USAGE_CACHE" 2>/dev/null
        echo "$response"
        return 0
    fi

    return 1
}

# If rate limits not in stdin, try API
if [ -z "$FIVE_HOUR" ] || [ "$FIVE_HOUR" = "null" ]; then
    API_RESPONSE=$(fetch_usage_from_api 2>/dev/null)
    if [ -n "$API_RESPONSE" ]; then
        FIVE_HOUR=$(echo "$API_RESPONSE" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
        SEVEN_DAY=$(echo "$API_RESPONSE" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
    fi
fi

# Calculate context percentage if not provided
if [ -z "$USED_PCT" ] || [ "$USED_PCT" = "null" ]; then
    if [ -n "$INPUT_TOKENS" ] && [ -n "$CONTEXT_SIZE" ] && [ "$CONTEXT_SIZE" != "0" ]; then
        TOTAL_TOKENS=$((INPUT_TOKENS + OUTPUT_TOKENS))
        USED_PCT=$(echo "scale=0; $TOTAL_TOKENS * 100 / $CONTEXT_SIZE" | bc 2>/dev/null || echo "0")
    fi
fi

# Build a mini progress bar (5 chars wide)
build_bar() {
    local pct="${1:-0}"
    pct=$(printf '%.0f' "$pct" 2>/dev/null || echo "0")
    [ -z "$pct" ] || [ "$pct" = "null" ] && pct=0

    local bar_width=5
    local filled=$((pct * bar_width / 100))
    [ $filled -gt $bar_width ] && filled=$bar_width
    [ $filled -lt 0 ] && filled=0
    local empty=$((bar_width - filled))

    local color="$GREEN"
    [ "$pct" -ge 50 ] && color="$YELLOW"
    [ "$pct" -ge 80 ] && color="$RED"

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    echo -e "${color}${bar}${RESET}"
}

# Format with bar
format_with_bar() {
    local pct="$1"
    local label="$2"

    [ -z "$pct" ] || [ "$pct" = "null" ] && return

    local pct_int=$(printf '%.0f' "$pct" 2>/dev/null || echo "0")
    local bar=$(build_bar "$pct_int")

    local color="$GREEN"
    [ "$pct_int" -ge 50 ] && color="$YELLOW"
    [ "$pct_int" -ge 80 ] && color="$RED"

    echo -e "${GRAY}${label}${RESET} ${bar} ${color}${pct_int}%${RESET}"
}

# Format tokens (15234 -> 15.2k)
format_tokens() {
    local tokens="$1"
    [ -z "$tokens" ] || [ "$tokens" = "null" ] && echo "0" && return

    local num=$(printf '%.0f' "$tokens" 2>/dev/null || echo "0")

    if [ "$num" -ge 1000000 ]; then
        echo "$(echo "scale=1; $num / 1000000" | bc)M"
    elif [ "$num" -ge 1000 ]; then
        echo "$(echo "scale=1; $num / 1000" | bc)k"
    else
        echo "$num"
    fi
}

# Git branch with dirty indicator (cached)
get_git_info() {
    local dir="$1"
    [ -z "$dir" ] && return

    local cache_key=$(echo "$dir" | md5 2>/dev/null || echo "$dir" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "default")
    local cache_file="/tmp/claude-statusline-git-${cache_key}.cache"

    if [ -f "$cache_file" ]; then
        local cache_mtime=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)
        local now=$(date +%s)
        if [ $((now - cache_mtime)) -lt 5 ]; then
            cat "$cache_file" 2>/dev/null
            return
        fi
    fi

    local git_info=""
    local branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)

    if [ -n "$branch" ]; then
        local dirty=""
        local status=$(git -C "$dir" status --porcelain 2>/dev/null | head -1)
        [ -n "$status" ] && dirty="*"

        if [ ${#branch} -gt 15 ]; then
            branch="${branch:0:12}..."
        fi

        git_info="${CYAN}${branch}${YELLOW}${dirty}${RESET}"
    fi

    echo -e "$git_info" > "$cache_file" 2>/dev/null
    echo -e "$git_info"
}

# Build output
SEP="${GRAY} │ ${RESET}"
OUTPUT=""

# Model name
if [ -n "$MODEL" ] && [ "$MODEL" != "null" ]; then
    OUTPUT="${BOLD}${CYAN}${MODEL}${RESET}"
fi

# Context bar with percentage
if [ -n "$USED_PCT" ] && [ "$USED_PCT" != "null" ] && [ "$USED_PCT" != "0" ]; then
    CTX_FMT=$(format_with_bar "$USED_PCT" "ctx")
    [ -n "$OUTPUT" ] && OUTPUT="$OUTPUT$SEP"
    OUTPUT="$OUTPUT$CTX_FMT"
fi

# Token counts
if [ -n "$INPUT_TOKENS" ] && [ "$INPUT_TOKENS" != "null" ]; then
    IN_FMT=$(format_tokens "$INPUT_TOKENS")
    OUT_FMT=$(format_tokens "$OUTPUT_TOKENS")
    [ -n "$OUTPUT" ] && OUTPUT="$OUTPUT$SEP"
    OUTPUT="$OUTPUT${GRAY}in:${RESET}${IN_FMT} ${GRAY}out:${RESET}${OUT_FMT}"
fi

# Cost
if [ -n "$COST" ] && [ "$COST" != "null" ]; then
    COST_FMT=$(printf '$%.2f' "$COST" 2>/dev/null || echo "\$0.00")
    [ -n "$OUTPUT" ] && OUTPUT="$OUTPUT$SEP"
    OUTPUT="$OUTPUT${GREEN}${COST_FMT}${RESET}"
fi

# 5-hour rate limit
if [ -n "$FIVE_HOUR" ] && [ "$FIVE_HOUR" != "null" ]; then
    FIVE_FMT=$(format_with_bar "$FIVE_HOUR" "5hr")
    [ -n "$OUTPUT" ] && OUTPUT="$OUTPUT$SEP"
    OUTPUT="$OUTPUT$FIVE_FMT"
fi

# Weekly rate limit
if [ -n "$SEVEN_DAY" ] && [ "$SEVEN_DAY" != "null" ]; then
    WEEK_FMT=$(format_with_bar "$SEVEN_DAY" "wk")
    [ -n "$OUTPUT" ] && OUTPUT="$OUTPUT$SEP"
    OUTPUT="$OUTPUT$WEEK_FMT"
fi

# Git branch
GIT_INFO=$(get_git_info "$CWD")
if [ -n "$GIT_INFO" ]; then
    [ -n "$OUTPUT" ] && OUTPUT="$OUTPUT$SEP"
    OUTPUT="$OUTPUT$GIT_INFO"
fi

# Fallback
if [ -z "$OUTPUT" ]; then
    OUTPUT="${GRAY}Ready${RESET}"
fi

echo -e "$OUTPUT"
exit 0
