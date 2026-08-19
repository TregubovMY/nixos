# Real host identity + module composition for mimir. Deliberately
# incomplete and NOT registered as nixosConfigurations.mimir in flake.nix
# — see docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md
# for exactly what's missing (hardware-configuration.nix, flake.nix
# registration, users.users.max) and why each is a separate, future,
# real-hardware-only step, not this file's job. Do not treat this file's
# mere existence as "mimir is installable."
#
# 2026-08-13: module list brought up to parity with hosts/mimir-vm-full/,
# which already VM-rehearsed this exact set (hyprland.nix/greetd.nix/
# nix-settings.nix/dev-databases.nix/podman.nix/home-manager.nix) end to
# end, including the "Hyprland: command not known" gap that surfaced when
# hyprland.nix was missing and the tuigreet/zsh-shell gaps documented in
# that host's own configuration.nix. None of these six need a real user
# to already exist -- checked each module doesn't reference users.users.*
# -- unlike users.users.max/home-manager.users.max itself, which stays
# out per the skeleton design doc's own reasoning (real auth is a human
# decision at install time, not something to pre-bake here).
#
# 2026-08-18: no secrets.nix / sops-nix import anymore — system-plan.md §7
# resolved the one secret that used to live there (GPG key for git commit
# signing) to Bitwarden instead, same place SSH keys and the Throne proxy
# config already are (§6). sops-nix is no longer part of this plan at all.
{
  imports = [
    ./disk-config.nix
    ../../modules/nixos/secure-boot.nix # not boot.nix — lanzaboote
      # replaces systemd-boot rather than layering on it (secure-boot.nix
      # itself force-disables boot.loader.systemd-boot.enable); mimir
      # wants Secure Boot per system-plan.md §2/§4.
    ../../modules/nixos/desktop-apps.nix
    ../../modules/nixos/hyprland.nix
    ../../modules/nixos/greetd.nix
    ../../modules/nixos/nix-settings.nix
    ../../modules/nixos/dev-databases.nix
    ../../modules/nixos/podman.nix
    ../../modules/nixos/home-manager.nix
    ../../modules/nixos/nix-ld.nix
  ];

  networking.hostName = "mimir";
  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "ru_RU.UTF-8";

  # Required because desktop-apps.nix pulls in unfree packages (RubyMine,
  # Chrome, VSCode, Postman) and flake.nix's allowUnfree = true only
  # applies to its own loose `pkgs` instance (packages.${system}), not to
  # any nixosSystem call — same requirement hosts/test-desktop-apps/
  # already has, see system-plan.md §2.
  nixpkgs.config.allowUnfree = true;

  # Gap mimir-vm-full's rehearsal found live: modules/home/shell.nix's
  # programs.zsh.enable (home-manager level) configures zsh but doesn't
  # register it in /etc/shells, which users.users.<name>.shell needs --
  # harmless to set now even before a real user exists, and one less
  # thing to remember at real-install time.
  programs.zsh.enable = true;

  system.stateVersion = "24.05"; # matches every other host in this repo
}
