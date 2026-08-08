# Throwaway verification host for the dev-databases module — NOT a real
# target machine. nixos-rebuild build-vm generates its own actual VM disk/kernel
# boot path at build time and doesn't use these specific values to boot — but nix
# flake check still runs NixOS's standard assertions on the base system regardless
# of build target, which require fileSystems."/" and a bootloader to be declared,
# so they're still needed here. Once the full hosts/ restructuring (disko/LUKS/Secure
# Boot, see system-plan.md §3-4) exists, import dev-databases.nix into the real
# host's configuration.nix instead and delete this directory.
{ config, pkgs, ... }:
{
  imports = [ ../../modules/nixos/dev-databases.nix ];

  fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
  boot.loader.grub.device = "/dev/vda";

  # Arbitrary but required by NixOS for any system closure to evaluate —
  # doesn't need to track the real nixpkgs channel version for a
  # throwaway VM that's never upgraded in place.
  system.stateVersion = "24.05";
}
