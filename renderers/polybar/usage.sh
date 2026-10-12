#!/usr/bin/env bash
# ccoverseer polybar renderer for the Claude Code 5-hour rate-limit window:
#   ▰▰▰▱▱▱▱▱▱▱ 31%
# Appends " ~" when the data is older than CCO_USAGE_STALE_AFTER seconds
# (no Claude Code turn has run since). Reads $CCO_USAGE_FILE.
#
#   [module/ccoverseer-usage]
#   type = custom/script
#   exec = ~/.local/share/ccoverseer/renderers/polybar/usage.sh
#   interval = 30

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
. "$here/../../lib/common.sh"

: "${CCO_USAGE_WIDTH:=10}"
: "${CCO_USAGE_FILLED:=▰}"
: "${CCO_USAGE_EMPTY:=▱}"
: "${CCO_USAGE_STYLE:=fill}"     # fill | indicator (one marker moving along the track)
: "${CCO_USAGE_INDICATOR:=●}"    # marker used by the indicator style
: "${CCO_USAGE_STALE_AFTER:=900}"
: "${CCO_USAGE_SHOW_7D:=0}"      # 1 = append the 7-day percentage
: "${CCO_USAGE_NODATA:=claude --}"
: "${CCO_USAGE_FONT:=}"          # optional polybar font index for the bar glyphs

if [ ! -r "$CCO_USAGE_FILE" ] || ! command -v jq >/dev/null 2>&1; then
    echo "$CCO_USAGE_NODATA"; exit 0
fi

read -r five seven captured < <(jq -r '
    "\(.rate_limits.five_hour.used_percentage // "-") \(.rate_limits.seven_day.used_percentage // "-") \(.captured_at // 0)"
' "$CCO_USAGE_FILE" 2>/dev/null)

if [ -z "$five" ] || [ "$five" = "-" ] || [ "${captured:-0}" = 0 ]; then
    echo "$CCO_USAGE_NODATA"; exit 0
fi

pct=$(printf '%.0f' "$five" 2>/dev/null) || pct=0
[ "$pct" -lt 0 ] && pct=0
[ "$pct" -gt 100 ] && pct=100
filled=$(( (pct * CCO_USAGE_WIDTH + 50) / 100 ))
marker=$(( pct * (CCO_USAGE_WIDTH - 1) / 100 ))

bar=""
for ((i = 0; i < CCO_USAGE_WIDTH; i++)); do
    if [ "$CCO_USAGE_STYLE" = indicator ]; then
        if [ "$i" -eq "$marker" ]; then bar+=$CCO_USAGE_INDICATOR; else bar+=$CCO_USAGE_EMPTY; fi
    elif [ "$i" -lt "$filled" ]; then bar+=$CCO_USAGE_FILLED
    else bar+=$CCO_USAGE_EMPTY
    fi
done

[ -n "$CCO_USAGE_FONT" ] && bar="%{T$CCO_USAGE_FONT}$bar%{T-}"

extra=""
if [ "$CCO_USAGE_SHOW_7D" = 1 ] && [ "$seven" != "-" ]; then
    extra=" · 7d $(printf '%.0f' "$seven" 2>/dev/null)%"
fi
stale=""
[ $(( $(date +%s) - captured )) -gt "$CCO_USAGE_STALE_AFTER" ] && stale=" ~"

printf '%s %d%%%s%s\n' "$bar" "$pct" "$extra" "$stale"
