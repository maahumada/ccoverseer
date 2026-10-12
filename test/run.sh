#!/usr/bin/env bash
# Dependency-free test suite (bash + jq). Run: ./test/run.sh
# Tests the producer/consumer logic against the cache contract with a fake
# workspace resolver, so it runs anywhere (no X11, no i3, no Claude Code).
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
pass=0 fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export CCO_CACHE_DIR="$tmp/cache" CCO_CONFIG_DIR="$tmp/config"
mkdir -p "$CCO_CONFIG_DIR"
A="$CCO_CACHE_DIR/agents" I="$CCO_CACHE_DIR/icons"
unset CCO_INNER CCO_KEY

ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL %s\n       expected: %q\n       got:      %q\n' "$1" "$2" "$3"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
gone() { if [ ! -e "$2" ]; then ok "$1"; else bad "$1" gone present; fi; }
kept() { if [ -e "$2" ]; then ok "$1"; else bad "$1" kept gone; fi; }
reset(){ rm -rf "$CCO_CACHE_DIR"; }
state(){ echo '{}' | WINDOWID="${WID:-111}" "$root/core/hooks/state.sh" "$@"; }
first(){ cut -f1 "$1" 2>/dev/null; }

# Fake resolver: prints whatever is in $tmp/tree.
cat > "$tmp/resolver" <<'EOF'
#!/usr/bin/env bash
cat "$(dirname "$0")/tree" 2>/dev/null
EOF
chmod +x "$tmp/resolver"
tree() { printf '%b' "$1" > "$tmp/tree"; }
render() { CCO_RESOLVER="$tmp/resolver" CCO_CLICK=0 "$root/renderers/polybar/agents.sh"; }

echo "state hook"
reset
state working;              eq "working writes w<WINDOWID>"     working "$(first "$A/w111")"
state "done";                 eq "done overwrites"                "done"    "$(first "$A/w111")"
state bogus;                eq "unknown state ignored"          "done"    "$(first "$A/w111")"
CCO_INNER=1 state working;  eq "inner icon run ignored"         "done"    "$(first "$A/w111")"
mkdir -p "$I"; printf 'x\ts\n' > "$I/w111"
state end
gone "end removes state" "$A/w111"
gone "end removes icon" "$I/w111"

reset
echo '{}' | env -u WINDOWID CCO_TERMINALS="no-such-term" "$root/core/hooks/state.sh" working
n=$(find "$CCO_CACHE_DIR" -type f 2>/dev/null | wc -l); eq "no terminal found -> nothing written" 0 "$n"

reset
# A fake terminal emulator: bash under another name, so /proc/<pid>/comm differs.
ln -s "$(command -v bash)" "$tmp/fake-term"
# shellcheck disable=SC2016  # expanded by the inner shell
term_pid=$(env -u WINDOWID CCO_TERMINALS="fake-term" "$tmp/fake-term" -c \
    'echo "{}" | "$1/core/hooks/state.sh" working; echo $$' _ "$root")
eq "process walk finds terminal pid" working "$(first "$A/p$term_pid")"

echo "polybar agents renderer"
reset
WID=111 state working; WID=222 state blocked
tree '3\tw111\n5\tw222\n'
eq "one badge per workspace, sorted"    "3 ◐  5 ▲" "$(render)"

WID=333 state "done"
tree '3\tw111\n5\tw222\n3\tw333\n'
eq "highest priority wins per workspace" "3 ◐  5 ▲" "$(render)"

printf 'done\t1\n' > "$A/w333"; printf 'done\t1\n' > "$A/w111"
eq "done decays to idle"                 "3 ○  5 ▲" "$(render)"

WID=999 state working
render >/dev/null
gone "window missing from tree is reaped" "$A/w999"

WID=998 state working; tree ''
render >/dev/null
kept "empty tree (i3 down) never reaps" "$A/w998"

reset; mkdir -p "$A"; printf 'working\t%s\n' "$(date +%s)" > "$A/p999999999"
render >/dev/null
gone "dead terminal pid is reaped" "$A/p999999999"

