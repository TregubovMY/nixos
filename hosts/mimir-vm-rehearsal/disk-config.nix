# Split out from configuration.nix (not left inline) so `nix run
# github:nix-community/disko -- --mode disko ./hosts/mimir-vm-rehearsal/disk-config.nix`
# has a real file to point at, matching hosts/mimir/disk-config.nix's own
# shape. swapSize "2G" small on purpose, matches hosts/test-secure-boot/
# and hosts/test-disko-luks/ -- this is a rehearsal of the mechanism
# (LUKS+btrfs+Secure Boot boot chain), not a real hibernate-sized
# install. The real hosts/mimir/ install uses the real 34G on the real,
# much larger /dev/sdb.
import ../../modules/nixos/disko-luks-btrfs.nix {
  device = "/dev/vda";
  swapSize = "2G";
}
