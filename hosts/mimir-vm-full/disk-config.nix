# Same shape as hosts/mimir-vm-rehearsal/disk-config.nix -- device =
# "/dev/vda" for the same manually-launched VM, swapSize "2G" small on
# purpose (rehearsal, not a real hibernate-sized install). Separate file
# from mimir-vm-rehearsal/'s own, not reused directly, so each host's
# nixosConfigurations entry is self-contained and independently
# buildable/removable.
import ../../modules/nixos/disko-luks-btrfs.nix {
  device = "/dev/vda";
  swapSize = "2G";
}
