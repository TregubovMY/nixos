# `modules/home/hyprland.nix` (real config content) Design

## Goal

The part `docs/superpowers/specs/2026-08-11-hyprland-design.md` explicitly
deferred: real Hyprland config content — keybinds, waybar, mako
notifications, hyprlock/hypridle, and the Crow Translate hotkey
(`system-plan.md` §5.11, whose Lua snippet was written in advance for
exactly this moment). `modules/nixos/hyprland.nix` (the system module,
`programs.hyprland.enable` + package list) is untouched except one
addition: `security.pam.services.hyprlock = {}` (hyprlock needs PAM
configured to authenticate at all — see that module's own comment).

## Decision: home-manager's native `wayland.windowManager.hyprland` module, not raw vendored Lua

Initially planned to vendor a raw `hyprland.lua` file under
`xdg.configFile`, the same pattern `modules/home/neovim.nix` uses for
LazyVim. Checked home-manager's actual module set first (per CLAUDE.md
"искать готовые решения") and found something better: home-manager
ships a first-class `wayland.windowManager.hyprland` module (fetched and
read in full at this repo's pinned rev,
`c30c7955cec30d664a9baced6bc0112e263d4647`) that:

- Generates `hyprland.lua` from a Nix attrset (`settings`) instead of
  hand-written Lua text — same declarative-config idea already used
  everywhere else in this repo, applied to Hyprland's new-since-0.55 Lua
  format specifically (`configType = "lua"`, confirmed by reading
  `modules/services/window-managers/hyprland/default.nix` and the
  module's own test fixture,
  `tests/modules/services/hyprland/lua-config.nix` +
  `lua-config.lua`, to ground the Nix→Lua translation rules actually
  used below, not guessed).
- Has `package = null` / `portalPackage = null` specifically for "you're
  using the NixOS module to install Hyprland" (our exact setup — quoted
  directly from the option's own description) — no duplicate
  installation, no conflict with `modules/nixos/hyprland.nix`.
