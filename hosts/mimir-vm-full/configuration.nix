# Full-system VM rehearsal -- NOT hosts/mimir/ (no real
# hardware-configuration.nix, no secrets.nix -- sops needs a real SSH
# host key, chicken-and-egg for a VM that doesn't exist until installed;
# see docs/superpowers/plans/tingly-doodling-phoenix.md), and broader in
# scope than hosts/mimir-vm-rehearsal/ (which only proved disko+LUKS+
# btrfs+Secure Boot boot). This host pulls in everything else this repo
# has actually built: desktop-apps.nix, dev-databases.nix, podman.nix,
# home-manager.nix at the system level, plus a real home-manager user
# (max, matching the username already anticipated by
# docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md)
# importing hyprland.nix/neovim.nix/shell.nix/zellij.nix/kitty.nix/
# direnv.nix/mise.nix -- the actual day-to-day desktop config, not just
# the disk/boot layer.
{ ... }:
{
  imports = [
    ./disk-config.nix
    ../../modules/nixos/secure-boot.nix
    ../../modules/nixos/desktop-apps.nix
    ../../modules/nixos/dev-databases.nix
    ../../modules/nixos/podman.nix
    ../../modules/nixos/home-manager.nix
  ];

  # Same gap as hosts/mimir-vm-rehearsal/ -- no hardware-configuration.nix,
  # so the initrd needs the virtio block driver declared by hand. See
  # that host's configuration.nix for the full explanation.
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_scsi" ];

  # desktop-apps.nix pulls in unfree packages (rubymine, google-chrome,
  # vscode, etc, per CLAUDE.md "Правила для пакетов") -- hosts/mimir/
  # already sets this, mirrored here for the same reason.
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "mimir-vm-full";

  # Rehearsal-only convenience, same as hosts/mimir-vm-rehearsal/'s root
  # password -- NOT how hosts/mimir/ should ever be configured (real
  # install needs a real decision about auth, see system-plan.md §7).
  users.users.max = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "max";
  };

  home-manager.users.max = {
    imports = [
      ../../modules/home/hyprland.nix
      ../../modules/home/neovim.nix
      ../../modules/home/shell.nix
      ../../modules/home/zellij.nix
      ../../modules/home/kitty.nix
      ../../modules/home/direnv.nix
      ../../modules/home/mise.nix
    ];
    home.stateVersion = "24.05";
  };

  system.stateVersion = "24.05";
}
