# Secure Boot via lanzaboote — a separate module from boot.nix, NOT
# imported alongside it: hosts that want Secure Boot import this module
# INSTEAD OF boot.nix (see hosts/test-secure-boot/), because lanzaboote
# REPLACES systemd-boot rather than layering on top of it (its own docs
# require boot.loader.systemd-boot.enable = lib.mkForce false alongside
# boot.lanzaboote.enable = true). Hosts that don't need Secure Boot keep
# importing plain boot.nix unchanged.
#
# Because this module replaces boot.nix entirely on the hosts that use it,
# it must carry boot.nix's OTHER settings itself too, not just the
# loader swap — otherwise a Secure Boot host silently loses them. Final
# whole-branch review (2026-08-10) caught that this file originally only
# force-disabled systemd-boot and enabled lanzaboote, leaving
# boot.initrd.systemd.enable unset here. That happened to still evaluate
# to `true` on test-secure-boot only because current nixpkgs defaults it
# to true (nixos/modules/system/boot/systemd/initrd.nix) — an upstream
# default that has changed before and could change again, not something
# this repo should rely on silently. boot.initrd.systemd.enable is
# load-bearing here: it's what disko-luks-btrfs.nix's LUKS-prompt design
# assumes (see that file), and it's the exact initrd choice this repo
# claims (in README.md/system-plan.md/the vendored test's own header) that
# Check 1 (docs/superpowers/specs/2026-08-10-secure-boot-design.md) proves
# Secure Boot works with — a claim that was only true by accident before
# this fix.
{ lib, pkgs, ... }:
{
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.initrd.systemd.enable = true;
  # Inert for lanzaboote today (it installs the signed bootloader itself
  # via boot.loader.external rather than calling bootctl/efibootmgr, so
  # nothing reads this on a lanzaboote host — checked against lanzaboote's
  # own source, rust/tool/systemd/src/install.rs) — kept anyway for parity
  # with boot.nix and with upstream lanzaboote's own documented config
  # shape, in case that changes.
  boot.loader.efi.canTouchEfiVariables = true;
  boot.lanzaboote = {
    enable = true;
    # /var/lib/sbctl is lanzaboote's current recommended pkiBundle path
    # (not /etc/secureboot, which is the legacy/migratable location) — see
    # https://github.com/nix-community/lanzaboote/blob/master/docs/getting-started/prepare-your-system.md
    # Real key generation (sbctl create-keys) happens on the real machine
    # only, at real-install time — this repo never generates or commits
    # Secure Boot keys; they're the machine's root of trust, root-only
    # permissions, analogous to a private CA key.
    pkiBundle = "/var/lib/sbctl";
  };
  environment.systemPackages = [ pkgs.sbctl ]; # for the real-install `sbctl
    # create-keys`/`sbctl enroll-keys` step — matches upstream's own
    # getting-started config, and system-plan.md §5.1's base-package list
    # already names sbctl (no packages module exists yet to actually
    # provide it otherwise)
}
