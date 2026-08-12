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
# Correction, found live: `dms setup` itself asks "Use systemd for
# session management?" and defaults to/recommends Yes -- when answered
# Yes (as it was here), the config it deploys expects a real `dms.service`
# systemd user unit to exist and starts DMS through it, not via a plain
# exec-once. Originally left programs.dank-material-shell.systemd.enable
# off on the theory that DMS would launch itself directly with no
# systemd involved -- wrong for the systemd-managed path `dms setup`
# actually offers and this session used. Symptom was a real blank
# Hyprland session (bare cursor, DMS never appeared) because Hyprland's
# generated config tried to start a systemd unit that didn't exist.
# Enabled below to match.
#
# Second correction, found live after the above fix still produced a
# blank session on the NEXT boot: enabling programs.dank-material-shell's
# own systemd service isn't enough by itself. `dms setup`'s generated
# ~/.config/hypr/hyprland.lua execs
# `systemctl --user start hyprland-session.target` on startup (confirmed
# by grepping the actual deployed file) -- the exact target
# wayland.windowManager.hyprland's own systemd.enable used to create
# (back when this module still used that module, before the
# xdg.configFile conflict above). Removing that module also removed the
# target definition, but DMS's own generated config still assumes it
# exists -- `systemctl --user start` on a target with no unit file just
# fails silently, so dms.service (WantedBy = graphical-session.target,
# the default) never gets pulled in. Fix: recreate ONLY the target unit
# itself here (not the whole conflicting module) -- BindsTo
# graphical-session.target, same shape
# wayland.windowManager.hyprland's own module used internally, so
# DMS's exec-once line has something real to start.
{ pkgs, ... }:
{
  # quickshell itself comes from home-manager's own programs.quickshell
  # module (confirmed present at this repo's pinned home-manager rev) --
  # programs.dank-material-shell's own home.nix sets
  # programs.quickshell.enable = true automatically, so it isn't
  # separately enabled here.
  programs.dank-material-shell = {
    enable = true;
    systemd.enable = true;
  };

  systemd.user.targets.hyprland-session = {
    Unit = {
      Description = "Hyprland compositor session";
      BindsTo = [ "graphical-session.target" ];
      Wants = [ "graphical-session-pre.target" ];
      After = [ "graphical-session-pre.target" ];
    };
  };

  # Requested live: a real cursor theme instead of the default GTK
  # fallback ("уродски"). Just the package -- selecting it is a DMS
  # Settings → Cursor action (writes ~/.config/hypr/dms/cursor.lua
  # itself, not Nix-managed, same boundary as the rest of ~/.config/hypr/
  # this module already draws).
  home.packages = [ pkgs.bibata-cursors ];
}
