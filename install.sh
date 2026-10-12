#!/usr/bin/env bash
# ccoverseer installer. Idempotent; never edits Claude Code settings unless
# you pass --merge-settings (and then it writes a timestamped backup first).
#
#   ./install.sh                    link ~/.local/share/ccoverseer -> this repo, check deps
#   ./install.sh --merge-settings   also add the hooks + statusLine to ~/.claude/settings.json
#   ./install.sh --with-icons       with --merge-settings, also add the opt-in topic-icon hook
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dest="${XDG_DATA_HOME:-$HOME/.local/share}/ccoverseer"
settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
merge=0 icons=0
for arg in "$@"; do
    case "$arg" in
        --merge-settings) merge=1 ;;
        --with-icons) icons=1 ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

missing=()
for c in jq i3-msg xprop; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
if [ ${#missing[@]} -gt 0 ]; then
    echo "warning: missing dependencies: ${missing[*]}" >&2
    echo "         (Debian/Ubuntu: sudo apt install jq i3-wm x11-utils)" >&2
fi

mkdir -p "$(dirname "$dest")"
if [ -L "$dest" ] || [ ! -e "$dest" ]; then
    ln -sfn "$repo" "$dest"
    echo "linked $dest -> $repo"
elif [ "$(cd "$dest" && pwd -P)" != "$(cd "$repo" && pwd -P)" ]; then
    echo "error: $dest exists and is not a symlink to this repo; remove it first" >&2
    exit 1
fi
chmod +x "$repo"/core/*.sh "$repo"/core/hooks/*.sh "$repo"/renderers/*/*.sh "$repo"/lib/resolver/*.sh

if [ "$merge" -eq 0 ]; then
    cat <<EOF

Next steps:
  1. Add the hooks and statusLine from core/settings.example.json to
     $settings   (or re-run with --merge-settings)
  2. Add the modules from renderers/polybar/modules.ini to your polybar config.
  3. Start a new Claude Code session (hooks are read at session start).
EOF
    exit 0
fi

command -v jq >/dev/null 2>&1 || { echo "error: --merge-settings needs jq" >&2; exit 1; }
mkdir -p "$(dirname "$settings")"
[ -s "$settings" ] || echo '{}' > "$settings"
backup="$settings.bak.$(date +%s)"
cp -L "$settings" "$backup"

example="$repo/core/settings.example.json"
icon_hook='{"hooks":[{"type":"command","command":"~/.local/share/ccoverseer/core/hooks/icon.sh","async":true}]}'
new=$(jq --slurpfile ex "$example" --argjson icons "$icons" --argjson iconhook "$icon_hook" '
  ($ex[0].hooks + (if $icons == 1 then {UserPromptSubmit: ($ex[0].hooks.UserPromptSubmit + [$iconhook])} else {} end)) as $add
  | .hooks = (.hooks // {})
  | reduce ($add | to_entries[]) as $e (.;
      .hooks[$e.key] = ((.hooks[$e.key] // []) as $cur
        | $cur + [ $e.value[] | select(tojson as $j | ($cur | map(tojson) | index($j)) == null) ]))
  | if (.statusLine // null) == null then .statusLine = $ex[0].statusLine
    else . end
' "$settings")

# Write through symlinks (dotfiles setups often symlink settings.json).
printf '%s\n' "$new" > "$(readlink -f "$settings")"
echo "merged hooks into $settings (backup: $backup)"
if jq -e '.statusLine.command | test("ccoverseer") | not' "$settings" >/dev/null 2>&1; then
    echo "note: you already have a statusLine; it was left untouched."
    echo "      To get the usage bar, set statusLine to core/usage-tap.sh and put your"
    echo "      current command in CCO_STATUSLINE_NEXT (see config.example)."
fi
