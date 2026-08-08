# Disk & Boot Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Declarative disk partitioning and boot for the real target machine `mimir` (disk `/dev/sdb`, user `max`) — disko + two LUKS2 containers (root + dedicated swap) + systemd-boot + hibernate support, verified entirely in a throwaway VM. Full rationale: `docs/superpowers/specs/2026-08-08-disk-boot-foundation-design.md`.

**Architecture:** Two reusable Nix modules (`modules/nixos/disko-luks-btrfs.nix`, parameterized disko disk layout; `modules/nixos/boot.nix`, systemd-boot + systemd-initrd) consumed by a throwaway verification host (`hosts/test-disko-luks/`, device `/dev/vda`). `hosts/mimir/` itself is explicitly **not** created by this plan — see the design doc's "Real Install Boundary".

**Tech Stack:** `disko` (new flake input), NixOS's `boot.initrd.luks.devices` (auto-wired by disko), disko's own `testLib.makeDiskoTest` VM-test helper, `nixos-rebuild build-vm` equivalent (`nix build .#nixosConfigurations.<host>.config.system.build.vm` — `nixos-rebuild` itself is not on PATH in this dev sandbox, established precedent from the postgres-redis plan).

## Global Constraints

- Nothing in this plan touches `/dev/sdb` or runs `nixos-install` for real — every verification step targets a throwaway VM disk. Per `CLAUDE.md`'s core rule.
- Disk-budget check (per `CLAUDE.md`) before any heavy build: if projected free space after a build/VM-image would drop under ~5GB, run `nix-collect-garbage -d` first; if still tight after that, stop and ask rather than guessing.
- `nixos-rebuild` is not on PATH in this dev sandbox — use `nix build .#nixosConfigurations.<host>.config.system.build.vm -o result` instead, which requires the target host's `configuration.nix` to explicitly import `(modulesPath + "/virtualisation/qemu-vm.nix")` (established precedent: `hosts/test-vm/configuration.nix` from the postgres-redis plan).
- The `swap` LUKS container must use a **fixed, interactive passphrase** (no `settings.keyFile`, no `randomEncryption`) — `randomEncryption` makes hibernation impossible (confirmed via the NixOS wiki and disko issue #604, cited in the design doc). Both LUKS containers get the **same** passphrase during real formatting so boot only prompts once (NixOS's initrd LUKS unlock auto-retries an already-entered passphrase against later `boot.initrd.luks.devices` entries) — this plan's VM tests use `passwordFile` for non-interactive automation (see Task 1), but must use the **same** password string in both places to actually exercise this auto-retry behavior, not just two independently-working LUKS containers.
- Every non-trivial `.nix` file gets WHY-comments per `CLAUDE.md` — this repo's explicit, deliberate exception to "no comments unless non-obvious."
- Verify claims against real sources at implementation time, not memory — this plan cites specific disko source files/examples/issues; if the pinned `disko` version in `flake.lock` behaves differently, trust what you observe and note the discrepancy, don't force the plan's assumption.

---

## Task 1: Disko flake input + the two reusable Nix modules

**Files:**
- Modify: `flake.nix`
- Create: `modules/nixos/disko-luks-btrfs.nix`
- Create: `modules/nixos/boot.nix`

**Interfaces:**
- Produces: `modules/nixos/disko-luks-btrfs.nix` is a function `{ device, swapSize ? "34G" }: { disko.devices = ...; }` — callers invoke it via `(import ./disko-luks-btrfs.nix { device = "..."; swapSize = "..."; })` inside a NixOS `imports` list, NOT a plain path reference (it takes custom arguments, unlike a standard `{ config, pkgs, ... }` module).
- Produces: `modules/nixos/boot.nix` is a plain NixOS module (no arguments needed beyond the standard module args) — reference it directly by path in `imports`.
- Consumes (Task 2): both modules get imported into `hosts/test-disko-luks/configuration.nix`.

- [ ] **Step 1: Add the `disko` flake input**

Edit `flake.nix` — add the input and thread it through `outputs`:

```nix
{
  # Scoped to what actually exists so far: the agent-sandbox package, a
  # throwaway test-vm host for the dev-databases module, and (new) the
  # disko/boot modules for the disk foundation design plus their own
  # throwaway verification host. Not yet the full host flake (Hyprland,
  # home-manager, sops-nix, hosts/mimir) — see system-plan.md §3.
  description = "agent-sandbox package + dev-databases test-vm + disk/boot foundation (see system-plan.md)";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.disko = {
    url = "github:nix-community/disko";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        # claude-code/opencode/chromium license status in nixpkgs should
        # be double-checked at implementation time (CLAUDE.md: verify,
        # don't assume) — set true defensively so an unfree marking
        # doesn't silently break the build.
        config.allowUnfree = true;
      };
    in
    {
      packages.${system} = rec {
        agent-sandbox-image =
          import ./modules/nixos/packages/agent-sandbox.nix { inherit pkgs; };
        # Bare `nix build` (no attribute) resolves to `.default` —
        # without this it fails outright since there's only one package
        # and its name isn't `default` (final review, M8).
        default = agent-sandbox-image;
      };

      # Throwaway verification host for the dev-databases module (Postgres+
      # Redis via oci-containers) — see docs/superpowers/plans/
      # 2026-08-04-postgres-redis.md and hosts/test-vm/configuration.nix's
      # own header comment for why this isn't a real target machine.
      nixosConfigurations.test-vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./hosts/test-vm/configuration.nix ];
      };

      # Throwaway verification host for the disk/boot foundation design
      # (disko-luks-btrfs.nix + boot.nix) — see docs/superpowers/specs/
      # 2026-08-08-disk-boot-foundation-design.md. NOT the real mimir host.
      nixosConfigurations.test-disko-luks = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          ./hosts/test-disko-luks/configuration.nix
        ];
      };
    };
}
```

- [ ] **Step 2: Write `modules/nixos/disko-luks-btrfs.nix`**

```nix
# Parameterized disko disk layout: GPT -> ESP -> two LUKS2 containers
# (root: btrfs with root/home/nix subvolumes; swap: a dedicated partition,
# NOT a btrfs subvolume swapfile). Full rationale for the two-container
# split (vs. swap-as-subvolume) and the resumeDevice mechanism below:
# docs/superpowers/specs/2026-08-08-disk-boot-foundation-design.md
# "Disk Architecture" and "Hibernate" sections. Short version: a btrfs
# swapfile's hibernate-resume behavior has a real history of breaking
# under boot.initrd.systemd.enable (nixpkgs issue #213122); a dedicated
# LUKS-wrapped swap partition with disko's own `resumeDevice = true` flag
# sidesteps that whole bug class.
#
# `device` and `swapSize` are parameters (not hardcoded) so the exact same
# module is reused by both hosts/test-disko-luks/ (device = "/dev/vda",
# a small swapSize to fit the throwaway test disk) and, later, the real
# hosts/mimir/ (device = "/dev/sdb", swapSize = "34G" to match the old
# .trash/disko.nix's number — adjust if mimir's actual RAM differs, since
# hibernate needs swap >= RAM).
{ device, swapSize ? "34G" }:
{
  disko.devices = {
    disk = {
      main = {
        inherit device;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            # Explicit `priority` on every partition (not relying on
            # attribute-name sort order) per disko's own migration docs
            # (docs/table-to-gpt.md): the new `type = "gpt"` layout uses
            # `priority` to determine the actual partition number/order,
            # not declaration order or key name. cryptswap gets a fixed
            # size and priority 2 so it's carved out BEFORE cryptroot
            # claims the rest via `size = "100%"` at priority 3.
            ESP = {
              priority = 1;
              size = "1024M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            cryptswap = {
              priority = 2;
              size = swapSize;
              content = {
                type = "luks";
                name = "cryptswap";
                settings.allowDiscards = true;
                # No settings.keyFile and no randomEncryption: this must be
                # a fixed-passphrase LUKS container, not disko's random-key
                # swap encryption — randomEncryption makes hibernation
                # impossible outright (confirmed via disko issue #604 and
                # the NixOS wiki's Swap page: the key doesn't survive a
                # reboot, so a hibernate image written under one random key
                # can never be read back). Interactive passphrase prompt by
                # default (no passwordFile set here) — real install must
                # use the SAME passphrase as cryptroot below, see this
                # plan's Global Constraints.
                content = {
                  type = "swap";
                  resumeDevice = true; # disko's own flag: sets
                    # boot.resumeDevice to this (decrypted, mapped) device
                    # declaratively — see disko's lib/types/swap.nix.
                };
              };
            };
            cryptroot = {
              priority = 3;
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                settings.allowDiscards = true;
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "/root" = {
                      mountpoint = "/";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    "/home" = {
                      mountpoint = "/home";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    "/nix" = {
                      mountpoint = "/nix";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
```

- [ ] **Step 3: Write `modules/nixos/boot.nix`**

```nix
# Shared boot-loader module: systemd-boot + the modern systemd-based
# initrd. boot.initrd.systemd.enable is needed for a working LUKS unlock
# prompt under systemd-boot on current NixOS, and (per the design doc's
# Hibernate section) is also the initrd that's able to auto-detect a
# resume device via EFI variables on recent NixOS versions. No separate
# luks.nix module: disko's own module already registers both LUKS
# containers (boot.initrd.luks.devices) from disko-luks-btrfs.nix's own
# description — there is nothing LUKS-specific left to configure here.
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
}
```

- [ ] **Step 4: Syntax-check**

Run: `nix-instantiate --parse modules/nixos/disko-luks-btrfs.nix modules/nixos/boot.nix flake.nix`
Expected: no errors (this only checks Nix syntax, not evaluation — Task 2's `nix flake check` is the real eval test, this step just catches typos early and cheaply).

- [ ] **Step 5: Commit**

```bash
git add flake.nix modules/nixos/disko-luks-btrfs.nix modules/nixos/boot.nix
git commit -m "Add disko flake input + parameterized disk-layout and boot modules"
```

---

## Task 2: Throwaway verification host + flake check

**Files:**
- Create: `hosts/test-disko-luks/configuration.nix`

**Interfaces:**
- Consumes: `modules/nixos/disko-luks-btrfs.nix` (called with `device = "/dev/vda"` and a small `swapSize` — see Step 1 below for why not 34G), `modules/nixos/boot.nix` (imported directly), both from Task 1.

- [ ] **Step 1: Write `hosts/test-disko-luks/configuration.nix`**

`swapSize = "2G"` here, NOT the real 34G: this host's virtual disk (Task 3's qcow2/VM disk) is small (8G, per the design doc's Testing section) and only needs to prove the LUKS+swap+resumeDevice mechanism works — it doesn't need to actually hold a real hibernate image sized for real RAM.

```nix
# Throwaway verification host for the disk/boot foundation design — NOT a
# real target machine, and NOT hosts/mimir/ (see docs/superpowers/specs/
# 2026-08-08-disk-boot-foundation-design.md "Real Install Boundary" for why
# the real host isn't created by this plan). Mirrors hosts/test-vm/'s
# established pattern: nixos-rebuild build-vm normally injects the qemu-vm
# module itself, but nixos-rebuild isn't on PATH in this dev sandbox, so
# `nix build .#nixosConfigurations.test-disko-luks.config.system.build.vm`
# is used instead, which needs that module imported explicitly here.
{ config, pkgs, modulesPath, ... }:
{
  imports = [
    (import ../../modules/nixos/disko-luks-btrfs.nix {
      device = "/dev/vda";
      swapSize = "2G"; # small on purpose — see this file's own header comment
    })
    ../../modules/nixos/boot.nix
    (modulesPath + "/virtualisation/qemu-vm.nix")
  ];

  # Arbitrary but required by NixOS for any system closure to evaluate —
  # doesn't need to track the real nixpkgs channel version for a
  # throwaway VM that's never upgraded in place.
  system.stateVersion = "24.05";
}
```

- [ ] **Step 2: Disk-budget check**

Run: `df -h /`
If projected free space after Task 3's build would drop under ~5GB, run `nix-collect-garbage -d` first per `CLAUDE.md`.

- [ ] **Step 3: Run `nix flake check`**

Run: `nix flake check`
Expected: passes, including the new `nixosConfigurations.test-disko-luks` evaluating cleanly (disko's module should auto-derive `fileSystems`/`swapDevices`/`boot.initrd.luks.devices` from `disko-luks-btrfs.nix`'s description — no manual `fileSystems."/"` needed here, unlike `hosts/test-vm/`, since disko provides it).

If it fails on something disko-specific (e.g. a missing option, an eval error inside `disko.devices`), read the error fully — it's more likely a real mistake in Task 1's module than a plan bug, given Task 1's module was written against verified real disko examples/source, but don't assume either way; check.

- [ ] **Step 4: `nixos-rebuild dry-build` equivalent**

Run: `nix build .#nixosConfigurations.test-disko-luks.config.system.build.toplevel --dry-run`
Expected: lists the derivations that would be built/fetched, no errors.

- [ ] **Step 5: Commit**

```bash
git add hosts/test-disko-luks/configuration.nix
git commit -m "Add throwaway test-disko-luks host for disk/boot foundation verification"
```

---

## Task 3: VM-based disko + hibernate verification

**Files:**
- Create: `modules/nixos/disko-luks-btrfs-test.nix` (small VM-test wrapper, see Step 1 — separate from the reusable module itself)

**Interfaces:**
- Consumes: `modules/nixos/disko-luks-btrfs.nix` (Task 1), `hosts/test-disko-luks/configuration.nix` (Task 2).

This is the task with real, functional risk — everything up to here is Nix eval-time correctness; this task proves the disk layout, LUKS unlock, and hibernate wiring actually work against a real (virtual) disk.

- [ ] **Step 1: Write a disko VM test using disko's own test helper**

Disko ships a reusable NixOS-VM-test helper specifically for this (`diskoLib.testLib.makeDiskoTest`, exposed as the `lib` output of the `disko` flake input) — reuse it rather than writing a raw VM test from scratch, per `CLAUDE.md`'s "search for real solutions" rule. Disko's own test suite has a directly comparable example combining LUKS + btrfs at `https://github.com/nix-community/disko/blob/master/tests/luks-btrfs-raid.nix` (fetch and read it before writing this file — it shows the exact shape: `disko-config` points at a disko config file, `extraTestScript` is a Python-ish string of `machine.succeed(...)` assertions run inside the booted VM).

**Before writing the actual call, verify `makeDiskoTest`'s exact parameter contract** by reading `https://github.com/nix-community/disko/blob/master/lib/testing.nix` (or wherever `testLib` actually lives in the pinned version once `flake.lock` exists from Task 1) — specifically whether `disko-config` accepts a file path only, or also an already-evaluated attribute set (this module is parameterized — `{ device, swapSize }: {...}` — not a plain attrset like disko's own example files, so you likely need a tiny wrapper file that calls it with test parameters and exposes the resulting plain `disko.devices` attrset, hence this task creates `modules/nixos/disko-luks-btrfs-test.nix` rather than pointing `disko-config` at `disko-luks-btrfs.nix` directly). If the pinned version's actual contract differs from what's described here, follow what you observe, not this text.

Starting point (adjust to match the verified real contract from the step above):

```nix
# modules/nixos/disko-luks-btrfs-test.nix — plain (non-parameterized) disko
# config for the VM test below, calling disko-luks-btrfs.nix with test-only
# parameters. Not consumed by hosts/test-disko-luks/configuration.nix
# (which imports the parameterized module directly) — this file exists
# only because disko's own makeDiskoTest test helper (see the flake check
# in this task) expects a plain config, not a function.
import ./disko-luks-btrfs.nix { device = "/dev/vda"; swapSize = "2G"; }
```

Then, in `flake.nix`'s `outputs`, add a `checks` output (verify the exact `makeDiskoTest` call signature per Step 1's note before finalizing):

