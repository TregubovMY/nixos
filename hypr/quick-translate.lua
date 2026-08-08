-- Crow Translate hotkey integration — see system-plan.md §5.11 and
-- docs/superpowers/plans/2026-08-04-translation-utility.md. Include this
-- file from your main hyprland.lua, e.g.:
--   require("quick-translate")
-- (Lua's require() resolves against Hyprland's config Lua path, which
-- includes $XDG_CONFIG_HOME/hypr — see
-- https://wiki.hypr.land/Configuring/Advanced-and-Cool/Expanding-functionality/
-- for the split-config pattern. Symlink or copy this file into
-- ~/.config/hypr/ so it's on that path; exact layout depends on where
-- this repo is checked out.)
--
-- Wayland has no global-shortcut API of its own — Crow Translate's D-Bus
-- method is the documented integration point for compositors like
-- Hyprland that can bind arbitrary shell commands to keys (unlike GNOME,
-- which needs its own separate global-shortcuts D-Bus portal setup).
--
-- Syntax note (checked against github.com/hyprwm/Hyprland's
-- example/hyprland.lua and wiki.hypr.land, 2026-08-08): as of Hyprland
-- 0.55 (released 2026-05-09), hyprlang (the old `.conf` format used by
-- this snippet's first draft) is deprecated in favor of this Lua config
-- format, and hyprlang support is slated to be dropped after roughly 1-2
-- more releases. Since this repo has no hyprland.conf/hyprland.lua yet
-- (see system-plan.md §3/§5.2 — the Hyprland module isn't built out),
-- there's no existing format to stay consistent with, so this was written
-- directly in Lua rather than in the format about to be deprecated.
--
-- `hl` below is a global injected by Hyprland's Lua runtime — no
-- `require("hyprland")` needed (confirmed from the upstream example
-- config, which uses `hl.*` directly with no such import).

-- mainMod is normally a `local` in the main hyprland.lua (see upstream
-- example: `local mainMod = "SUPER"`), and Lua's `require()` gives this
-- file its own scope — it doesn't inherit the caller's locals. Re-declared
-- here so this snippet is self-contained; keep it in sync with whatever
-- mainMod the rest of the config uses once one exists.
local mainMod = "SUPER"

-- Crow Translate needs to be running for its D-Bus service to answer —
-- launch it at session start rather than requiring a manual launch
-- before the hotkey works. NOTE: "start minimized to tray" is a GUI
-- setting on Crow Translate's own General tab, not a CLI flag — this
-- command does not force it. On a fresh install expect a visible window
-- at first login until that setting is turned on manually (tracked in
-- the README's manual-verification checklist).
hl.on("hyprland.start", function()
  hl.exec_cmd("crow-translate")
end)

-- Translate the current text selection on hotkey press.
--
-- MANUAL VERIFICATION REQUIRED (agent cannot check this — no visual/runtime
-- access to a running Hyprland session, per CLAUDE.md): confirm the hotkey
-- actually fires, the translation popup appears, and mainMod+T does not
-- collide with another existing bind in your hyprland.lua. Tracked as a
-- follow-up in the task-3 README.
hl.bind(
  mainMod .. " + T",
  hl.dsp.exec_cmd(
    "gdbus call --session --dest io.crow_translate.CrowTranslate "
      .. "--object-path /io/crow_translate/CrowTranslate/MainWindow "
      .. "--method io.crow_translate.CrowTranslate.MainWindow.translateSelection"
  )
)
