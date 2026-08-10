# Vendored from lanzaboote's nix/tests/lanzaboote/common/lanzaboote.nix
# (pinned rev 7c9a54a7f87b4539ddbd8bda09a8a5f5f9361aa9, matching this repo's
# flake.lock — see ../systemd-initrd.nix for the full provenance note).
#
# ONE deliberate change from upstream: the `../../fixtures/uefi-keys`
# references below are `../fixtures/uefi-keys` here (one `..` fewer).
# Upstream's tree is nix/tests/{lanzaboote/common/*.nix, fixtures/} — two
# levels from common/ up to the tests/ dir that fixtures/ sits under. This
# vendored copy flattens that one level (no separate "lanzaboote/" wrapper
# dir under secure-boot-test/), so fixtures/ is only one level up from
# common/ here. Content is otherwise unchanged.
#
# `pkiBundle = "/var/lib/lanzaboote-test-fixture"` below is a TEST-ONLY
# path, deliberately distinct from secure-boot.nix's real
# `pkiBundle = "/var/lib/sbctl"` — this test bakes in throwaway/public
# fixture keys (fixtures/uefi-keys/, upstream's own published test PKI, not
# secrets) via systemd-tmpfiles, whereas the real module expects
# `sbctl create-keys` to populate /var/lib/sbctl on the real machine at
# install time. Do not unify these two paths.
{ config, lib, ... }:

let
  pkiBundle = "/var/lib/lanzaboote-test-fixture";
in
{
  imports = [ ./image.nix ];

  options.lanzabooteTest = {
    keyFixture = lib.mkEnableOption "pkiBundle fixture baked into the image" // {
      default = config.virtualisation.useSecureBoot;
    };

    persistentRoot = lib.mkEnableOption "a persistent root filesystem";
  };

  config = {
    systemd.tmpfiles.settings = lib.mkIf config.lanzabooteTest.keyFixture {
      "10-sbctl"."${pkiBundle}".L = {
        argument = "${../fixtures/uefi-keys}";
      };
    };

    boot = {
      loader.timeout = 0;
      loader.efi.canTouchEfiVariables = true;

      lanzaboote = {
        enable = true;
        logLevel = "debug";
        pkiBundle = lib.mkDefault pkiBundle;
      };
    };
  };
}
