# Throwaway verification host for the disk/boot foundation design — NOT a
# real target machine, and NOT hosts/mimir/ (see docs/superpowers/specs/
# 2026-08-08-disk-boot-foundation-design.md "Real Install Boundary" for why
# the real host isn't created by this plan). Mirrors hosts/test-vm/'s
# established pattern: nixos-rebuild build-vm normally injects the qemu-vm
# module itself, but nixos-rebuild isn't on PATH in this dev sandbox, so
# `nix build .#nixosConfigurations.test-disko-luks.config.system.build.vm`
# is used instead, which needs that module imported explicitly here.
#
# swapSize below is "2G", NOT the real 34G: this host's virtual disk
# (Task 3's qcow2/VM disk) is small (8G, per the design doc's Testing
# section) and only needs to prove the LUKS+swap+resumeDevice mechanism
# works — it doesn't need to actually hold a real hibernate image sized
# for real RAM. The real hosts/mimir/ install (not part of this plan)
# would use the real 34G.
{ config, pkgs, modulesPath, ... }:
{
  imports = [
    (import ../../modules/nixos/disko-luks-btrfs.nix {
      device = "/dev/vda";
      swapSize = "2G"; # small on purpose — see this file's header comment
    })
    ../../modules/nixos/boot.nix
    (modulesPath + "/virtualisation/qemu-vm.nix")
  ];

  # Arbitrary but required by NixOS for any system closure to evaluate —
  # doesn't need to track the real nixpkgs channel version for a
  # throwaway VM that's never upgraded in place.
  system.stateVersion = "24.05";
}
