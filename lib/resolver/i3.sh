#!/usr/bin/env bash
# Workspace resolver for i3 (X11).
#
# Interface shared by every resolver in lib/resolver/:
#   stdout: one line per managed window   "<workspace>\t<key>"
#   where <key> uses the same scheme as the cache (w<xid> or p<pid>).
#   Usage: i3.sh [--pids]
#     --pids  also emit p<pid> lines (needs xprop; only requested when the
#             cache holds PID-keyed entries, since it costs one xprop call
#             per window).
# Workspaces without a number (named-only, scratchpad) are emitted as -1 so
# the renderer knows the window is alive but has nowhere to show it.

command -v i3-msg >/dev/null 2>&1 || exit 1
command -v jq >/dev/null 2>&1 || exit 1

want_pids=0
[ "${1:-}" = --pids ] && want_pids=1

i3-msg -t get_tree 2>/dev/null | jq -r '
  recurse(.nodes[]?, .floating_nodes[]?) | select(.type=="workspace") as $ws
  | $ws | recurse(.nodes[]?, .floating_nodes[]?) | select(.window != null)
  | "\($ws.num // -1)\t\(.window)"
' | while IFS=$'\t' read -r ws win; do
    [ -n "$win" ] || continue
    printf '%s\tw%s\n' "$ws" "$win"
    if [ "$want_pids" -eq 1 ]; then
        pid=$(xprop -id "$win" _NET_WM_PID 2>/dev/null | awk '{print $NF}')
        case "$pid" in ''|*[!0-9]*) ;; *) printf '%s\tp%s\n' "$ws" "$pid" ;; esac
    fi
done
