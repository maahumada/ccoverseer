#!/usr/bin/env bash
# ccoverseer demo: drives a fake set of Claude Code sessions through every
# state, so you can preview a bar theme or record a GIF without running any
# agent. It writes to its own cache directory (never your real one), using
# the format in docs/cache-contract.md.
#
#   scripts/demo.sh play                      loop the scenario (one step per second)
#   scripts/demo.sh step <n>                  write frame n (0-11) once and exit
#   scripts/demo.sh polybar                   play + open a demo bar (scripts/demo-polybar.ini)
#   scripts/demo.sh env                       print the variables a renderer needs
#
# Scenario (12 steps, one per wall-clock second, step = epoch % 12): three
# agents work on workspaces 1-3; 2 finishes, 3 asks for a permission (its ▲
# stays while the others flip to their topic icons), gets approved and
# resumes; 1 goes idle; meanwhile the 5-hour usage bar climbs. With the
# default CCO_ALT_PERIOD=2, state faces show on seconds 0,1 mod 4 and topic
# icons on 2,3 mod 4, so every transition lands on a state face and a
# 12-second recording started on a multiple of 12 loops seamlessly.

set -u

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)

export CCO_CACHE_DIR="${CCO_DEMO_DIR:-${TMPDIR:-/tmp}/ccoverseer-demo-$UID}"
# Keep the user's ~/.config/ccoverseer (fonts, labels) out of the demo.
export CCO_CONFIG_DIR="$CCO_CACHE_DIR/config"
export CCO_RESOLVER="$here/demo-resolver.sh"
export CCO_ALT_PERIOD=2

agents="$CCO_CACHE_DIR/agents"
icons="$CCO_CACHE_DIR/icons"

# Demo terminals: key -> workspace, and a topic icon per session.
keys=(w1001 w1002 w1003)
workspaces=(1 2 3)
topics=(f121 f02d f0c3)   # api, docs, testing (Nerd Font codepoints)

setup() {
    mkdir -p "$agents" "$icons" "$CCO_CONFIG_DIR"
    local i tree=""
    for i in "${!keys[@]}"; do
        tree+="${workspaces[$i]}"$'\t'"${keys[$i]}"$'\n'
        # shellcheck disable=SC2059  # \u escape needs the codepoint in the format
        { printf "\\u${topics[$i]}"; printf '\tdemo-session-%s\n' "$i"; } > "$icons/${keys[$i]}"
    done
    printf '%s' "$tree" > "$CCO_CACHE_DIR/demo-tree"
}

# set_state <index> <state> [age_seconds]
set_state() {
    printf '%s\t%s\n' "$2" "$(( $(date +%s) - ${3:-0} ))" > "$agents/${keys[$1]}"
}

set_usage() {
    printf '{"rate_limits":{"five_hour":{"used_percentage":%s},"seven_day":{"used_percentage":%s}},"captured_at":%s}\n' \
        "$1" "$(( $1 / 3 ))" "$(date +%s)" > "$CCO_CACHE_DIR/usage.json"
}

frame() {
    case "$1" in
        0|1|2|3) set_state 0 working; set_state 1 working; set_state 2 working ;;
        4)       set_state 0 working; set_state 1 "done";  set_state 2 working ;;
        5|6|7)   set_state 0 working; set_state 1 "done";  set_state 2 blocked ;;
        8)       set_state 0 working; set_state 1 "done";  set_state 2 working ;;
        9|10|11) set_state 0 "done" 3600; set_state 1 "done"; set_state 2 working ;;
        *) echo "demo: frame must be 0-11" >&2; return 1 ;;
    esac
    local usage=(18 21 24 27 30 33 36 40 44 48 52 56)
    set_usage "${usage[$1]}"
}

play() {
    local ms wait
    setup
    while :; do
        frame "$(( $(date +%s) % 12 ))"
        # Sleep until the next wall-clock second so steps stay in phase.
        ms=$(date +%3N); wait=$(( 1000 - 10#$ms )); [ "$wait" -ge 1000 ] && wait=999
        sleep "0.$(printf '%03d' "$wait")"
    done
}

case "${1:-play}" in
    play)  play ;;
    step)  setup; frame "${2:?usage: demo.sh step <0-11>}" ;;
    env)   printf 'export CCO_CACHE_DIR=%q CCO_CONFIG_DIR=%q CCO_RESOLVER=%q CCO_ALT_PERIOD=%q\n' \
               "$CCO_CACHE_DIR" "$CCO_CONFIG_DIR" "$CCO_RESOLVER" "$CCO_ALT_PERIOD" ;;
    polybar)
        command -v polybar >/dev/null 2>&1 || { echo "demo: polybar not found" >&2; exit 1; }
        play & player=$!
        trap 'kill "$player" 2>/dev/null' EXIT INT TERM
        # Font slots defined in demo-polybar.ini.
        export CCO_FONT_WORKING=3 CCO_FONT_DONE=3 CCO_FONT_IDLE=3 CCO_FONT_BLOCKED=3
        export CCO_USAGE_FONT=4 CCO_FONT_ICON=5 CCO_BADGE_SEP=" "
        CCO_ROOT="$root" polybar -q -c "$here/demo-polybar.ini" demo ;;
    *) sed -n '2,15p' "$0"; exit 2 ;;
esac
