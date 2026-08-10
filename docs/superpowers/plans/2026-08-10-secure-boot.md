# Secure Boot (lanzaboote) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reusable `modules/nixos/secure-boot.nix` (lanzaboote) on top of the already-working disko/LUKS/systemd-boot foundation, verified by two narrower checks rather than one combined test (see the design doc for why a full combined test was rejected). Full rationale: `docs/superpowers/specs/2026-08-10-secure-boot-design.md`.

**Architecture:** `modules/nixos/secure-boot.nix` force-disables `boot.loader.systemd-boot.enable` and enables `boot.lanzaboote`, imported instead of (not alongside) `modules/nixos/boot.nix` on hosts that want Secure Boot. A throwaway `hosts/test-secure-boot/` proves this module composes cleanly with `disko-luks-btrfs.nix` (eval-only). A separate, vendored copy of lanzaboote's own upstream test proves Secure Boot itself works with this repo's exact `boot.initrd.systemd.enable = true` choice. Neither check proves the two work together in one real boot — that gap is a named, accepted limitation, not silently implied to be covered.

**Tech Stack:** `lanzaboote` (new flake input, `github:nix-community/lanzaboote/v1.1.0`), `sbctl` (already in nixpkgs), lanzaboote's own `nixosTest`-based signing-chain test (vendored, not live-referenced into the flake input).

## Global Constraints

- `hosts/test-disko-luks/` (from the disk/boot foundation plan) is **not modified** — it stays the clean "plain systemd-boot, no Secure Boot" reference that plan already verified.
- No real key generation (`sbctl create-keys`), no real UEFI enrollment, nothing touches `/dev/sdb` or any real hardware. `hosts/mimir/` still does not exist and is not created by this plan.
- `pkiBundle = "/var/lib/sbctl"` in the real module is not parameterized (not host-specific, unlike `device`/`swapSize` in `disko-luks-btrfs.nix`).
- Disk-budget check (per `CLAUDE.md`) before Task 3's heavy build: if projected free space would drop under ~5GB, `nix-collect-garbage -d` first.
- `nixos-rebuild` is not on PATH in this dev sandbox — use `nix build .#nixosConfigurations.<host>.config.system.build.<target>` instead, per established precedent from the disk/boot foundation plan.
- This sandbox's `install.determinate.systems` substituter is unreachable — every missing `.narinfo` lookup times out at 300s before falling back to `cache.nixos.org`. Always pass `--option substituters "https://cache.nixos.org/" --option extra-substituters ""` on `nix build`/`nix flake check` commands (established fix, used repeatedly in the disk/boot foundation plan).
- Every non-trivial `.nix` file gets WHY-comments per `CLAUDE.md`.
- Verify claims against real sources at implementation time — this plan cites specific lanzaboote source files/versions; if the pinned version in `flake.lock` behaves differently once actually fetched, trust what you observe and note the discrepancy rather than forcing the plan's assumption.

---

## Task 1: lanzaboote flake input + the reusable module

**Files:**
- Modify: `flake.nix`
- Create: `modules/nixos/secure-boot.nix`

**Interfaces:**
- Produces: `modules/nixos/secure-boot.nix` is a plain NixOS module (no custom arguments, unlike `disko-luks-btrfs.nix`) — reference it directly by path in `imports`. Requires `lanzaboote.nixosModules.lanzaboote` also present in the consuming `nixosSystem`'s `modules` list (same pattern `disko.nixosModules.disko` already uses for `nixosConfigurations.test-disko-luks`).
- Consumes (Task 2): imported by `hosts/test-secure-boot/configuration.nix` instead of `modules/nixos/boot.nix`.

- [ ] **Step 1: Add the `lanzaboote` flake input**

Edit `flake.nix` — add the input, thread it through `outputs`, and register a new throwaway host. Current `flake.nix` (reproduced here so the diff is unambiguous — this task only adds the `lanzaboote` input, threads it through `outputs`, and nothing else; `nixosConfigurations.test-secure-boot` is Task 2's job, don't add it yet):

