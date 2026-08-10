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

**Revised after checking lanzaboote's actual test source (not just its
existence).** The plan initially assumed lanzaboote's own test could be
straightforwardly adapted onto our real disko/LUKS disk layout. Reading
`nix/tests/lanzaboote/common/image.nix` shows that isn't true: lanzaboote's
test builds a completely different kind of disk image — a pre-baked
`systemd-repart` image (`modulesPath + "/image/repart.nix"`, separate ESP/
nix-store/root partitions, UEFI auth-variable files written straight onto
the ESP for auto-enrollment) — not a disk partitioned by any tool at
runtime. `checks.disko-luks-btrfs` (the disk/boot plan's own test) does the
opposite: it runs disko's *real* partitioning process, LUKS format
included, against a blank virtual disk inside a booting VM. These are two
incompatible test-construction mechanisms, not two pieces of one test that
compose by copying assertions across.

Combining them for real — Secure Boot's signing chain over disko's actual
LUKS/btrfs layout, verified together in one VM boot — is a genuine
integration project (would need `virtualisation.useSecureBoot`/`OVMF`
layered onto `makeDiskoTest`'s VM, plus a real answer for UEFI key
enrollment onto an ESP that disko created rather than lanzaboote's own
repart step). Discussed with the human partner and deliberately **not**
attempted in this plan — the risk/effort would rival or exceed the disk/boot
plan's own hardest task for a benefit that's mostly already covered by
lanzaboote's own upstream CI. Instead: two separate, narrower checks (below).

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
it into a Secure-Boot-only config. This host's job is narrower than
originally planned (see below): it exists to prove `disko-luks-btrfs.nix`
and `secure-boot.nix` *evaluate together* without option conflicts (e.g. no
double-definition of `boot.loader.*` triggering a NixOS assertion) — not to
be booted through a real Secure-Boot-verified chain.

## Two Checks, Not One Combined Test

**Check 1 — Secure Boot works with our exact initrd choice.** Reuse
lanzaboote's own `nix/tests/lanzaboote/systemd-initrd.nix` test close to
as-is (their repart-image architecture, not integrated with disko) as
`checks.${system}.secure-boot-signing` in `flake.nix`. This is upstream's
own proof that Secure Boot plus `boot.initrd.systemd.enable = true` (this
repo's exact `boot.nix` choice) works, re-run concretely against the
`lanzaboote` version actually pinned in this repo's `flake.lock` rather
than trusted secondhand. Assertion (unchanged from upstream):
`"Secure Boot: enabled (user)" in machine.succeed("bootctl status")`.
Does **not** exercise disko/LUKS/btrfs — that's Check 2's job, and neither
check claims to cover what only a combined test could.

**Check 2 — module composition doesn't conflict.** `nix flake check
--no-build` evaluating `hosts/test-secure-boot/`'s `nixosConfigurations`
entry (`disko-luks-btrfs.nix` + `secure-boot.nix` together) is enough to
catch the most likely real failure mode — both modules touching
`boot.loader`/`boot.initrd` options in incompatible ways — without needing
a real VM boot. Cheap, fast, run on every edit.

**What neither check proves, named explicitly rather than implied:** that
Secure Boot's signing chain and disko's actual LUKS/btrfs/swap layout work
together in one real boot. That gap is accepted for this plan (see Risk
profile above) and documented as a known limitation, same honesty standard
as the disk/boot plan's own hibernate-cycle gap.

## Testing (per CLAUDE.md's disk-budget-aware cycle — nothing touches real hardware)

1. `nix flake check --no-build` — Check 2 (module composition), and the
   routine fast command for every edit generally.
2. `nix flake check -L` — additionally builds and boots Check 1 (Secure
   Boot signing chain via lanzaboote's own test architecture).
3. `nix build .#nixosConfigurations.test-secure-boot.config.system.build.vm`
   — manual boot of the composed-but-not-Secure-Boot-tested host, useful
   only for confirming the closure itself builds/boots at all (same
   `virtualisation.useDefaultFilesystems` caveat `hosts/test-disko-luks/`
   already documents — this host doesn't exercise its own disk layout
   either when booted this way).

## Real Install Boundary

Unchanged principle from the disk/boot plan: nothing here runs on
`/dev/sdb`, generates real keys, or enrolls anything in real UEFI firmware.
`hosts/mimir/` still doesn't exist. When the real install eventually
happens, Secure Boot enrollment is a manual, physical-access step
(`sbctl create-keys`, `sbctl enroll-keys`, reboot into firmware setup) —
this plan's deliverable is a VM-proven, ready-to-import module, not a
completed real installation.
