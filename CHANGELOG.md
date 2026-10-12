# Changelog

## 0.1.0 (unreleased)

- Agents renderer: badges keep a constant width while alternating between state and topic icon (`CCO_STABLE_WIDTH`, on by default), so neighbouring modules and centred blocks no longer jump. New `CCO_FONT_ICON`.
- Usage renderer: `CCO_USAGE_FONT` to draw the bar glyphs in their own (bigger) font.
- `scripts/demo.sh`: scripted demo and theme preview with an isolated cache and a demo polybar config, synced to the wall clock so a 12-second recording loops seamlessly.

- Per-workspace badges for Claude Code sessions (working / done / idle / blocked) for i3 + polybar.
- Terminal identification via `$WINDOWID`, with a process-tree fallback.
- Rate-limit bar from the statusLine payload, with chaining to an existing statusLine.
- Opt-in topic icons classified by Claude Haiku, with configurable context and labels.
- Documented cache contract and workspace-resolver interface.
