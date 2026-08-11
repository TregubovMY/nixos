# Throwaway verification host for modules/home/neovim.nix (base LazyVim)
# -- NOT a real target machine, and NOT hosts/mimir/. Mirrors
# hosts/test-shell/'s shape (ext4 /dev/vda1 + grub, throwaway testuser,
# no qemu-vm.nix). Real build, not dry-run -- see docs/superpowers/specs/
# 2026-08-11-neovim-base-design.md "Explicitly not verified here": this
# proves the Nix-side inputs (package list, vendored config symlinking)
# build correctly. It does NOT prove lazy.nvim's own first-run plugin
# install succeeds -- that's genuinely impure/network-dependent and out
# of what this sandbox can verify, same category as Hyprland's visual
# check.
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
    imports = [ ../../modules/home/neovim.nix ];
    home.stateVersion = "24.05";
  };

  system.stateVersion = "24.05";
}
