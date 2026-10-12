#!/usr/bin/env bash
# ccoverseer polybar renderer: one badge per workspace that hosts a Claude Code
# session, e.g.   2 ◐  3 ●  5 ▲
#
#   working ◐   done ●   idle ○ (done for longer than CCO_IDLE_AFTER)   blocked ▲
#
# If the optional topic-icon hook is enabled, each badge alternates between
# the state glyph and the session's topic icon every CCO_ALT_PERIOD seconds.
# A blocked agent always shows its state: that signal must never be hidden.
#
# Polybar module:
#   [module/ccoverseer]
#   type = custom/script
#   exec = ~/.local/share/ccoverseer/renderers/polybar/agents.sh
#   interval = 2

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
. "$here/../../lib/common.sh"

: "${CCO_IDLE_AFTER:=600}"     # seconds after Stop before done -> idle
: "${CCO_ALT_PERIOD:=4}"       # seconds per face when topic icons are on
: "${CCO_CLICK:=1}"            # 1 = clicking a badge focuses its workspace
: "${CCO_BADGE_SEP:=  }"       # text between badges
: "${CCO_GLYPH_WORKING:=◐}"
: "${CCO_GLYPH_DONE:=●}"
: "${CCO_GLYPH_IDLE:=○}"
: "${CCO_GLYPH_BLOCKED:=▲}"
# Optional polybar font index (the N in %{TN}) per state glyph. Empty = the
# module's default font. Useful to render the glyphs bigger than the digits.
: "${CCO_FONT_WORKING:=}" "${CCO_FONT_DONE:=}" "${CCO_FONT_IDLE:=}" "${CCO_FONT_BLOCKED:=}"
: "${CCO_RESOLVER:=$here/../../lib/resolver/i3.sh}"

[ -d "$CCO_AGENTS_DIR" ] || exit 0
shopt -s nullglob
files=("$CCO_AGENTS_DIR"/[wp]*)
[ ${#files[@]} -eq 0 ] && { echo ""; exit 0; }

now=$(date +%s)

# 1. Read states; drop PID-keyed entries whose terminal is gone.
declare -A state_of
need_pids=0
for f in "${files[@]}"; do
    key=${f##*/}
    case "$key" in
        p*) cco_is_uint "${key#p}" || continue
            [ -d "/proc/${key#p}" ] || { rm -f "$f" "$CCO_ICONS_DIR/$key"; continue; }
            need_pids=1 ;;
        w*) cco_is_uint "${key#w}" || continue ;;
        *)  continue ;;
    esac
    IFS=$'\t' read -r st ts < "$f" || true
    [ -n "$st" ] || continue
    if [ "$st" = "done" ] && cco_is_uint "$ts" && [ $((now - ts)) -gt "$CCO_IDLE_AFTER" ]; then
        st=idle
    fi
    state_of[$key]=$st
done
[ ${#state_of[@]} -eq 0 ] && { echo ""; exit 0; }

# 2. Map keys to workspaces via the window-manager resolver.
declare -A ws_of
resolver_args=()
[ "$need_pids" -eq 1 ] && resolver_args=(--pids)
got_tree=0
while IFS=$'\t' read -r ws key; do
    [ -n "$key" ] || continue
    got_tree=1
    ws_of[$key]=$ws
done < <("$CCO_RESOLVER" "${resolver_args[@]}" 2>/dev/null)

# Window-keyed entries whose window no longer exists are stale (e.g. the
# terminal was killed without SessionEnd). Only reap when the tree query
# actually returned something, so a failing i3-msg never wipes the cache.
if [ "$got_tree" -eq 1 ]; then
    for key in "${!state_of[@]}"; do
        case "$key" in
            w*) [ -n "${ws_of[$key]:-}" ] || { rm -f "$CCO_AGENTS_DIR/$key" "$CCO_ICONS_DIR/$key"; unset "state_of[$key]"; } ;;
        esac
    done
fi

# 3. Collapse to one state per workspace (blocked > working > done > idle).
prio() { case "$1" in blocked) echo 3 ;; working) echo 2 ;; done) echo 1 ;; *) echo 0 ;; esac; }
declare -A ws_state ws_key
for key in "${!state_of[@]}"; do
    ws=${ws_of[$key]:-}
    { [ -n "$ws" ] && [ "$ws" -ge 0 ] 2>/dev/null; } || continue
    cur=${ws_state[$ws]:-}
    if [ -z "$cur" ] || [ "$(prio "${state_of[$key]}")" -gt "$(prio "$cur")" ]; then
        ws_state[$ws]=${state_of[$key]}
        ws_key[$ws]=$key
    fi
done
[ ${#ws_state[@]} -eq 0 ] && { echo ""; exit 0; }

glyph_for() {
    local g f
    case "$1" in
        working) g=$CCO_GLYPH_WORKING f=$CCO_FONT_WORKING ;;
        done)    g=$CCO_GLYPH_DONE    f=$CCO_FONT_DONE ;;
        idle)    g=$CCO_GLYPH_IDLE    f=$CCO_FONT_IDLE ;;
        blocked) g=$CCO_GLYPH_BLOCKED f=$CCO_FONT_BLOCKED ;;
    esac
    if [ -n "$f" ]; then printf '%%{T%s}%s%%{T-}' "$f" "$g"; else printf '%s' "$g"; fi
}

# 4. Render, ordered by workspace number.
phase=$(( (now / CCO_ALT_PERIOD) % 2 ))
out=""
while read -r ws; do
    st=${ws_state[$ws]}
    icon=""
    [ -r "$CCO_ICONS_DIR/${ws_key[$ws]}" ] && IFS=$'\t' read -r icon _ < "$CCO_ICONS_DIR/${ws_key[$ws]}"
    if [ -n "$icon" ] && [ "$st" != blocked ] && [ "$phase" -eq 1 ]; then
        badge="$ws $icon"
    else
        badge="$ws $(glyph_for "$st")"
    fi
    if [ "$CCO_CLICK" = 1 ]; then
        badge="%{A1:i3-msg workspace number $ws >/dev/null:}$badge%{A}"
    fi
    out+="$badge$CCO_BADGE_SEP"
done < <(printf '%s\n' "${!ws_state[@]}" | sort -n)

printf '%s\n' "${out%"$CCO_BADGE_SEP"}"