```nix
checks.${system} = {
  disko-luks-btrfs = disko.lib.testLib.makeDiskoTest {
    inherit pkgs;
    name = "disko-luks-btrfs";
    disko-config = ./modules/nixos/disko-luks-btrfs-test.nix;
    extraTestScript = ''
      # Both LUKS containers actually exist and are real LUKS (not
      # plaintext, not randomEncryption swap):
      machine.succeed("cryptsetup isLuks /dev/vda2")
      machine.succeed("cryptsetup isLuks /dev/vda3")
      # btrfs root came up with its subvolumes:
      machine.succeed("btrfs subvolume list /")
      # swap is actually active on the decrypted mapper device, not the
      # raw partition (proves the LUKS -> swap nesting actually worked —
      # the one thing the design doc flagged as unverified-by-example):
      machine.succeed("swapon --show | grep -q /dev/mapper/cryptswap")
      # boot.resumeDevice ended up pointing at the right place — check the
      # activated system's kernel params, not just that the option exists
      # at eval time:
      machine.succeed("cat /proc/cmdline | grep -q resume=")
    '';
  };
};
```

Adjust `/dev/vda2`/`/dev/vda3` partition numbers if `priority` produced a different actual numbering than expected — check `lsblk`/`fdisk -l /dev/vda` inside the test (or in a manual run) rather than assuming.