reset
WID=111 state working; WID=222 state blocked
mkdir -p "$I"; printf 'T\tsess\n' > "$I/w111"; printf 'T\tsess\n' > "$I/w222"
tree '3\tw111\n5\tw222\n'
eq "icon face (phase 1)"           "3 T  5 ▲" "$(CCO_ALT_PERIOD=1000000000 render)"
eq "state face (phase 0)"          "3 ◐  5 ▲" "$(CCO_ALT_PERIOD=2000000000 render)"
eq "font tags and click actions"   "%{A1:i3-msg workspace number 3 >/dev/null:}3 %{T4}◐%{T-}%{A}" \
   "$(rm -f "$A/w222"; CCO_FONT_WORKING=4 CCO_ALT_PERIOD=2000000000 CCO_RESOLVER="$tmp/resolver" "$root/renderers/polybar/agents.sh")"

reset
eq "no agents -> empty line" "" "$(render)"

echo "usage tap + renderer"
reset
payload='{"rate_limits":{"five_hour":{"used_percentage":31.4},"seven_day":{"used_percentage":12}}}'
out=$(printf '%s' "$payload" | "$root/core/usage-tap.sh")
eq "tap prints nothing by default" "" "$out"
eq "tap stores rate_limits" "31.4" "$(jq -r '.rate_limits.five_hour.used_percentage' "$CCO_CACHE_DIR/usage.json")"
echo '{"model":{}}' | "$root/core/usage-tap.sh"
eq "payload without rate_limits keeps last data" "31.4" "$(jq -r '.rate_limits.five_hour.used_percentage' "$CCO_CACHE_DIR/usage.json")"
eq "statusLine chaining" "next:31.4" \
   "$(printf '%s' "$payload" | CCO_STATUSLINE_NEXT='printf next:; jq -r .rate_limits.five_hour.used_percentage' "$root/core/usage-tap.sh")"
eq "usage bar"          "▰▰▰▱▱▱▱▱▱▱ 31%" "$("$root/renderers/polybar/usage.sh")"
eq "indicator style"   "──●─────── 31%" "$(CCO_USAGE_STYLE=indicator CCO_USAGE_EMPTY=─ "$root/renderers/polybar/usage.sh")"
eq "usage bar with 7d"  "▰▰▰▱▱▱▱▱▱▱ 31% · 7d 12%" "$(CCO_USAGE_SHOW_7D=1 "$root/renderers/polybar/usage.sh")"
jq '.captured_at = 1' "$CCO_CACHE_DIR/usage.json" > "$tmp/u" && mv "$tmp/u" "$CCO_CACHE_DIR/usage.json"
eq "stale marker"       "▰▰▰▱▱▱▱▱▱▱ 31% ~" "$("$root/renderers/polybar/usage.sh")"
rm -f "$CCO_CACHE_DIR/usage.json"
eq "no data"            "claude --" "$("$root/renderers/polybar/usage.sh")"

echo "installer --merge-settings"
export CLAUDE_CONFIG_DIR="$tmp/claude" XDG_DATA_HOME="$tmp/share"
mkdir -p "$CLAUDE_CONFIG_DIR"
echo '{"statusLine":{"type":"command","command":"mine.sh"},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"other.sh"}]}]}}' > "$CLAUDE_CONFIG_DIR/settings.json"
"$root/install.sh" --merge-settings >/dev/null 2>&1
"$root/install.sh" --merge-settings >/dev/null 2>&1
s="$CLAUDE_CONFIG_DIR/settings.json"
eq "existing statusLine untouched" "mine.sh" "$(jq -r .statusLine.command "$s")"
eq "existing hooks kept, ours added once" "2" "$(jq '.hooks.Stop | length' "$s")"
eq "all five events wired" "5" "$(jq '.hooks | keys | length' "$s")"
eq "icon hook not added by default" "0" "$(jq '[.. | strings | select(test("icon.sh"))] | length' "$s")"
"$root/install.sh" --merge-settings --with-icons >/dev/null 2>&1
eq "--with-icons adds the icon hook" "1" "$(jq '[.. | strings | select(test("icon.sh"))] | length' "$s")"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
