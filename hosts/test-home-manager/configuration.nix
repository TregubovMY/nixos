# Throwaway verification host for the home-manager infrastructure design —
# NOT a real target machine, and NOT hosts/mimir/. Mirrors
# hosts/test-desktop-apps/'s shape exactly (ext4 /dev/vda1 + grub, no
# qemu-vm.nix import) since this only needs eval + a real build, no VM
# boot -- see docs/superpowers/specs/2026-08-11-home-manager-design.md
# "Testing" for why.
#
# testuser exists only to give home-manager.users.* something to bind to
# -- same throwaway-only status as hosts/test-disko-luks/'s virtual disk
# or hosts/test-secrets/'s test SSH key. NOT a preview of mimir's real
# username; hosts/mimir/configuration.nix still has no users.users.* or
# home-manager.users.* block (see docs/superpowers/specs/
# 2026-08-11-mimir-host-skeleton-design.md) and this host doesn't change
# that.
{ ... }:
{
  imports = [
    ../../modules/nixos/boot.nix
    ../../modules/nixos/home-manager.nix
  ];

  fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
  boot.loader.grub.device = "/dev/vda";

  users.users.testuser = {
    isNormalUser = true;
    home = "/home/testuser";
  };
  home-manager.users.testuser = {
    home.stateVersion = "24.05";
  };

  system.stateVersion = "24.05";
}
