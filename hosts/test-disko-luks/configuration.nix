# Throwaway verification host for the disk/boot foundation design — NOT a
# real target machine, and NOT hosts/mimir/ (see docs/superpowers/specs/
# 2026-08-08-disk-boot-foundation-design.md "Real Install Boundary" for why
# the real host isn't created by this plan). Unlike hosts/test-vm/
# (configuration.nix declares fileSystems."/" and boot.loader.grub.device
# directly, no qemu-vm.nix import — that pattern is NOT mirrored here),
# this host imports virtualisation/qemu-vm.nix explicitly: nixos-rebuild
# build-vm normally injects that module itself, but nixos-rebuild isn't on
# PATH in this dev sandbox, so `nix build
# .#nixosConfigurations.test-disko-luks.config.system.build.vm` is used
# instead, which needs the module imported by hand.
#
# IMPORTANT — what this host actually proves: qemu-vm.nix's
# `virtualisation.useDefaultFilesystems` (on by default) overrides
# fileSystems/swapDevices/boot.initrd.luks.devices entirely for any VM
# built from it, regardless of what disko-luks-btrfs.nix/boot.nix set. So
# booting this host does NOT exercise the real LUKS/btrfs/swap layout at
# all — it only proves the modules evaluate and the closure builds. Real
# functional verification (LUKS unlock, btrfs subvolumes, swap on the
# decrypted mapper device, resume= in cmdline) is `checks.disko-luks-btrfs`
# in flake.nix, which runs disko's own VM test harness against a real
# virtual disk instead of going through qemu-vm.nix's defaults. A
# consequence of the override: `boot.resumeDevice` below is NOT overridden
# by qemu-vm.nix, so this host still boots with
# `resume=/dev/mapper/cryptswap` in its kernel cmdline pointing at a
# device that can never exist under useDefaultFilesystems — a latent
# boot-time device wait if this host is ever booted by hand (plausibly why
# Task 3 Step 3's manual hibernate check hung; see task-3-report.md).
#
# swapSize below is "2G", NOT the real 34G: this host's virtual disk is
# small — `virtualisation.diskSize` for a manually-built VM defaults to
# 1024 (1G, per nixpkgs' qemu-vm.nix), well under the 4096 MiB (4G) disk
# that `checks.disko-luks-btrfs`'s makeDiskoTest hardcodes for the actual
# functional test — and only needs to prove the LUKS+swap+resumeDevice
# mechanism works, not hold a real hibernate image sized for real RAM. Note
# the ~4 GiB ceiling if swapSize is ever raised here: with ESP 1024M + a
# larger swap, cryptroot on either disk shrinks fast. The real
# hosts/mimir/ install (not part of this plan) would use the real 34G on a
# real, much larger disk.
{ modulesPath, ... }:
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
