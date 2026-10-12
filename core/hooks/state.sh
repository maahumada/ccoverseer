#!/usr/bin/env bash
# ccoverseer state hook. Called from Claude Code hooks with one argument:
#   working | done | blocked | end
#
# Recommended wiring (see core/settings.example.json):
#   UserPromptSubmit -> working     Stop         -> done
#   PostToolUse      -> working     Notification -> blocked
#   SessionEnd       -> end
#
# PostToolUse matters: after you answer a permission prompt the agent runs
# the tool, and PostToolUse is the first event that tells us it is no longer
# blocked. Without it the "blocked" badge stays until the next Stop.
#
# Writes $CCO_AGENTS_DIR/<key> = "<state>\t<epoch>"   (see docs/cache-contract.md)

# Hooks pipe a JSON payload on stdin; we do not need it, but must drain it.
cat >/dev/null 2>&1

# Ignore events fired by the icon classifier's own inner `claude -p` run.
[ -n "${CCO_INNER:-}" ] && exit 0

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
. "$here/../../lib/common.sh"

state="${1:-done}"
case "$state" in
    working|done|blocked|end) ;;
    *) echo "ccoverseer: unknown state '$state'" >&2; exit 0 ;;
esac

key=$(cco_terminal_key) || exit 0
[ -n "$key" ] || exit 0

if [ "$state" = end ]; then
    rm -f "$CCO_AGENTS_DIR/$key" "$CCO_ICONS_DIR/$key"
    exit 0
fi

mkdir -p "$CCO_AGENTS_DIR"
tmp="$CCO_AGENTS_DIR/.$key.$$"
printf '%s\t%s\n' "$state" "$(date +%s)" > "$tmp" && mv -f "$tmp" "$CCO_AGENTS_DIR/$key"
exit 0
