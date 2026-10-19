# Display manager for the Hyprland session (system-plan.md never named
# one -- gap found live while rehearsing hosts/mimir-vm-full: no display
# manager meant landing on a plain TTY every boot, `Hyprland` had to be
# typed by hand).
#
# 2026-10-18: switched from greetd+tuigreet (a TUI prompt -- plain black
# text screen, reported live as looking "странный"/broken rather than a
# normal login screen) to services.displayManager.dms-greeter: nixpkgs'
# own NixOS module for DankMaterialShell's graphical greetd greeter
# (nixos/modules/services/display-managers/dms-greeter.nix, confirmed
# present at this repo's pinned nixpkgs rev after the 2026-10-15 nixpkgs
# bump). It runs an actual Hyprland+Quickshell/DMS instance as a dedicated
# `dms-greeter` system user to render the login UI -- same visual system as
# the real desktop session, not a hand-built login screen -- then hands off
# to the selected session via greetd's normal protocol once authenticated.
# Still greetd underneath (Hyprland wiki's documented minimal pairing for a
# Wayland-only, single-compositor machine), just a themed Quickshell UI
# instead of tuigreet's TUI -- not a jump to a full desktop-environment
# display manager (SDDM/GDM).
#
# The module itself sets services.greetd.enable/settings (mkDefault) and
# all the wiring (PAM service, system user, cache dir under
# /var/lib/dms-greeter) -- nothing more to declare here for that part.
{ ... }:
{
  services.displayManager.dms-greeter = {
    enable = true;
    # Must match a `programs.<name>.enable` -- programs.hyprland.enable is
    # set in modules/nixos/hyprland.nix; the module asserts this itself.
    compositor.name = "hyprland";
    # Copies max's own ~/.config/DankMaterialShell/settings.json,
    # ~/.local/state/DankMaterialShell/session.json and
    # ~/.cache/DankMaterialShell/dms-colors.json into the greeter's own
    # /var/lib/dms-greeter cache (module's own configFilesFromHome logic)
    # on every greetd start -- so the login screen shows the same
    # wallpaper/theme/colors as the real desktop instead of DMS's stock
    # defaults. Read-only copy, not a shared state file -- the greeter
    # user never writes back into max's home.
    configHome = "/home/max";
  };

  # Real root cause of the "автозапуск не работает" (XDG autostart silently
  # not running -- ~/.config/autostart/*.desktop entries like Bitwarden/
  # Telegram/Throne never launched) found live 2026-10-18: tuigreet's old
  # `--cmd start-hyprland` launched the compositor directly, bypassing UWSM
  # entirely despite programs.hyprland.withUWSM = true (confirmed live --
  # no `uwsm` process in the tree, `xdg-desktop-autostart.target` and every
  # `wayland-session*`/`wayland-wm*` unit stayed unloaded/ignored the whole
  # session). UWSM's own session chain is what starts
  # `xdg-desktop-autostart.target` (confirmed in nixpkgs'
  # nixos/modules/system/boot/systemd/user.nix and .../none.nix) -- it was
  # simply never engaged. The actual UWSM entrypoint is the
  # `hyprland-uwsm.desktop` session file Hyprland's own nixpkgs module
  # already generates (`Exec=uwsm start -e -D Hyprland hyprland.desktop`,
  # confirmed present at /run/current-system/sw/share/wayland-sessions/)
  # -- a previous comment here assumed plain `start-hyprland` was correct
  # for the UWSM path too; that assumption was wrong, this is the fix.
  # dms-greeter resolves the session to launch via
  # services.displayManager.defaultSession (nixos/modules/services/
  # display-managers/default.nix, validated against the discovered
  # sessionData.sessionNames -- "hyprland-uwsm" is one of them since
  # programs.hyprland sets services.displayManager.sessionPackages to its
  # own package, which ships both hyprland.desktop and
  # hyprland-uwsm.desktop).
  services.displayManager.defaultSession = "hyprland-uwsm";

  # Secret Service (system keyring), unlocked by the login password typed
  # into the greeter (pam_gnome_keyring on its PAM stack), so nothing asks
  # for a second password. Added 2026-10-06 for DankCalendar, which keeps
  # Google OAuth tokens in the keyring (modules/home/calendar.nix); Chrome,
  # VS Code and others use the same Secret Service when it exists instead
  # of weaker fallbacks. Wired on both PAM services: "greetd" (greetd's own
  # fixed PAM service name, used for the actual session handoff) and
  # "dms-greeter" (the module's own separate PAM service -- confirmed in
  # its source, used for the greeter UI's own auth conversation, e.g. the
  # fprintd hardware probe) -- harmless to enable on either if unused by a
  # given auth path, so both are covered rather than guessing which one
  # actually fires the keyring unlock.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;
  security.pam.services.dms-greeter.enableGnomeKeyring = true;
}
