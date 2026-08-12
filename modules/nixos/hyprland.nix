# Hyprland compositor + its supporting package stack (system-plan.md
# §5.2). programs.hyprland.enable already defaults xdg.portal.enable,
# portalPackage (-> xdg-desktop-portal-hyprland), and xwayland.enable to
# working values -- confirmed by evaluating the module's real option
# defaults against this repo's pinned nixpkgs (see
# docs/superpowers/specs/2026-08-11-hyprland-design.md "Research
# findings"), not assumed from §5.2's flat package list. Real config
# content lives in modules/home/hyprland.nix, see
# docs/superpowers/specs/2026-08-12-hyprland-config-design.md and
# docs/superpowers/plans/tingly-doodling-phoenix.md for the later
# DankMaterialShell switch.
#
# waybar/fuzzel/mako/hyprlock/hypridle/hyprpolkitagent used to be listed
# here -- removed, DankMaterialShell (modules/home/hyprland.nix) replaces
# all of them as one integrated system (confirmed against its own
# README's explicit "replaces waybar, swaylock, swayidle, mako, fuzzel,
# polkit" claim). security.pam.services.hyprlock removed for the same
# reason -- DMS's own lock screen handles PAM itself (its NixOS module
# sets up a dedicated dankshell-u2f PAM service when its security-key
# option is enabled, not used here).
{ pkgs, ... }:
{
  programs.hyprland.enable = true;

  environment.systemPackages = with pkgs; [
    grim
    slurp
    wf-recorder
    hyprpaper
    cliphist
    wl-clipboard
    # qt5ct/qt6ct + kvantum: system-plan.md §5.2's single "qt5/qt6ct +
    # kvantum" bullet is actually four separate packages at non-obvious
    # attribute paths -- bare qt6ct doesn't exist (renamed), bare qt5ct
    # doesn't exist either (needs libsForQt5 prefix). Confirmed against
    # this repo's pinned nixpkgs via nix eval, not assumed. Unrelated to
    # DMS (Qt theming for other Qt apps like RubyMine), kept.
    libsForQt5.qt5ct
    qt6Packages.qt6ct
    libsForQt5.qtstyleplugin-kvantum
    kdePackages.qtstyleplugin-kvantum
  ];
}
