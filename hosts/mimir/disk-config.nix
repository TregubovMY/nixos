# Real disk layout for mimir. Used two ways:
#
# 1. bin/mimir-install runs disko on this file directly and passes the
#    real disk on the command line (`--argstr device /dev/nvme0n1`), so
#    the device is chosen on the actual machine at install time instead of
#    being guessed here. (Was hardcoded to /dev/sdb from the skeleton
#    design doc; that guess can only be right by luck on unseen hardware.)
# 2. hosts/mimir/configuration.nix imports it as a NixOS module. Module
#    args don't contain `device`, so the default below applies -- and it
#    doesn't matter: disko-generated fileSystems/LUKS entries point at
#    /dev/disk/by-partlabel/disk-main-*, never at the raw device path. The
#    default is a deliberately non-existent path so that running disko
#    without --argstr fails loudly instead of wiping some real disk.
#
# swapSize 34G: RAM + headroom for hibernate (resumeDevice, see
# disko-luks-btrfs.nix).
{ device ? "/dev/disk/by-id/PASS-DEVICE-VIA-ARGSTR", ... }:
import ../../modules/nixos/disko-luks-btrfs.nix {
  inherit device;
  swapSize = "34G";
}
