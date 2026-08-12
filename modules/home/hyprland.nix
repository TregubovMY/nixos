# Real Hyprland desktop config -- now built on DankMaterialShell (DMS), a
# Quickshell-based desktop shell, per explicit user request after
# hand-styled waybar/mako/hyprlock iterations were repeatedly flagged as
# "выглядит плохо/пусто". DMS replaces waybar, mako, hyprlock, hypridle,
# fuzzel, and the polkit agent as one integrated system (confirmed
# against DankMaterialShell's own README: "It replaces waybar, swaylock,
# swayidle, mako, fuzzel, polkit, and everything else you'd normally
# stitch together") -- see docs/superpowers/plans/tingly-doodling-phoenix.md
# for the fuller discussion (why not end-4/dots-hyprland directly: that
# repo is an Arch/AUR-specific installer with configs for apps we don't
# use, not portable to NixOS; DMS ships real nixosModules/homeModules
# under distro/nix/, fetched and read in full before wiring this in).
#
# IMPORTANT — deliberately NOT using home-manager's own
# wayland.windowManager.hyprland module at all, even just for its
# systemd.enable session-target wiring. Checked live: that module claims
# xdg.configFile."hypr/hyprland.conf"/".lua" as a home-manager-managed
# (read-only, Nix-store-symlinked) file the moment `enable = true` is
# set, REGARDLESS of whether settings/extraConfig are populated -- its
# own `config` block sets xdg.configFile unconditionally under
# `mkIf cfg.enable`. DMS's own `dms setup` CLI (interactive, run once
# after first login) needs to WRITE ~/.config/hypr/hyprland.lua and
# ~/.config/hypr/dms/*.lua (colors/outputs/layout/cursor/binds/
# binds-user/windowrules) itself and keep them DMS-managed from then on
# (confirmed via DMS's own docs/Hyprland_Lua_Migration.md, fetched and
# read in full) -- a Nix-owned symlink there would block that outright.
# So this repo leaves ~/.config/hypr/ entirely unmanaged by Nix/home-
# manager, fully owned by DMS. Same "genuinely impure, accepted"
# category as LazyVim's lazy.nvim bootstrap in modules/home/neovim.nix,
# one step further (not even a Nix-vendored starting point -- DMS
# bootstraps the whole directory from nothing via `dms setup`).
#
# Consequence: programs.dank-material-shell.systemd.enable is left off
# too -- that option's WantedBy target (wayland.systemd.target,
# "graphical-session.target" by default) is normally reached via
# wayland.windowManager.hyprland's own dbus-update-activation-environment
# + hyprland-session.target dance, which isn't available here. DMS's own
# `dms setup` writes the real startup wiring (an exec-once line launching
# `dms run` directly from Hyprland's own config) instead -- no systemd
# session-target chain needed on our side.
#
# Custom keybinds this repo previously hand-wrote in Nix (Crow Translate
# hotkey, cliphist picker, screenshot bind) are consequently NOT
# reproduced here either -- they'd need to be re-added by hand into
# ~/.config/hypr/dms/binds-user.lua after `dms setup`, the same
# human-editable, DMS-managed file its own Settings UI writes to. Noted
# as a follow-up, not silently dropped.
{ ... }:
{
  # quickshell itself comes from home-manager's own programs.quickshell
  # module (confirmed present at this repo's pinned home-manager rev) --
  # programs.dank-material-shell's own home.nix sets
  # programs.quickshell.enable = true automatically, so it isn't
  # separately enabled here.
  programs.dank-material-shell.enable = true;
}
