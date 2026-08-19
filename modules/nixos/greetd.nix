# Display manager for the Hyprland session (system-plan.md never named
# one -- gap found live while rehearsing hosts/mimir-vm-full: no display
# manager meant landing on a plain TTY every boot, `Hyprland` had to be
# typed by hand). greetd + tuigreet, not a GTK/Qt greeter (gtkgreet/
# regreet) or a full display manager (SDDM/GDM): tuigreet is a single
# lightweight TUI binary purpose-built for greetd, no extra desktop
# toolkit pulled in just to show a login prompt -- same "don't add a
# whole stack for one small piece" reasoning as hyprpolkitagent over
# polkit-gnome in modules/nixos/hyprland.nix. greetd itself (not
# lightdm/sddm) is also the pairing Hyprland's own wiki documents as the
# standard minimal choice for a Wayland-only, single-compositor machine.
{ pkgs, ... }:
{
  services.greetd = {
    enable = true;
    # Avoids systemd boot messages interrupting the TUI -- exactly what
    # this option's own description says to set for a tuigreet-like
    # greeter (checked nixos/modules/services/display-managers/greetd.nix
    # at this repo's pinned nixpkgs rev, not assumed).
    useTextGreeter = true;
    # --cmd start-hyprland, NOT --cmd Hyprland: the latter execs the
    # compositor binary raw, which upstream Hyprland flags with "started
    # without start-hyprland... strongly discouraged" on every boot (real
    # bug found live -- github.com/hyprwm/Hyprland/discussions/12661 --
    # not just a cosmetic message, see modules/nixos/hyprland.nix's
    # withUWSM comment for what it actually breaks). `start-hyprland` is
    # the wrapper the Hyprland package itself ships (confirmed in this
    # repo's pinned nixpkgs -- programs.hyprland's own `enable` option
    # docs it directly), and is what withUWSM's systemd/UWSM integration
    # (enabled in hyprland.nix) actually expects to be launched through.
    settings.default_session.command =
      "${pkgs.tuigreet}/bin/tuigreet --time --remember --asterisks --cmd start-hyprland";
  };
}
