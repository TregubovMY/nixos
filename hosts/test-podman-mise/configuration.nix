# Throwaway verification host for modules/nixos/podman.nix +
# modules/home/mise.nix -- NOT a real target machine, and NOT
# hosts/mimir/. Mirrors hosts/test-shell/'s shape (ext4 /dev/vda1 + grub,
# throwaway testuser, no qemu-vm.nix). Real build: podman.nix pulls in a
# systemd-level service (podman socket/setuid helpers), worth confirming
# it actually builds, not just evaluates.
{ ... }:
{
  imports = [
    ../../modules/nixos/boot.nix
    ../../modules/nixos/home-manager.nix
    ../../modules/nixos/podman.nix
  ];

  fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
  boot.loader.grub.device = "/dev/vda";

  users.users.testuser = {
    isNormalUser = true;
    home = "/home/testuser";
  };
  home-manager.users.testuser = {
    imports = [ ../../modules/home/mise.nix ];
    home.stateVersion = "24.05";
  };

  system.stateVersion = "24.05";
}