```nix
inputs.lanzaboote = {
  url = "github:nix-community/lanzaboote/v1.1.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Add `lanzaboote` to the `outputs` function signature: `outputs = { self, nixpkgs, disko, lanzaboote, ... }:`.

Update the top-of-file `description` and header comment to mention Secure Boot is now part of what's scoped (follow the existing comment's style — see how it already lists "agent-sandbox package + dev-databases test-vm + disk/boot foundation").

- [ ] **Step 2: Write `modules/nixos/secure-boot.nix`**

```nix
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
```

- [ ] **Step 3: Syntax-check**

Run: `nix-instantiate --parse modules/nixos/secure-boot.nix flake.nix`
Expected: no errors (syntax only — Task 2's `nix flake check --no-build` is the real eval test for this module composing correctly).

- [ ] **Step 4: Commit**

```bash
git add flake.nix modules/nixos/secure-boot.nix
git commit -m "Add lanzaboote flake input + secure-boot.nix module"
```

---

## Task 2: Throwaway host + module-composition check (Design doc's "Check 2")

**Files:**
- Create: `hosts/test-secure-boot/configuration.nix`
- Modify: `flake.nix` (register `nixosConfigurations.test-secure-boot`)

**Interfaces:**
- Consumes: `modules/nixos/disko-luks-btrfs.nix` (from the disk/boot foundation plan — parameterized, `{ device, swapSize ? "34G" }`), `modules/nixos/secure-boot.nix` (Task 1), `lanzaboote.nixosModules.lanzaboote` (Task 1's flake input).

- [ ] **Step 1: Write `hosts/test-secure-boot/configuration.nix`**

```nix
# Throwaway verification host for the Secure Boot design — NOT a real
# target machine, and NOT hosts/mimir/. Mirrors hosts/test-disko-luks/'s
# pattern (device = "/dev/vda", small swapSize, explicit qemu-vm.nix
# import since nixos-rebuild isn't on PATH in this dev sandbox) but swaps
# secure-boot.nix in for boot.nix.
#
# IMPORTANT — narrower purpose than hosts/test-disko-luks/: this host
# exists ONLY to prove disko-luks-btrfs.nix and secure-boot.nix evaluate
# together without option conflicts (nix flake check --no-build — Design
# doc's "Check 2"). It is NOT used to verify Secure Boot itself works —
# that's a separate, vendored copy of lanzaboote's own upstream test (see
# Task 3), which uses a completely different image-building mechanism
# (systemd-repart, not disko) and doesn't touch this host at all. Booting
# this host manually (Step 3 below) proves the closure builds, nothing
# about Secure Boot or the disk layout being real — same
# virtualisation.useDefaultFilesystems caveat hosts/test-disko-luks/
# already documents.
{ modulesPath, ... }:
{
  imports = [
    (import ../../modules/nixos/disko-luks-btrfs.nix {
      device = "/dev/vda";
      swapSize = "2G"; # small on purpose, matches hosts/test-disko-luks/ —
        # this host's virtual disk only needs to prove module composition,
        # not hold a real hibernate image.
    })
    ../../modules/nixos/secure-boot.nix
    (modulesPath + "/virtualisation/qemu-vm.nix")
  ];

  system.stateVersion = "24.05";
}
```

- [ ] **Step 2: Register `nixosConfigurations.test-secure-boot` in `flake.nix`**

Add, alongside the existing `nixosConfigurations.test-disko-luks` block:

```nix
# Throwaway verification host for the Secure Boot design — see
# docs/superpowers/specs/2026-08-10-secure-boot-design.md. Proves module
# composition only (Check 2) — NOT a Secure-Boot-verified boot chain, see
# hosts/test-secure-boot/configuration.nix's own header comment.
nixosConfigurations.test-secure-boot = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    disko.nixosModules.disko
    lanzaboote.nixosModules.lanzaboote
    ./hosts/test-secure-boot/configuration.nix
  ];
};
```

- [ ] **Step 3: Disk-budget check**

Run: `df -h /`. GC first (`nix-collect-garbage -d`) if projected free space after this task's build would drop under ~5GB.

- [ ] **Step 4: Run the module-composition check**

Run: `nix flake check --no-build --option substituters "https://cache.nixos.org/" --option extra-substituters ""`
Expected: passes cleanly, including `nixosConfigurations.test-secure-boot` evaluating without error. This is the actual deliverable of this task — a real failure here (e.g. a `boot.loader`/`boot.initrd` option set two conflicting ways by `disko-luks-btrfs.nix` and `secure-boot.nix`) is a genuine finding, not a plan bug to work around; investigate and, if it's a real incompatibility, report it rather than silently patching around it.

- [ ] **Step 5: Optional manual boot (dry-build equivalent)**

Run: `nix build .#nixosConfigurations.test-secure-boot.config.system.build.toplevel --dry-run --option substituters "https://cache.nixos.org/" --option extra-substituters ""`
Expected: lists derivations that would build, no errors.

- [ ] **Step 6: Commit**

```bash
git add hosts/test-secure-boot/configuration.nix flake.nix
git commit -m "Add throwaway test-secure-boot host for module-composition check"
```

---

