# Throwaway verification host for modules/home/shell.nix + zellij.nix --
# NOT a real target machine, and NOT hosts/mimir/. Mirrors
# hosts/test-home-manager/'s shape (ext4 /dev/vda1 + grub, throwaway
# testuser, no qemu-vm.nix) but is a separate host, not an extension of
# it -- keeps hosts/test-home-manager/ as the pure "infra only, no
# content" proof its own header comment already documents, unmutated.
# See docs/superpowers/specs/2026-08-11-shell-zellij-design.md "Testing"
# for why this gets a real build, not just eval/dry-run: unlike the
# Hyprland round, this content has real activation-time behavior
# (dotfiles actually get written).
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
      ../../modules/home/shell.nix
      ../../modules/home/zellij.nix
    ];
    home.stateVersion = "24.05";
  };

  system.stateVersion = "24.05";
}
