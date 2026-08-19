# Real host identity + module composition for mimir. Deliberately
# incomplete and NOT registered as nixosConfigurations.mimir in flake.nix
# — see docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md
# for exactly what's missing (hardware-configuration.nix, flake.nix
# registration, users.users.max) and why each is a separate, future,
# real-hardware-only step, not this file's job. Do not treat this file's
# mere existence as "mimir is installable."
#
# No secrets.nix / sops-nix import — system-plan.md §7 resolved the one
# secret that used to live there (GPG key for git commit signing) to
# Bitwarden instead, same place SSH keys and the Throne proxy config
# already are (§6). sops-nix is no longer part of this plan at all.
{
  imports = [
    ./disk-config.nix
    ../../modules/nixos/secure-boot.nix # not boot.nix — lanzaboote
      # replaces systemd-boot rather than layering on it (secure-boot.nix
      # itself force-disables boot.loader.systemd-boot.enable); mimir
      # wants Secure Boot per system-plan.md §2/§4.
    ../../modules/nixos/desktop-apps.nix
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

  system.stateVersion = "24.05"; # matches every other host in this repo
}
