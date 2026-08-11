# Throwaway verification host for the Hyprland module + package list —
# NOT a real target machine, and NOT hosts/mimir/. Mirrors
# hosts/test-desktop-apps/'s shape exactly (ext4 /dev/vda1 + grub, no
# qemu-vm.nix import, no VM boot) -- same testing depth, see
# docs/superpowers/specs/2026-08-11-hyprland-design.md "Testing" for why:
# programs.hyprland.enable is structurally the same kind of thing as
# programs.throne.enable/programs.kdeconnect.enable, both already proven
# there. No nixpkgs.config.allowUnfree needed -- every package in
# hyprland.nix is FOSS (confirmed at design time, re-confirmed for real
# by this host's own dry-build below).
{ ... }:
{
  imports = [
    ../../modules/nixos/boot.nix
    ../../modules/nixos/hyprland.nix
  ];

  fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
  boot.loader.grub.device = "/dev/vda";

  system.stateVersion = "24.05";
}
