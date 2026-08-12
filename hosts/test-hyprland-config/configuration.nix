# Throwaway verification host for modules/home/hyprland.nix (real
# config content) -- NOT a real target machine, and NOT hosts/mimir/.
# Mirrors hosts/test-neovim/'s shape (ext4 /dev/vda1 + grub, throwaway
# testuser, no qemu-vm.nix). Real build, not dry-run -- see
# docs/superpowers/specs/2026-08-12-hyprland-config-design.md
# "Explicitly not verified here": proves the Nix-side inputs (package
# resolution, generated hyprland.lua/.luarc.json/waybar-mako-hypridle
# config, PAM/systemd unit definitions) are structurally correct. Does
# NOT prove hyprland-session.target is actually reached at runtime, or
# anything visual -- real-hardware-and-human-eyes-only, same boundary as
# hosts/test-hyprland/'s own header comment.
#
# Imports modules/nixos/hyprland.nix (not just boot.nix) so that
# modules/home/hyprland.nix's package = null / portalPackage = null
# resolve against a real programs.hyprland.enable, matching how this
# module is actually meant to be used.
{ ... }:
{
  imports = [
    ../../modules/nixos/boot.nix
    ../../modules/nixos/hyprland.nix
    ../../modules/nixos/home-manager.nix
  ];

  fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
  boot.loader.grub.device = "/dev/vda";

  users.users.testuser = {
    isNormalUser = true;
    home = "/home/testuser";
  };
  home-manager.users.testuser = {
    imports = [ ../../modules/home/hyprland.nix ];
    home.stateVersion = "24.05";
  };

  system.stateVersion = "24.05";
}
