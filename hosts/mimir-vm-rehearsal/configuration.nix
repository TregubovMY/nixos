# Manual-install rehearsal host — NOT hosts/mimir/ (no real
# hardware-configuration.nix, no secrets.nix/desktop-apps.nix — minimal on
# purpose, see docs/superpowers/plans/tingly-doodling-phoenix.md), and NOT
# hosts/test-secure-boot/ even though it reuses that host's exact
# disko-luks-btrfs.nix + secure-boot.nix combo (device = "/dev/vda"):
# deliberately does NOT import qemu-vm.nix. That module makes
# hosts/test-secure-boot/ fast to eval/build automatically, but
# virtualisation.useDefaultFilesystems (on by default) silently overrides
# the real fileSystems/swapDevices/LUKS layout for any VM built through
# it — so booting that host never actually exercises real LUKS unlock or
# btrfs mount, only proves the modules evaluate together.
#
# This host is meant to be installed for real instead: boot a NixOS
# installer ISO in a manually-launched VM (virt-manager, synthetic qcow2
# disk presented as /dev/vda), then run the real
# `disko --mode disko` + `nixos-install --flake .#mimir-vm-rehearsal`
# sequence from system-plan.md §8, entering the LUKS passphrase and
# running `sbctl create-keys`/`enroll-keys` interactively at the VM's own
# console — the first genuine (not just eval) test of the
# disko+LUKS+btrfs+lanzaboote-Secure-Boot combination the design docs
# (docs/superpowers/specs/2026-08-10-secure-boot-design.md "Risk profile")
# flag as never tested together, before trusting it to the real
# hosts/mimir/ install on /dev/sdb.
{ ... }:
{
  imports = [
    ./disk-config.nix
    ../../modules/nixos/secure-boot.nix
  ];

  system.stateVersion = "24.05";
}