- [ ] **Step 2: Run the disko VM test**

Run: `nix flake check -L` (the `-L` shows full build/test logs, needed to see the VM test's actual assertions and any failures — a bare `nix flake check` only shows pass/fail).

This is a real, slow VM build+boot+test cycle — expect it to take a while (established precedent from the postgres-redis plan's Task 3: real `nix build` for a VM closure can take 20-30+ minutes in this sandbox, especially on a cold store). Run it in the foreground and block on it; if backgrounding it, poll with real `sleep 30`-`60` between checks, not a tight loop — this is a subagent execution-environment note from earlier plans in this repo, still applicable.

If `swapon --show | grep -q /dev/mapper/cryptswap` or the `resume=` check fails specifically (as opposed to the LUKS/btrfs checks, which are lower-risk and match well-documented patterns): this is exactly the scenario the design doc's Hibernate section flagged as unverified-by-committed-example. Don't just declare it broken — investigate what `swapon --show`/`cat /proc/cmdline` actually show inside the VM (add a `machine.succeed("swapon --show")` without the grep, temporarily, to see the raw output) before concluding the `luks -> swap -> resumeDevice` nesting doesn't work as designed. If it genuinely doesn't work, the design doc names a fallback (`swapDevices.*.encrypted.blkDev`, a NixOS-level option independent of disko's swap content type) — flag this to the controller rather than silently reworking the whole module; it's a real design decision, not a mechanical fix.

- [ ] **Step 3: Best-effort hibernate check in the VM**

QEMU supports suspend-to-disk; attempt it as a sanity check (not a substitute for real hardware verification — the design doc is explicit about this). Build and boot the VM directly (not via the `checks` test harness, which doesn't give an interactive session):

```bash
nix build .#nixosConfigurations.test-disko-luks.config.system.build.vm -o result
./result/bin/run-test-disko-luks-vm
```

Inside the running VM (enter the LUKS passphrase you set when the test disk was formatted — if this is the first boot of a fresh image, disko's activation runs the actual formatting with whatever `passwordFile`/interactive prompt Step 1's test config specifies; check what Step 1 actually did for password handling before assuming an interactive prompt appears here), attempt `systemctl hibernate` and power back on. Record what happens — success, failure, or inconclusive (QEMU hibernate support can be finicky) — as a note in this task's completion, not as a pass/fail gate for the task. The real gate is Step 2's automated assertions.

- [ ] **Step 4: Cleanup**

Remove `./result` and any `nixos.qcow2` created by the manual VM run in Step 3 — these are build byproducts, not meant to be committed (check `.gitignore` covers them; if not, add an entry rather than leaving loose byproducts for `git status` to flag later).

- [ ] **Step 5: Commit**

```bash
git add flake.nix modules/nixos/disko-luks-btrfs-test.nix
git commit -m "Add disko VM test for the disk/boot foundation (LUKS, btrfs, hibernate wiring)"
```

---

## Task 4: Documentation

**Files:**
- Modify: `README.md`
- Modify: `system-plan.md` (§4)

**Interfaces:** none — documentation only.

- [ ] **Step 1: Update `system-plan.md` §4**

Find the current §4 ("Разметка диска и загрузка") — it currently describes a single LUKS2 container with an optional `/swap` subvolume. Replace with the actual finalized architecture (two LUKS2 containers, dedicated swap partition, `resumeDevice` mechanism) — condense the design doc's "Disk Architecture" and "Hibernate" sections into a few paragraphs matching this file's existing prose style (see §5.11/§5.12 for the established tone: what was built, the one-sentence why for the non-obvious calls). Reference `modules/nixos/disko-luks-btrfs.nix` and `modules/nixos/boot.nix` by path, and note that `hosts/mimir/` itself isn't built yet (still §3's aspirational structure) — verified only via `hosts/test-disko-luks/`.

- [ ] **Step 2: Add a section to `README.md`**

Add a section (after the existing Postgres/Redis section, matching this file's established pattern — see the existing sections for tone/structure) covering: what `modules/nixos/disko-luks-btrfs.nix`/`boot.nix` are, how to verify them (`nix flake check -L`, the disko VM test), and an explicit "Известные ограничения" list:
- Real hibernate-and-resume is only genuinely confirmed on actual hardware — the VM check (Task 3, Step 3) is best-effort, not proof.
- `hosts/mimir/` (the real host) doesn't exist yet — this only produces reusable, VM-verified modules. Real install is a separate, explicitly-requested step (see the design doc's "Real Install Boundary").
- Both LUKS containers need the **same** passphrase entered during the real install's formatting step for the single-prompt boot behavior to actually happen — if they end up with different passphrases, boot will prompt twice.

- [ ] **Step 3: Commit**

```bash
git add README.md system-plan.md
git commit -m "Document disk/boot foundation modules and known limitations"
```
