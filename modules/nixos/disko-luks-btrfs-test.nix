# Plain (non-parameterized) disko config used ONLY by disko's own
# makeDiskoTest VM test (see flake.nix's `checks.${system}.disko-luks-btrfs`
# and docs/superpowers/plans/2026-08-08-disk-boot-foundation.md, Task 3, and
# docs/superpowers/specs/2026-08-08-disk-boot-foundation-design.md).
#
# NOT consumed by hosts/test-disko-luks/configuration.nix, which imports
# the parameterized modules/nixos/disko-luks-btrfs.nix directly with a
# real interactive LUKS passphrase prompt, matching an actual install.
# This file exists, and differs from that real path, for two contract
# reasons discovered by reading disko's pinned source
# (nix-community/disko, rev ff8702b4de27f72b4c78573dfb89ec74e36abdf1 per
# flake.lock, files lib/tests.nix and lib/types/luks.nix):
#
# 1. `makeDiskoTest`'s `disko-config` argument (lib/tests.nix) does
#    `importedDiskoConfig = import disko-config;` then, only if the
#    result is a function, calls it as `importedDiskoConfig { inherit lib; }`
#    — i.e. it can only supply `lib`, never our module's own required
#    `device`/`swapSize` args. So this file pins those to the test VM's
#    values (device = "/dev/vda", the disk QEMU always gives a NixOS VM
#    test's single-disk "machine" node; swapSize = "2G" to match
#    hosts/test-disko-luks/configuration.nix, since this is meant to
#    exercise the exact same layout that host uses) and hands
#    makeDiskoTest a `{ lib, ... }: {...}` function it CAN call.
#
# 2. makeDiskoTest's automated `machine.succeed(...)` formatting step runs
#    with no TTY, so it cannot answer disko's interactive LUKS passphrase
#    prompt (disko-luks-btrfs.nix deliberately leaves both LUKS containers
#    on that interactive default for real installs). Checked
#    lib/types/luks.nix: interactive entry is gated on `config.askPassword`,
#    which is true whenever neither `settings.keyFile` nor `passwordFile`
#    is set; there's also an `IN_DISKO_TEST` non-interactive escape hatch
#    in that same file, but grepping the whole pinned checkout shows it is
#    only ever exported by disko's lib/make-disk-image.nix path, NOT by
#    makeDiskoTest — so it does not help here. Instead, both LUKS
#    containers get `settings.keyFile = "/tmp/secret.key"` here, which
#    makeDiskoTest's own harness populates automatically: at format time
#    via `machine.succeed("echo -n 'secretsecret' > /tmp/secret.key")`,
#    and for the post-install reboot via `boot.initrd.secrets` (used
#    because boot.nix sets `boot.initrd.systemd.enable = true`) — the same
#    mechanism disko's own tests/luks-btrfs-raid.nix example test uses.
{ lib, ... }:
let
  base = import ./disko-luks-btrfs.nix { device = "/dev/vda"; swapSize = "2G"; };
  # Applied identically to both LUKS containers below via recursiveUpdate,
  # which merges nested attrsets rather than replacing them wholesale —
  # so this only adds `keyFile` alongside each container's existing
  # `settings.allowDiscards = true`, and leaves the swap/btrfs `content`
  # nested one level deeper untouched.
  testKeyFile = {
    settings.keyFile = "/tmp/secret.key";
  };
in
lib.recursiveUpdate base {
  disko.devices.disk.main.content.partitions = {
    cryptswap.content = testKeyFile;
    cryptroot.content = testKeyFile;
  };
}
