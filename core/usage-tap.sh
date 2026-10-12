#!/usr/bin/env bash
# ccoverseer statusLine tap. Claude Code pipes a JSON payload to the statusLine
# command on every turn; we persist its rate_limits block so a status bar can
# render it without calling anything.
#
# Writes $CCO_USAGE_FILE = {"rate_limits": {...}, "captured_at": <epoch>}
#
# Claude Code supports a single statusLine command. If you already use one
# (ccstatusline, claude-powerline, your own script...), set CCO_STATUSLINE_NEXT
# in the config file: the payload is forwarded to it and its output is shown
# in Claude Code as usual. Otherwise the tap prints nothing.

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
. "$here/../lib/common.sh"

payload=$(cat)

if command -v jq >/dev/null 2>&1; then
    mkdir -p "$CCO_CACHE_DIR"
    tmp="$CCO_USAGE_FILE.$$"
    if printf '%s' "$payload" | jq -c --argjson ts "$(date +%s)" \
            'select(.rate_limits != null) | {rate_limits: .rate_limits, captured_at: $ts}' \
            > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
        mv -f "$tmp" "$CCO_USAGE_FILE"
    else
        rm -f "$tmp"
    fi
fi

if [ -n "${CCO_STATUSLINE_NEXT:-}" ]; then
    printf '%s' "$payload" | sh -c "$CCO_STATUSLINE_NEXT"
fi
exit 0
