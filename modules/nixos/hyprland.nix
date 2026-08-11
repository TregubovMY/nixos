# Hyprland compositor + its supporting package stack (system-plan.md
# §5.2). programs.hyprland.enable already defaults xdg.portal.enable,
# portalPackage (-> xdg-desktop-portal-hyprland), and xwayland.enable to
# working values -- confirmed by evaluating the module's real option
# defaults against this repo's pinned nixpkgs (see
# docs/superpowers/specs/2026-08-11-hyprland-design.md "Research
# findings"), not assumed from §5.2's flat package list. No real Hyprland
# config content here (keybinds, waybar widgets, theme, exec-once
# autostart) -- that needs home-manager dotfiles (modules/home/*, not
# built yet), a separate later task, same boundary the desktop-packages
# and home-manager rounds already drew.
{ pkgs, ... }:
{
  programs.hyprland.enable = true;

  environment.systemPackages = with pkgs; [
    waybar
    fuzzel
    mako
    hyprlock
    hypridle
    grim
    slurp
    wf-recorder
    hyprpaper
    cliphist
    wl-clipboard
    # Hyprland's own polkit agent, not polkit-gnome -- system-plan.md
    # §5.2 left this an open either/or; hyprpolkitagent is actively
    # maintained by the Hyprland project itself and purpose-built for
    # this exact compositor rather than borrowed from GNOME. See design
    # doc "Research findings" for the full comparison.
    hyprpolkitagent
    # qt5ct/qt6ct + kvantum: system-plan.md §5.2's single "qt5/qt6ct +
    # kvantum" bullet is actually four separate packages at non-obvious
    # attribute paths -- bare qt6ct doesn't exist (renamed), bare qt5ct
    # doesn't exist either (needs libsForQt5 prefix). Confirmed against
    # this repo's pinned nixpkgs via nix eval, not assumed.
    libsForQt5.qt5ct
    qt6Packages.qt6ct
    libsForQt5.qtstyleplugin-kvantum
    kdePackages.qtstyleplugin-kvantum
  ];
}