- `systemd.enable = true` (default) creates `hyprland-session.target`
  (`BindsTo = graphical-session.target`), and auto-generates the
  `dbus-update-activation-environment` + `systemctl --user start/stop
  hyprland-session.target` startup/shutdown hooks itself (visible in the
  test fixture's expected output) — no hand-written exec-once needed for
  that plumbing.
- Auto-generates `hypr/.luarc.json` (lua_ls workspace stubs pointing at
  the real Hyprland package's `share/hypr/stubs`) — free editor
  support for anyone editing this Lua config in `modules/home/neovim.nix`
  later.

Setting `wayland.systemd.target = "hyprland-session.target"` (top-level
`wayland.nix` option, defaults to generic `"graphical-session.target"`)
is what lets `programs.waybar`/`services.hypridle`/`services.mako`'s own
`systemd.enable`/`WantedBy` wiring actually bind to Hyprland's session
instead of a target nothing here starts.

## Nix → Lua translation rules used (from the fetched module + test fixture)

- A top-level `settings.<key>` attrset (non-list) generates **one**
  `hl.<key>({...})` call; a **list** value generates one call per
  element (used for `bind`/`env`/`on`).
- `dwindle`/`master`/`scrolling`/`misc`/`input`/`general`/`decoration`
  all nest **inside** the single `settings.config` attrset — the
  official upstream example calls `hl.config({...})` multiple times for
  these, but per the module's own doc ("multiple `hl.config()`
  invocations... each one will update just what you pass into it") one
  merged call is equivalent and simpler.
- `bind`/`env` entries need `_args = [ ... ]` (positional Lua call args).
  A dispatcher expression (`hl.dsp.window.close()`,
  `hl.dsp.exec_cmd("...")`, a `function() ... end` body) must be wrapped
  in `lib.generators.mkLuaInline "<raw lua>"` — otherwise it gets
  rendered as a quoted Lua *string*, not executable code (confirmed by
  the test fixture: plain Nix strings become quoted values, only
  `mkLuaInline`-wrapped ones render raw).
- **No `_var` locals used here** — the official example's `local mod =
  "SUPER"` exists to avoid repeating the literal in *hand-written* Lua;
  since this config is generated from Nix at build time, the Nix string
  itself is the "variable" (`"SUPER + Q"` written directly wherever
  needed) — `_var`/string-concat-via-`mkLuaInline` would be pure
  ceremony here, so skipped as unnecessary complexity (see
  `[[feedback-prefer-simplicity]]`).
- Shell commands inside `hl.dsp.exec_cmd("...")` that themselves need
  embedded double quotes (e.g. `grim -g "$(slurp)" - | wl-copy`) are
  written as `''hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy")''`
  — Nix's `''...''` string type doesn't treat `"` or `\` specially, so
  the literal `\"` characters pass through untouched into the Lua source,
  where they're the correct Lua string-escape for an embedded quote.

## Keybinds chosen

No existing spec dictated exact keys beyond Crow Translate's `SUPER+T`
(`system-plan.md` §5.11, kept as specified). The rest is a reasonable,
undocumented-elsewhere default set — a dotfile/UX choice, not an
architecture decision, so made directly rather than escalated (same
category as `zellij.nix`/`kitty.nix` shipping upstream defaults with no
custom theme):

| Bind | Action |
|---|---|
| `SUPER+RETURN` | `kitty` (terminal, already `programs.kitty.enable` in `modules/home/kitty.nix`) |
| `SUPER+Q` | close focused window |
| `SUPER+D` | `fuzzel` (app launcher) |
| `SUPER+V` | toggle floating |
| `SUPER+F` | toggle fullscreen |
| `SUPER+L` | `hyprlock` (manual lock, same binary `hypridle`'s `lock_cmd` uses) |
| `SUPER+SHIFT+S` | region screenshot → clipboard (`grim -g "$(slurp)" - \| wl-copy`) |
| `SUPER+SHIFT+V` | clipboard history picker (`cliphist list \| fuzzel --dmenu \| cliphist decode \| wl-copy`) |
| `SUPER+T` | Crow Translate `translateSelection` D-Bus call (§5.11, verbatim) |
| `SUPER+[arrows]` | move focus |
| `SUPER+[0-9]` / `SUPER+SHIFT+[0-9]` | switch / move-to workspace |
| `SUPER+mouse_down/up` | scroll through workspaces |
| `SUPER+mouse:272/273` | drag / resize window |
| `SUPER+SHIFT+Q` | `hl.dsp.exit()` (quit compositor) |

`hl.dsp.window.fullscreen`/`hl.dsp.exit`/`hl.dsp.workspace.*` dispatcher
names and signatures confirmed against the Lua API reference
(alejandrominaya.github.io/hyprland-lua-docs), not guessed — the
official `example/hyprland.lua`'s own exit bind
(`hyprctl dispatch 'hl.dsp.exit()'` shelled out as a string) looked like
a documentation artifact, not real usage; `hl.dsp.exit()` called
directly through `mkLuaInline` is what the API reference itself
documents as the real dispatcher.

## Autostart (`hl.on("hyprland.start", ...)`)

One combined hook, not scattered `exec_cmd` calls at file-load time
(which would fire on every config reload, not just session start — see
official example's own comment on why `exec-once`-equivalent needs the
`hyprland.start` hook):
```lua
hl.on("hyprland.start", function()
  hl.exec_cmd("crow-translate")
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
```
`crow-translate`: backgrounded so its D-Bus service is ready before the
first `SUPER+T` press (§5.11's own stated reason). `wl-paste --watch
cliphist store` (text + image variants): the standard way `cliphist`
actually populates its history — the package alone does nothing without
this, not previously wired anywhere in this repo.

waybar/mako/hypridle are **not** started this way — they use their own
home-manager modules' native systemd integration (see below), which is
the more idiomatic mechanism where it exists, keeping this hook minimal.

## Sub-modules used, and what's deliberately left at upstream defaults

- **`programs.waybar`**: `enable = true`, `systemd.enable = true`
  (binds to `hyprland-session.target` via the shared
  `wayland.systemd.target`), a minimal functional `settings.mainBar`
  (workspaces/clock left, pulseaudio/network/battery/tray right). No
  custom `style` (CSS) — same "no fabricated preferences, ship upstream
  defaults" boundary `kitty.nix`/`zellij.nix` already established;
  theming is a live, visual, human-only decision (`CLAUDE.md`: "Агент не
  может 'посмотреть глазами' на Hyprland").
- **`services.mako`**: `enable = true`, no `settings` — mako is
  D-Bus-activatable (`dbus.packages` wired by its own home-manager
  module), so it needs no autostart entry and no config beyond upstream
  defaults to function at all.
- **`programs.hyprlock`**: `enable = true`, no `settings` — needs the
  system-level PAM service (`modules/nixos/hyprland.nix`, added this
  round) to authenticate; visual styling is, again, a human-only later
  decision.
- **`services.hypridle`**: `enable = true`, `settings` taken directly
  from the module's own documented example (`lock_cmd = "pidof hyprlock
  || hyprlock"` guards against stacking multiple lock instances;
  `timeout = 900` → lock, `timeout = 1200` → `dpms off`, `on-resume` →
  `dpms on`) — real, required functionality (auto-lock timing), not
  invented from nothing.
- **`services.hyprpaper`**: **not enabled.** Needs a real wallpaper
  image path; this repo has no image asset, and picking one isn't a
  decision this round can make (personal choice, same boundary
  `system-plan.md` §7 already draws around personal data/preferences
  living outside git). The `hyprpaper` binary is already installed at
  the system level (`modules/nixos/hyprland.nix`) — enabling the
  home-manager service with a real path is a one-line follow-up once
  someone has a wallpaper file.

## Files

```
modules/nixos/hyprland.nix   # + security.pam.services.hyprlock = {}
modules/home/hyprland.nix    # new — everything above
```

## Test Host

`hosts/test-hyprland-config/` — new, not a reuse of
`hosts/test-hyprland/` (that host intentionally has no home-manager
wiring, scoped to the system-module-only round). Mirrors
`hosts/test-neovim/`'s shape: ext4 `/dev/vda1` + grub, throwaway
`testuser`, imports `modules/nixos/boot.nix` +
`modules/nixos/hyprland.nix` (so `package = null` resolves against a
real Hyprland) + `modules/nixos/home-manager.nix`, with
`home-manager.users.testuser` importing `modules/home/hyprland.nix`.
Real (non-dry-run) build:
```
nix build .#nixosConfigurations.test-hyprland-config.config.system.build.toplevel
```

## Explicitly not verified here

Same boundary as the base Hyprland round and every other desktop-facing
module in this repo: no VM boot (no GPU/display in this sandbox), no
visual check, no proof that `hyprland-session.target` actually gets
reached at runtime (that depends on how the display/session manager on
real hardware starts a Hyprland session — genuinely a `hosts/mimir/`
real-install-time concern, not something a throwaway NixOS build can
exercise). What's verified: the Nix side — every package resolves and
builds, the generated `hyprland.lua`/`.luarc.json`/waybar-mako-hypridle
config files are structurally well-formed (home-manager's own module
already asserts internal consistency, e.g. rejecting a submap named
`"reset"`), and PAM/systemd unit definitions evaluate without error.

## Out of Scope

- `services.hyprpaper` (wallpaper) — see above.
- Waybar CSS theming, mako notification styling, hyprlock visual
  layout — upstream defaults, human/visual decision.
- `wf-recorder` keybind — no clean start/stop toggle without a
  fragile PID-tracking script; package is already on `$PATH`
  (`modules/nixos/hyprland.nix`), invoke manually from a terminal.
- `hosts/mimir/`'s real session — still needs a real user
  (`home-manager.users.<name>`), unchanged boundary from every prior
  "real hardware" gap in this repo.
