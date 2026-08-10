# Vendored, byte-for-byte copy of lanzaboote's own upstream test
# (nix/tests/lanzaboote/systemd-initrd.nix) — this file needed no changes.
# common/lanzaboote.nix and common/image.nix DID need a small path-depth
# adjustment (see the comment at the top of each) because this vendored
# copy is one directory level shallower than upstream's own tree.
#
# Source: https://github.com/nix-community/lanzaboote
# Pinned rev (matches this repo's flake.lock "lanzaboote" input, resolved
# from the "v1.1.0" ref — see flake.nix):
#   7c9a54a7f87b4539ddbd8bda09a8a5f5f9361aa9
# Fetched: 2026-08-10.
#
# WHY this exists / what it does and does NOT prove (Design doc's "Check 1",
# see docs/superpowers/specs/2026-08-10-secure-boot-design.md "Two Checks,
# Not One Combined Test"):
#
# This is upstream's OWN test architecture — a pre-baked systemd-repart disk
# image (see common/image.nix) with UEFI auth-variables written straight
# onto the ESP for auto-enrollment, booted under OVMF with
# virtualisation.useSecureBoot = true. It does NOT go through this repo's
# disko-luks-btrfs.nix (no disko partitioning, no LUKS, no btrfs at all
# here) and does NOT import secure-boot.nix (it sets boot.lanzaboote.*
# itself, via common/lanzaboote.nix, using a test-only pkiBundle fixture
# baked from fixtures/uefi-keys/ instead of a real sbctl-generated
# /var/lib/sbctl). That combination — Secure Boot's signing chain over
# disko's actual LUKS/btrfs layout, in one real boot — is a named, accepted
# gap for this whole plan (see design doc's "Risk profile"), not something
# this test is trying to cover.
#
# What this DOES prove: Secure Boot works together with
# boot.initrd.systemd.enable = true — the exact initrd choice boot.nix
# makes for the LUKS prompt (disko-luks-btrfs-test.nix's own check) — using
# upstream's own proven test machinery, re-run concretely against the
# lanzaboote version actually pinned here rather than trusted secondhand.
# Module composition between disko-luks-btrfs.nix and secure-boot.nix
# (Check 2) is covered separately by hosts/test-secure-boot/.
{
  name = "lanzaboote-systemd-initrd";

  nodes.machine =
    { ... }:
    {
      imports = [ ./common/lanzaboote.nix ];

      boot.initrd.systemd.enable = true;
    };

  testScript =
    { nodes, ... }:
    (import ./common/image-helper.nix { inherit (nodes) machine; })
    + ''
      machine.start()
      assert "Secure Boot: enabled (user)" in machine.succeed("bootctl status")
    '';
}
