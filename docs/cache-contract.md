# Cache contract

ccoverseer is split into a **producer** (Claude Code hooks + statusLine tap)
and **renderers** (status-bar modules). They only talk through files under
one directory. If you write a renderer for another bar or window manager,
this page is all you need; you do not have to read the hook code.

Root: `${CCO_CACHE_DIR:-${XDG_CACHE_HOME:-~/.cache}/ccoverseer}`

```
ccoverseer/
├── agents/<key>     one file per Claude Code session's terminal
├── icons/<key>      optional topic glyph for that terminal
└── usage.json       last rate-limit snapshot
```

## Keys

A key identifies the **terminal window** that hosts a Claude Code session,
because that is what a window manager places on a workspace.

| Form | Meaning | How the producer gets it |
|---|---|---|
| `w<xid>` | X11 window id, decimal | `$WINDOWID` (set by alacritty, kitty, xterm, urxvt, st and most X terminals) |
| `p<pid>` | PID of the terminal emulator process | walking up `/proc/<pid>/stat` until `comm` is in `CCO_TERMINALS` |

`w` keys are preferred. A renderer maps `w` keys straight to a window and
`p` keys through the window's `_NET_WM_PID` (X11) or `pid` field (Sway,
Hyprland).

## `agents/<key>`

One line, tab-separated: `<state>\t<unix_epoch>`. It is replaced atomically
(write to a temp file, then `mv`).

| State | Written on | Meaning |
|---|---|---|
| `working` | `UserPromptSubmit`, `PostToolUse` | the agent is running |
| `done` | `Stop` | the turn finished; waiting for your next prompt |
| `blocked` | `Notification` (`permission_prompt`, `elicitation_dialog`) | waiting for you to approve or answer |

The file is removed on `SessionEnd`.

The producer never writes `idle`. It is derived by the renderer: a `done`
entry older than `CCO_IDLE_AFTER` seconds (default 600).

When several sessions share a workspace, show the most urgent one:
`blocked` > `working` > `done` > `idle`.

### Staleness and cleanup

A terminal can die without `SessionEnd` (killed window, crash). Renderers
should reap entries whose terminal is gone:

- `p<pid>`: `/proc/<pid>` no longer exists.
- `w<xid>`: the window is absent from a *successful, non-empty* window-tree
  query. Never reap when the query failed, or a WM restart wipes the cache.

Remove `icons/<key>` together with `agents/<key>`.

## `icons/<key>` (optional)

One line: `<glyph>\t<session_id>`. It is written by the opt-in topic-icon
hook. The glyph is a single character, usually from the Nerd Font private
use area. The `session_id` lets the hook skip sessions it has already
classified.

Renderers may alternate the state glyph and the icon. A `blocked` session
must always show its state.

## `usage.json`

```json
{"rate_limits": {"five_hour": {"used_percentage": 31.4, "resets_at": 1791790000},
                 "seven_day": {"used_percentage": 12,   "resets_at": 1792000000}},
 "captured_at": 1791781221}
```

`rate_limits` is copied verbatim from the Claude Code statusLine payload, so
its schema follows Claude Code. Fields can be missing on some plans or
versions, so degrade gracefully. `captured_at` is when the last turn ran;
show a staleness hint when it is old.

## Workspace resolvers

The PID/window to workspace mapping is window-manager specific and lives in
`lib/resolver/<wm>.sh`. Interface:

- stdout: one `<workspace_number>\t<key>` line per window. Use `-1` for
  windows on unnumbered workspaces or the scratchpad, so they count as alive
  but are not shown.
- `--pids`: also emit `p<pid>` lines. Renderers only pass it when the cache
  holds `p` keys, because it can be costly.
- On failure, exit non-zero or print nothing.

The renderer selects the resolver with `CCO_RESOLVER`.
