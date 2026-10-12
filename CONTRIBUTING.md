# Contributing

The most useful contributions are new **resolvers** (Sway, Hyprland, bspwm…)
and **renderers** (Waybar, i3blocks, tmux…). Both only need
[docs/cache-contract.md](docs/cache-contract.md).

- Resolver: `lib/resolver/<wm>.sh`, emitting `<workspace>\t<key>` lines.
- Renderer: `renderers/<bar>/`, reading the cache and never calling Claude Code.

Before opening a PR, run `./test/run.sh` and `shellcheck -x` on the scripts
you touched (CI runs both), and add a test when you change a state transition.
