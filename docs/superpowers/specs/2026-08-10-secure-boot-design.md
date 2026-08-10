# Secure Boot (lanzaboote) Design

## Goal

Add Secure Boot on top of the already-working, VM-verified disko + LUKS2 +
systemd-boot foundation (`docs/superpowers/specs/2026-08-08-disk-boot-foundation-design.md`),
using `lanzaboote` (`nix-community/lanzaboote`) — signed boot chain with a
self-owned PKI via `sbctl`, per `system-plan.md` §2/§4. Verified in a
throwaway VM, same rigor as the disk/boot plan. Real key generation and UEFI
enrollment stay out of scope — physical hardware only, a separate
explicitly-requested future step.

## Context

`modules/nixos/boot.nix` (existing, unchanged by this plan) gives
`boot.loader.systemd-boot.enable = true` + `boot.initrd.systemd.enable = true`.
Hosts that don't need Secure Boot keep importing that module exactly as
today. lanzaboote **replaces** systemd-boot rather than layering on top of
it — its own docs require `boot.loader.systemd-boot.enable = lib.mkForce
false` alongside `boot.lanzaboote.enable = true` — so this is a genuinely
separate module, not an addition to `boot.nix`.

## Risk profile — lower than the disk/boot plan

The disk/boot plan's core risk was that `luks -> swap -> resumeDevice` had
never been exercised together in any committed example. Secure Boot is
different: lanzaboote's own upstream CI runs a real `nixosTest`
(`nix/tests/lanzaboote/systemd-initrd.nix`) combining Secure Boot with
`boot.initrd.systemd.enable = true` — **the exact initrd choice this repo
already made** for the LUKS prompt in `boot.nix`. That combination is
already proven upstream, not just theoretically compatible. Confirmed via
lanzaboote's real test suite and issue tracker (checked for LUKS2/btrfs-
specific problems — none found; open issues cluster around TPM-bound
unlock via `systemd-cryptenroll`, which this plan does not use).

Given that, a from-scratch Secure Boot test would be redundant risk-wise —
but a test of *our own* module composition (disko + two LUKS containers +
btrfs + lanzaboote together, not lanzaboote in isolation) still has real
value, and is worth doing to the same standard as the disk/boot plan: adapt
lanzaboote's own passing test pattern onto our actual disk layout rather
than writing one from scratch or trusting upstream's isolated test to
stand in for our specific composition.

## Module

```
modules/nixos/secure-boot.nix
```
- Flake input: `lanzaboote = { url = "github:nix-community/lanzaboote/v1.1.0"; inputs.nixpkgs.follows = "nixpkgs"; };`
- Module content (sketch, exact form finalized at implementation time):
  ```nix
  { lib, ... }:
  {
    boot.loader.systemd-boot.enable = lib.mkForce false;
    boot.lanzaboote = {
      enable = true;
      pkiBundle = "/var/lib/sbctl";
    };
  }
  ```
- `pkiBundle = "/var/lib/sbctl"` is lanzaboote's current recommended path
  (not `/etc/secureboot`, which is legacy/migratable). Not parameterized —
  unlike `device`/`swapSize` in `disko-luks-btrfs.nix`, this path isn't
  host-specific, no reason to make it a module argument.
- Requires the `lanzaboote.nixosModules.lanzaboote` module imported
  alongside this one at the flake level (same pattern as `disko.nixosModules.disko`
  in `flake.nix` today).

## Key management (real install only, not this plan's concern to implement)

`sbctl create-keys` writes to `/var/lib/sbctl`, root-only permissions, on
the real machine — never committed to git, analogous to a private CA key.
lanzaboote's own docs don't say this explicitly, but the design (local
keyring, root-only perms, no repo-based example anywhere in their docs)
makes it unambiguous. This plan generates no keys and touches no real
hardware.

## Test Host

```
hosts/test-secure-boot/   # throwaway, mirrors hosts/test-disko-luks/'s pattern
  configuration.nix       # device = "/dev/vda", imports disko-luks-btrfs.nix
                           # + secure-boot.nix (NOT boot.nix — replaced)
```
`hosts/test-disko-luks/` is **not** modified — it stays the clean
"plain systemd-boot, no Secure Boot" reference the disk/boot plan already
verified. A separate host keeps that guarantee intact rather than mutating
it into a Secure-Boot-only config.

## VM Test

New `checks.${system}.secure-boot` (or similar name, finalized at plan time)
in `flake.nix`, adapted from lanzaboote's own
`nix/tests/lanzaboote/systemd-initrd.nix` and its `common/lanzaboote.nix`
fixture-loading helper, applied to `hosts/test-secure-boot/`'s actual disko
layout rather than lanzaboote's own minimal test fixture disk:
- `virtualisation.useSecureBoot = true` (the NixOS test-framework option
  that pre-configures OVMF with Secure Boot variables).
- Test key fixtures enrolled into the VM's `pkiBundle` via
  `systemd.tmpfiles`, mirroring lanzaboote's own fixture pattern (source:
  `nix/tests/fixtures/uefi-keys/` in their repo — reuse their fixtures
  rather than generating new ones, avoids the plan minting its own throwaway
  keys for no reason).
- Assertions: `bootctl status` reports `Secure Boot: enabled (user)` inside
  the booted VM, and (reusing the disk/boot plan's own proven assertions)
  the LUKS/btrfs/swap layout still comes up correctly underneath — this is
  the part that specifically tests *our* composition, not lanzaboote alone.

## Testing (per CLAUDE.md's disk-budget-aware cycle — nothing touches real hardware)

1. `nix flake check --no-build` (fast eval-only, per the disk/boot plan's
   own I1 fix — this repo's `nix flake check` now includes real VM builds,
   `--no-build` is the cheap after-every-edit form).
2. `nix flake check -L` — the real thing: builds and boots the Secure Boot
   VM test, asserts the signed boot chain plus the disk layout underneath.
3. `nix build .#nixosConfigurations.test-secure-boot.config.system.build.vm`
   — manual boot for a closer look if the automated test's output needs
   investigation (same pattern as the disk/boot plan's Task 3).

## Real Install Boundary

Unchanged principle from the disk/boot plan: nothing here runs on
`/dev/sdb`, generates real keys, or enrolls anything in real UEFI firmware.
`hosts/mimir/` still doesn't exist. When the real install eventually
happens, Secure Boot enrollment is a manual, physical-access step
(`sbctl create-keys`, `sbctl enroll-keys`, reboot into firmware setup) —
this plan's deliverable is a VM-proven, ready-to-import module, not a
completed real installation.
