# Disk layout shared by every machine (GPT: ESP + LUKS swap + LUKS btrfs,
# modules/nixos/disko-luks-btrfs.nix). Used two ways:
#
# 1. bin/install-host runs disko on this file and passes the real values
#    on the command line: `--argstr device /dev/nvme0n1` (chosen on the
#    machine, never guessed here) and `--argstr swapSize <RAM+2G>` (swap
#    must hold all of RAM for hibernate, and machines differ -- a fixed
#    34G wasted 34 of 60 GB in the VM rehearsal, 2026-10-06).
# 2. hosts/common.nix imports it as a NixOS module. Module args contain
#    neither value, so the defaults apply -- harmless: disko's generated
#    fileSystems/LUKS entries point at /dev/disk/by-partlabel/disk-main-*,
#    not at the device or sizes. The device default is a non-existent path
#    so running disko without --argstr fails loudly instead of wiping a disk.
{ device ? "/dev/disk/by-id/PASS-DEVICE-VIA-ARGSTR", swapSize ? "34G", ... }:
import ../modules/nixos/disko-luks-btrfs.nix {
  inherit device swapSize;
}