## Task 3: Vendor lanzaboote's own signing-chain test (Design doc's "Check 1")

**Files:**
- Create: `modules/nixos/secure-boot-test/` (a small directory of vendored files — see Step 1)
- Modify: `flake.nix` (add `checks.${system}.secure-boot-signing`)

**Interfaces:**
- Consumes: `lanzaboote` flake input (Task 1) — its own test source, fetched fresh in this task (don't assume Task 1's summary of it is complete; read the real files).

This is the task with real research risk, similar in spirit to the disk/boot foundation plan's Task 3 — the brief gives you real starting references, not guaranteed-final code.

- [ ] **Step 1: Read lanzaboote's actual test source before writing anything**

Fetch and read these files from the pinned `lanzaboote` rev (`v1.1.0` — confirm this still matches what Task 1's `flake.lock` actually resolved to; if the lock resolved a different commit, use that one instead):
- `https://raw.githubusercontent.com/nix-community/lanzaboote/v1.1.0/nix/tests/lanzaboote/systemd-initrd.nix` — the actual test (a `{ name, nodes.machine, testScript }` attrset, NOT yet a `pkgs.testers.nixosTest`/`nixosTest` call).
- `https://raw.githubusercontent.com/nix-community/lanzaboote/v1.1.0/nix/tests/lanzaboote/common/lanzaboote.nix` — shared fixture-loading module it imports (sets `boot.lanzaboote.enable`, bakes `../../fixtures/uefi-keys` into a *test-only* `pkiBundle` at `/var/lib/lanzaboote-test-fixture` via `systemd.tmpfiles.settings.*.L.argument` — note this is a different, test-only `pkiBundle` path from `secure-boot.nix`'s real `/var/lib/sbctl`, deliberately not the same, don't unify them).
- `https://raw.githubusercontent.com/nix-community/lanzaboote/v1.1.0/nix/tests/lanzaboote/common/image.nix` — the systemd-repart image-building machinery (`modulesPath + "/image/repart.nix"`, ESP/nix-store/root partitions, `virtualisation.useSecureBoot = true`, `efi.OVMF = pkgs.OVMFFull.fd`, UEFI auth-variable files written onto the ESP for auto-enrollment via `sbctl enroll-keys --yes-this-might-brick-my-machine`). This is genuinely complex — read it fully before deciding how much to vendor vs. reference live.
- **The wrapper mechanism is confirmed** (traced through `flake.nix` → root `default.nix` → `nix/tests/default.nix` at `v1.1.0`):
  ```nix
  pkgs.testers.runNixOSTest {
    imports = [ ./lanzaboote/systemd-initrd.nix ];
    globalTimeout = 5 * 60;
    extraBaseModules = {
      imports = [ lanzabooteFlake.nixosModules.lanzaboote ]; # their own module — supplies the
        # lanzaboote NixOS module the raw test file assumes is already present
        # (the test file itself only sets boot.lanzaboote.* options, it doesn't
        # import the module)
    };
  }
  ```
  Re-verify this against the actual pinned rev when you fetch `nix/tests/default.nix` yourself (URL:
  `https://raw.githubusercontent.com/nix-community/lanzaboote/v1.1.0/nix/tests/default.nix`)
  — this plan's confirmation is from `v1.1.0` specifically; if `flake.lock` resolved a different
  commit, confirm the wrapper still matches before relying on it.

- [ ] **Step 2: Decide vendor vs. live-reference, and write the files**

Recommended default: **vendor** (copy) the test content into this repo under `modules/nixos/secure-boot-test/` rather than referencing `${lanzaboote}/nix/tests/lanzaboote/...` live paths — the disk/boot foundation plan's equivalent decision (`disko-luks-btrfs-test.nix`, a local wrapper file) favored explicitness and stability over live-referencing another flake's internal file layout, which could shift between lanzaboote versions with no warning. If live-referencing turns out clearly simpler and you have a good reason to prefer it, that's a judgment call you're equipped to make — note the reasoning in your report either way.

Whichever approach: the resulting test should end up equivalent to lanzaboote's own `systemd-initrd.nix` test — Secure Boot enabled, `boot.initrd.systemd.enable = true` set explicitly (matching `boot.nix`'s real choice, even though this test's image-building path doesn't go through `boot.nix` itself), asserting `"Secure Boot: enabled (user)" in machine.succeed("bootctl status")`. Add a WHY-comment explaining this test does NOT exercise `disko-luks-btrfs.nix`/`secure-boot.nix` — it's upstream's own architecture confirming Secure Boot plus our initrd choice, re-run against our pinned lanzaboote version, not a test of our modules' composition (that's Task 2's job).

