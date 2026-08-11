# Throwaway verification host for modules/home/kitty.nix + direnv.nix --
# NOT a real target machine, and NOT hosts/mimir/. Mirrors
# hosts/test-shell/'s shape (ext4 /dev/vda1 + grub, throwaway testuser,
# no qemu-vm.nix). Real build, same reasoning as shell.nix/neovim.nix --
# both modules have real activation-time content (kitty.conf, direnv
# shell hook wiring).
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
    imports = [
      ../../modules/home/kitty.nix
      ../../modules/home/direnv.nix
    ];
    home.stateVersion = "24.05";
  };

  system.stateVersion = "24.05";
}
