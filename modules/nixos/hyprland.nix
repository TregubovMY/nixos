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
  programs.hyprland = {
    enable = true;
    # UWSM (Universal Wayland Session Manager) -- greetd was execing the
    # raw `Hyprland` binary (see modules/nixos/greetd.nix), which prints
    # "Hyprland was started without start-hyprland. This is strongly
    # discouraged..." on every boot: a real, upstream-documented warning
    # (github.com/hyprwm/Hyprland/discussions/12661), not cosmetic noise
    # from this repo's own config. Root cause: launched that way, Hyprland
    # never imports its env into systemd/D-Bus activation environment and
    # never starts graphical-session(-pre).target itself, so anything
    # depending on those targets (portals, xdg-autostart) is relying on
    # luck/ordering, not a real dependency. withUWSM = true switches on
    # this module's own upstream integration (confirmed by reading this
    # repo's pinned nixpkgs rev's nixos/modules/programs/wayland/
    # hyprland.nix directly, not assumed from memory): it flips
    # programs.uwsm.enable on automatically and makes `start-hyprland` (a
    # wrapper the Hyprland package itself ships) the real entrypoint --
    # greetd's --cmd changes to that wrapper below. NOT setting
    # programs.uwsm.waylandCompositors by hand -- that generates a
    # separate "Hyprland (UWSM)" *.desktop entry for session-picker
    # display managers (GDM/SDDM-style); greetd/tuigreet here selects the
    # session via --cmd directly, so that entry would just be dead
    # config. NOT relevant here: the wiki's "disable
    # wayland.windowManager.hyprland.systemd.enable" caveat -- this repo
    # never used that home-manager module at all (see modules/home/
    # hyprland.nix's own header comment on why), so there's no conflict
    # to disable.
    withUWSM = true;
  };

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
    # Reported live: dock/taskbar/launcher in DMS showed no app icons at
    # all. Root cause -- this repo never installed ANY icon theme
    # anywhere (grepped modules/home, modules/nixos: zero hits before
    # this). DMS resolves icons through the Qt6 icon theme system and,
    # per its own docs (danklinux.com/docs/dankmaterialshell/
    # icon-theming), reads QS_ICON_THEME if set, which overrides
    # everything else -- simpler than also wiring qt6ct.conf/gtk
    # settings.ini just to name a theme. papirus-icon-theme: DMS's own
    # docs list it first under "Material Design style", matching DMS's
    # own Material Design aesthetic. hicolor-icon-theme: freedesktop's
    # base fallback theme, so apps whose .desktop Icon= isn't covered by
    # Papirus still get *something* instead of a blank square.
    papirus-icon-theme
    hicolor-icon-theme
  ];

  # QS_ICON_THEME takes precedence over DMS's other icon-theme lookup
  # paths (gtk3/qt6ct/kde config files) per DMS's own docs -- one env
  # var instead of also maintaining a qt6ct.conf/gtk settings.ini just
  # for this. environment.sessionVariables (not home-manager) because
  # DMS/Hyprland pick up the graphical session's environment before any
  # per-user home-manager session vars would apply.
  environment.sessionVariables.QS_ICON_THEME = "Papirus-Dark";
}
