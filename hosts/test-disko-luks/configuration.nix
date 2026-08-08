# Throwaway verification host for the disk/boot foundation design — NOT a
# real target machine, and NOT hosts/mimir/ (see docs/superpowers/specs/
# 2026-08-08-disk-boot-foundation-design.md "Real Install Boundary" for why
# the real host isn't created by this plan). Mirrors hosts/test-vm/'s
# established pattern: nixos-rebuild build-vm normally injects the qemu-vm
# module itself, but nixos-rebuild isn't on PATH in this dev sandbox, so
# `nix build .#nixosConfigurations.test-disko-luks.config.system.build.vm`
# is used instead, which needs that module imported explicitly here.
{ config, pkgs, modulesPath, ... }:
{
  imports = [
    (import ../../modules/nixos/disko-luks-btrfs.nix {
      device = "/dev/vda";
      swapSize = "2G"; # small on purpose — see this file's own header comment
    })
    ../../modules/nixos/boot.nix
    (modulesPath + "/virtualisation/qemu-vm.nix")
  ];

  # Arbitrary but required by NixOS for any system closure to evaluate —
  # doesn't need to track the real nixpkgs channel version for a
  # throwaway VM that's never upgraded in place.
  system.stateVersion = "24.05";
}
