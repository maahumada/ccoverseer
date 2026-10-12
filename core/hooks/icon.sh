#!/usr/bin/env bash
# ccoverseer topic-icon hook (OPTIONAL, opt-in). Wire it to UserPromptSubmit
# with "async": true. Once per Claude Code session it asks Claude Haiku to
# classify what the session is about into one label from labels.tsv, and
# stores the matching glyph so the renderer can alternate it with the state.
#
# PRIVACY / COST: this sends data to Anthropic through your own `claude` CLI
# and consumes your plan/tokens: one small Haiku request per session. What is
# sent is controlled by CCO_ICON_CONTEXT (default: "repo readme prompt"):
#   repo    name of the git repository (or directory)
#   readme  first CCO_ICON_README_BYTES bytes of its README
#   prompt  first 500 characters of the first prompt of the session
# Leave this hook out of settings.json and nothing is ever sent.
#
# Writes $CCO_ICONS_DIR/<key> = "<glyph>\t<session_id>"

# Re-entry guard: the inner `claude -p` runs with the same user hooks.
[ -n "${CCO_INNER:-}" ] && { cat >/dev/null 2>&1; exit 0; }

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
. "$here/../../lib/common.sh"

: "${CCO_ICON_CONTEXT:=repo readme prompt}"
: "${CCO_ICON_README_BYTES:=1500}"
: "${CCO_ICON_MODEL:=haiku}"
: "${CCO_ICON_TIMEOUT:=60}"
labels_file="$CCO_CONFIG_DIR/labels.tsv"
[ -r "$labels_file" ] || labels_file="$here/../labels.tsv"

command -v jq >/dev/null 2>&1 || { cat >/dev/null 2>&1; exit 0; }
input=$(cat 2>/dev/null)
session_id=$(jq -r '.session_id // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
prompt=$(jq -r '.prompt // empty' <<<"$input")
[ -n "$session_id" ] || exit 0

key=$(cco_terminal_key) || exit 0
[ -n "$key" ] || exit 0
mkdir -p "$CCO_ICONS_DIR"
icon_file="$CCO_ICONS_DIR/$key"

# Already classified for this session: free exit (the common case).
if [ -r "$icon_file" ]; then
    IFS=$'\t' read -r _ sess < "$icon_file"
    [ "$sess" = "$session_id" ] && exit 0
fi

# One classification in flight per terminal; locks older than 120s are stale.
lock="$CCO_ICONS_DIR/.lock.$key"
if ! mkdir "$lock" 2>/dev/null; then
    age=$(( $(date +%s) - $(stat -c %Y "$lock" 2>/dev/null || echo 0) ))
    [ "$age" -le 120 ] && exit 0
    rmdir "$lock" 2>/dev/null
    mkdir "$lock" 2>/dev/null || exit 0
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT

# Load labels: label -> codepoint, and the list shown to the model.
declare -A codepoint
label_list=""
while IFS=$'\t' read -r label cp desc; do
    case "$label" in ''|'#'*) continue ;; esac
    codepoint[$label]=$cp
    label_list+="$label: $desc"$'\n'
done < "$labels_file"
[ -n "${codepoint[other]:-}" ] || exit 0

# Gather only the context the user allowed.
repo="" readme="" first_prompt=""
root=$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null) || root=${cwd:-}
case " $CCO_ICON_CONTEXT " in *" repo "*) repo=$(basename "${root:-unknown}") ;; esac
case " $CCO_ICON_CONTEXT " in *" readme "*)
    for f in "$root/README.md" "$root/README.rst" "$root/README"; do
        [ -r "$f" ] && { readme=$(head -c "$CCO_ICON_README_BYTES" "$f" 2>/dev/null); break; }
    done ;;
esac
case " $CCO_ICON_CONTEXT " in *" prompt "*) first_prompt=${prompt:0:500} ;; esac

claude_bin=$(command -v claude || echo "$HOME/.local/bin/claude")
[ -x "$claude_bin" ] || exit 0

llm_prompt="You are a classifier. Given the context of a programming session, answer with ONE word: the label from the list below that best describes what the project is about.

Labels:
${label_list}
Repository: ${repo:-(not shared)}

README excerpt:
${readme:-(not shared)}

First request of the session:
${first_prompt:-(not shared)}

Prefer the label that describes the DOMAIN of the repository over the action of the request. Use action labels (debug, testing, deploy, refactor, docs) only when the repository has no clear domain. Example: fixing a bug in a scraper is 'bot', not 'debug'.

Answer with the label only, no punctuation."

# Neutral cwd so the one-shot does not load the project's CLAUDE.md.
out=$(cd "$HOME" && CCO_INNER=1 timeout "$CCO_ICON_TIMEOUT" "$claude_bin" --model "$CCO_ICON_MODEL" -p "$llm_prompt" 2>/dev/null)
[ -n "$out" ] || exit 0   # failed: write nothing, the next prompt retries

label=$(printf '%s' "$out" | tr '[:upper:]' '[:lower:]' | grep -oE '[a-z]+' | head -1)
cp=${codepoint[$label]:-${codepoint[other]}}
# shellcheck disable=SC2059  # \u escape needs the codepoint in the format
glyph=$(printf "\\u$cp")

tmp="$icon_file.$$"
printf '%s\t%s\n' "$glyph" "$session_id" > "$tmp" && mv -f "$tmp" "$icon_file"
exit 0
