# Throwaway verification host for the Secure Boot design — NOT a real
# target machine, and NOT hosts/mimir/. Mirrors hosts/test-disko-luks/'s
# pattern (device = "/dev/vda", small swapSize, explicit qemu-vm.nix
# import since nixos-rebuild isn't on PATH in this dev sandbox) but swaps
# secure-boot.nix in for boot.nix.
#
# IMPORTANT — narrower purpose than hosts/test-disko-luks/: this host
# exists ONLY to prove disko-luks-btrfs.nix and secure-boot.nix evaluate
# together without option conflicts (nix flake check --no-build — Design
# doc's "Check 2"). It is NOT used to verify Secure Boot itself works —
# that's a separate, vendored copy of lanzaboote's own upstream test (see
# Task 3), which uses a completely different image-building mechanism
# (systemd-repart, not disko) and doesn't touch this host at all. Booting
# this host manually (Step 3 below) proves the closure builds, nothing
# about Secure Boot or the disk layout being real — same
# virtualisation.useDefaultFilesystems caveat hosts/test-disko-luks/
# already documents.
{ modulesPath, ... }:
{
  imports = [
    (import ../../modules/nixos/disko-luks-btrfs.nix {
      device = "/dev/vda";
      swapSize = "2G"; # small on purpose, matches hosts/test-disko-luks/ —
        # this host's virtual disk only needs to prove module composition,
        # not hold a real hibernate image.
    })
    ../../modules/nixos/secure-boot.nix
    (modulesPath + "/virtualisation/qemu-vm.nix")
  ];

  system.stateVersion = "24.05";
}