- [ ] **Step 3: Wire it into `flake.nix`**

Add, using the confirmed wrapper shape from Step 1 (`pkgs.testers.runNixOSTest`, not `disko.lib.testLib.makeDiskoTest` — different upstream, different helper):

```nix
checks.${system} = {
  disko-luks-btrfs = disko.lib.testLib.makeDiskoTest { /* unchanged, from the disk/boot foundation plan */ };

  # Confirms Secure Boot works with this repo's exact boot.initrd.systemd.enable
  # = true choice, via lanzaboote's own upstream test architecture (vendored,
  # see modules/nixos/secure-boot-test/). Does NOT exercise disko-luks-btrfs.nix
  # or secure-boot.nix — see docs/superpowers/specs/2026-08-10-secure-boot-design.md
  # "Two Checks, Not One Combined Test".
  secure-boot-signing = pkgs.testers.runNixOSTest {
    imports = [ ./modules/nixos/secure-boot-test/systemd-initrd.nix ]; # or wherever Step 2 landed it
    globalTimeout = 5 * 60;
    extraBaseModules = {
      imports = [ lanzaboote.nixosModules.lanzaboote ];
    };
  };
};
```

Adjust the exact import path to match whatever Step 2 actually produced.

- [ ] **Step 4: Run it**

Disk-budget check first (`df -h /`, GC if needed). Then:
```bash
nix flake check -L --option substituters "https://cache.nixos.org/" --option extra-substituters ""
```
Run in the foreground and block until it finishes — do not background this and end your turn waiting for a notification, that mechanism doesn't exist for subagents (this has bitten multiple agents across the disk/boot foundation plan; don't repeat it). Real VM build+boot, expect it to take a while (20-30+ min precedent in this sandbox is normal, not stuck).

Expected: `checks.${system}.secure-boot-signing` passes — `bootctl status` reports `Secure Boot: enabled (user)` inside the booted VM. If it fails, this is a real, worth-investigating finding (not a plan bug to route around) — could mean the pinned lanzaboote version's test infrastructure shifted, or a genuine incompatibility; investigate what actually happened before reporting status.

- [ ] **Step 5: Cleanup**

Remove any stray `result`/`nixos.qcow2` build byproducts (check `.gitignore` already covers these from the disk/boot foundation plan — it should).

- [ ] **Step 6: Commit**

```bash
git add flake.nix modules/nixos/secure-boot-test/
git commit -m "Add vendored lanzaboote signing-chain test (Secure Boot + systemd-initrd)"
```

---

## Task 4: Documentation

**Files:**
- Modify: `README.md`
- Modify: `system-plan.md` (§4's `lanzaboote` bullet, currently "включаем отдельным модулем (пока не сделано)")

**Interfaces:** none — documentation only.

- [ ] **Step 1: Update `system-plan.md` §4**

Find the current `lanzaboote` bullet in §4 (ends with "...действий при каждом обновлении системы."). Replace "пока не сделано" with a description of what was actually built: `modules/nixos/secure-boot.nix` (force-disables systemd-boot, enables lanzaboote, `pkiBundle = "/var/lib/sbctl"`), and the two-checks-not-one testing approach (Check 1: vendored upstream signing-chain test, proves Secure Boot + our initrd choice work; Check 2: eval-only module-composition check) — name the gap explicitly: neither check proves the signing chain and the real disk layout work together in one boot, that's accepted and documented, not silently implied to be covered. Match the existing prose style/tone in that section (see how the swap/hibernate paragraphs are written — concrete, cites the real mechanism, one-sentence why for non-obvious calls).

- [ ] **Step 2: Add a section to `README.md`**

Add a section (after the existing "Разметка диска и загрузка" section, matching its structure) covering: what `modules/nixos/secure-boot.nix` is, how to verify it (`nix flake check --no-build` for Check 2, `nix flake check -L` for Check 1), and an "Известные ограничения" list:
- Real key generation and UEFI enrollment only happen on real hardware, at real-install time — this repo never generates/commits Secure Boot keys.
- Check 1 and Check 2 are separate — passing both does not prove Secure Boot and the real disko/LUKS/btrfs layout work together in one boot; that combination has never been tested end-to-end (named limitation, see design doc's "Risk profile").
- `hosts/mimir/` still doesn't exist; enabling `secure-boot.nix` on the real host is a future, explicitly-requested step alongside real key enrollment.

- [ ] **Step 3: Commit**

```bash
git add README.md system-plan.md
git commit -m "Document Secure Boot module, two-checks testing approach, and known limitations"
```
