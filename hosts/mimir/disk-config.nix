# Real disk-layout wrapper for mimir — device and swapSize are not new
# decisions here, they're already documented as the intended real values
# in disko-luks-btrfs.nix's own header comment. This file just gives that
# documented intent a real caller. NOT registered in flake.nix yet (see
# docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md) — needs
# a real hardware-configuration.nix first, which needs mimir itself.
import ../../modules/nixos/disko-luks-btrfs.nix {
  device = "/dev/sdb";
  swapSize = "34G";
}
