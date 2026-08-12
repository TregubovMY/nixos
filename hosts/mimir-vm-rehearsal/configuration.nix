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

  # Discovered live during the rehearsal run, not anticipated when this
  # host was written: with no hardware-configuration.nix and no
  # qemu-vm.nix (deliberately, see header comment), the installed
  # system's own initrd has none of nixpkgs' default
  # boot.initrd.includeDefaultModules fallback list (SATA/PATA/NVMe/USB
  # -- checked nixos/modules/system/boot/kernel.nix at this repo's
  # pinned nixpkgs rev: it genuinely does not include virtio anything,
  # that list predates VMs being common and is kept only for backwards
  # compat). Without a virtio block driver available in the initrd, the
  # kernel can never see /dev/vda at all during early boot -- the LUKS
  # partitions' by-partlabel symlinks never appear, hence
  # "Timed out waiting for device ...cryptroot" and emergency mode. A
  # real hardware-configuration.nix (nixos-generate-config, run inside
  # this exact VM) would have detected and declared this automatically
  # -- this is the minimal manual equivalent for a throwaway rehearsal
  # host.
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_scsi" ];

  # Rehearsal-only convenience -- NOT how hosts/mimir/ should ever be
  # configured (that needs a real user + real secrets, see
  # system-plan.md §7). nixos-install left root locked (no password set
  # interactively during the unattended-ish install run), which blocks
  # even emergency-mode login. A known, fixed password is fine here:
  # this is a throwaway synthetic disk, not a real machine.
  users.users.root.initialPassword = "root";

  system.stateVersion = "24.05";
}
