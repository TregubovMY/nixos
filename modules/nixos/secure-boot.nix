# Secure Boot via lanzaboote — a separate module from boot.nix, not an
# addition to it: lanzaboote REPLACES systemd-boot rather than layering on
# top (its own docs require boot.loader.systemd-boot.enable = lib.mkForce
# false alongside boot.lanzaboote.enable = true). Hosts that don't need
# Secure Boot keep importing plain boot.nix unchanged.
#
# Risk note (see docs/superpowers/specs/2026-08-10-secure-boot-design.md
# "Risk profile" for the full writeup): lanzaboote's own upstream CI
# already runs a real nixosTest combining Secure Boot with
# boot.initrd.systemd.enable = true — the exact initrd choice boot.nix
# already makes for the LUKS prompt (see disko-luks-btrfs.nix). That
# combination is proven upstream, not just theoretically compatible.
{ lib, ... }:
{
  boot.loader.systemd-boot.enable = lib.mkForce false;
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
}
