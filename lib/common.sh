#!/usr/bin/env bash
# Shared helpers for ccoverseer. Sourced by hooks and renderers; never executed.
# shellcheck shell=bash

# Where the producer (hooks) writes and the renderers read. This directory
# layout is the public contract documented in docs/cache-contract.md.
CCO_CACHE_DIR="${CCO_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/ccoverseer}"
# shellcheck disable=SC2034  # used by the scripts that source this file
CCO_AGENTS_DIR="$CCO_CACHE_DIR/agents"
# shellcheck disable=SC2034
CCO_ICONS_DIR="$CCO_CACHE_DIR/icons"
# shellcheck disable=SC2034
CCO_USAGE_FILE="$CCO_CACHE_DIR/usage.json"
CCO_CONFIG_DIR="${CCO_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/ccoverseer}"

# Optional user config: plain shell assignments (see config.example).
# shellcheck source=/dev/null
[ -r "$CCO_CONFIG_DIR/config" ] && . "$CCO_CONFIG_DIR/config"

# Terminal emulators recognised when walking up the process tree. Only used
# when $WINDOWID is not available. Space separated /proc/<pid>/comm values.
: "${CCO_TERMINALS:=alacritty kitty wezterm-gui foot st urxvt xterm xfce4-terminal konsole terminator tilix}"

cco_is_uint() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# Print the parent PID of $1 (robust to spaces/parens in comm).
cco_ppid() {
    local stat rest
    stat=$(<"/proc/$1/stat") || return 1
    rest=${stat##*) }        # drop "<pid> (<comm>) "
    # shellcheck disable=SC2086
    set -- $rest             # $1=state, $2=ppid
    printf '%s\n' "$2"
}

# Identify the terminal window that hosts this Claude Code session.
#   w<xid>  X11 window id, taken from $WINDOWID (set by most X terminals)
#   p<pid>  PID of the terminal emulator process (fallback: process walk)
# Prints nothing if no terminal can be identified.
cco_terminal_key() {
    if [ -n "${CCO_KEY:-}" ]; then printf '%s\n' "$CCO_KEY"; return 0; fi
    if cco_is_uint "${WINDOWID:-}" && [ "$WINDOWID" -gt 0 ]; then
        printf 'w%s\n' "$WINDOWID"; return 0
    fi
    local pid=$$ comm t
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
        [ -r "/proc/$pid/comm" ] || return 1
        comm=$(<"/proc/$pid/comm")
        for t in $CCO_TERMINALS; do
            [ "$comm" = "$t" ] && { printf 'p%s\n' "$pid"; return 0; }
        done
        pid=$(cco_ppid "$pid") || return 1
        { cco_is_uint "$pid" && [ "$pid" -gt 1 ]; } || return 1
    done
    return 1
}
