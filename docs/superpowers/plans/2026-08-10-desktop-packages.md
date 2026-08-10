# Desktop Package List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the remaining declarative package list from `system-plan.md` §5 (IDE/editors, AI agent host packages, communication/browser, API/network, proxy client, remote desktop, KDE Connect, virtualization, media) as one `modules/nixos/desktop-apps.nix`. No custom packaging needed anywhere — research (see design doc) found Throne is a plain nixpkgs package with its own module now, collapsing what was going to be a separate custom-derivation task into this one. Full rationale: `docs/superpowers/specs/2026-08-10-desktop-packages-design.md`.

**Architecture:** One system-level module (`environment.systemPackages` + two NixOS program-module enables: `programs.throne`, `programs.kdeconnect`). Verified via eval + dry-build only — no VM functional test (see the design doc's "Testing Scope" for why: this plan has no runtime mechanism to prove, just package/option presence, and re-testing upstream's own already-CI-covered packages would be ceremony this problem doesn't need).

**Tech Stack:** Plain nixpkgs packages + two NixOS program modules (`programs.throne`, `programs.kdeconnect`) already shipped in nixpkgs.

## Global Constraints

- **Verify every non-obvious package attribute name before using it** — this plan's own research already found two real surprises (`jetbrains.rubymine` → `jetbrains.ruby-mine`; Throne needing no custom derivation at all). Don't carry a name over from `system-plan.md`'s older text without checking; it's already been wrong once in this same pass.
- **`nix search` doesn't honor `nixpkgs.config.allowUnfree = true`** for unfree packages (it evaluates against nixpkgs' own default `allowUnfree = false` and silently drops anything that fails to evaluate) — this is why `jetbrains.ruby-mine` looked absent when it wasn't. To check an unfree package's existence, use `NIXPKGS_ALLOW_UNFREE=1 nix eval --impure --expr '(import <nixpkgs> { config.allowUnfree = true; }).<attr>.version'` instead of `nix search`.
- No `libvirtd`/`kvm` group membership for any specific user — no real user exists in this repo yet (`hosts/mimir/` doesn't exist, home-manager doesn't exist). `virtualisation.libvirtd.enable`/`programs.virt-manager.enable` are system-level and don't need one; group membership is a real-install-time step once a real user exists.
- No VM functional test for this plan (see design doc "Testing Scope") — `nix flake check --no-build` + a dry-build is the complete verification bar.
- `install.determinate.systems` substituter is unreachable in this sandbox — always pass `--option substituters "https://cache.nixos.org/" --option extra-substituters ""` on build/check commands.
- Every non-trivial `.nix` file gets WHY-comments per `CLAUDE.md` — in particular, the Throne/RubyMine surprises are exactly the kind of thing worth a comment so nobody re-trusts the stale `system-plan.md` wording six months from now without checking first.

---

## Task 1: `modules/nixos/desktop-apps.nix`

**Files:**
- Create: `modules/nixos/desktop-apps.nix`

**Interfaces:**
- Produces: a plain NixOS module (no custom arguments) — reference by path in `imports`. No flake input changes needed (everything here is plain nixpkgs).

- [ ] **Step 1: Verify every package/option name for real before writing the file**

Don't trust the list below blindly — it reflects this plan's own research as of 2026-08-10, but nixpkgs moves fast (as the RubyMine rename itself proves). Re-check each non-trivial one:
```bash
NIXPKGS_ALLOW_UNFREE=1 nix eval --impure --expr '(import <nixpkgs> { config.allowUnfree = true; }).jetbrains.ruby-mine.version'
nix eval --impure --expr '(import <nixpkgs> {}).throne.version'
nix eval --impure --expr '(import <nixpkgs> {}).wayvnc.version'
nix eval --impure --expr '(import <nixpkgs> {}).remmina.version'
NIXPKGS_ALLOW_UNFREE=1 nix eval --impure --expr '(import <nixpkgs> { config.allowUnfree = true; }).kdePackages.kdeconnect-kde.version'
```
If any of these fail, that's a real finding — investigate (renamed? removed? restructured, like RubyMine was?) rather than guessing a fix.

- [ ] **Step 2: Write the module**

```nix
# Declarative desktop package list — system.plan.md §5.4-§5.10, §5.1.1,
# §5.1.2. Placed here (system-level environment.systemPackages), NOT
# under modules/home/ as system-plan.md §3's aspirational structure
# eventually wants: home-manager isn't built in this repo yet (separate,
# later task per explicit priority order, 2026-08-10). This is a
# sequencing choice, not a permanent one — revisit once home-manager
# exists.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # §5.4 IDE / редакторы
    # jetbrains.ruby-mine, NOT jetbrains.rubymine (renamed upstream,
    # hyphenated to match rust-rover's convention — the old name doesn't
    # exist anymore, not even as an alias/throw). `nix search` looked
    # empty for BOTH names because it doesn't honor
    # nixpkgs.config.allowUnfree=true (only applies to a real pkgs
    # instance, not bare `nix search`'s own hermetic eval) — don't take
    # `nix search`'s silence on an unfree package as evidence it's gone;
    # verify with `NIXPKGS_ALLOW_UNFREE=1 nix eval --impure` instead.
    jetbrains.ruby-mine
    vscode

    # §5.5 AI coding agents — host-level packages for one-off interactive
    # use (system-plan.md §5.5); the sandboxed/per-project path is
    # separate, see modules/nixos/packages/agent-sandbox.nix and README.md.
    claude-code
    opencode

    # §5.6 Коммуникация / браузер
    telegram-desktop
    google-chrome
    firefox

    # §5.7 API / сеть
    postman

    # §5.1.1 Удалённый стол (обе стороны — сервер и клиент, решено
    # 2026-08-10)
    wayvnc
    remmina

    # §5.10 Медиа
    mpv
    yt-dlp
    pavucontrol
    playerctl

    # §5.9 Виртуализация — OVMF/spice-vdagent packages; libvirtd/
    # virt-manager themselves are enabled as services/programs below, not
    # packages here
    OVMFFull
    spice-vdagent
  ];

  # §5.1.2 Телефон ↔ ПК (решено 2026-08-10) — module auto-provides
  # kdePackages.kdeconnect-kde and opens the needed firewall ports
  # (TCP/UDP 1714-1764) itself; simpler than doing it by hand in
  # networking.firewall.
  programs.kdeconnect.enable = true;

  # §5.8 Прокси-клиент — Throne (nekoray's successor). NOT a custom
  # AppImage/binary derivation as system-plan.md originally described:
  # verified (2026-08-10) it's now a plain nixpkgs package built from
  # source, with its own NixOS module that already solves the hard parts
  # (wraps the sing-box-backed core with the right capabilities via
  # setcap, auto-configures polkit for TUN-mode DNS so it doesn't need
  # repeated password prompts). tunMode.enable avoids needing full
  # setuid-root.
  programs.throne = {
    enable = true;
    tunMode.enable = true;
  };

  # §5.9 Виртуализация
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  # No libvirtd/kvm group membership here — no real user exists yet in
  # this repo (hosts/mimir/ doesn't exist, home-manager doesn't exist).
  # That's a real-install-time step once a real user is defined, not
  # this module's job.
}
```

- [ ] **Step 3: Syntax-check**

Run: `nix-instantiate --parse modules/nixos/desktop-apps.nix`

- [ ] **Step 4: Commit**

```bash
git add modules/nixos/desktop-apps.nix
git commit -m "Add desktop-apps.nix: IDE, comms, remote desktop, KDE Connect, Throne, virtualisation, media"
```

---

## Task 2: Throwaway host + verification

**Files:**
- Create: `hosts/test-desktop-apps/configuration.nix`
- Modify: `flake.nix` (register `nixosConfigurations.test-desktop-apps`)

**Interfaces:**
- Consumes: `modules/nixos/desktop-apps.nix` (Task 1), `modules/nixos/boot.nix` (existing).

- [ ] **Step 1: Write `hosts/test-desktop-apps/configuration.nix`**

Plain shape, no disko/LUKS (same reasoning as the secrets plan's test host — nothing here interacts with disk encryption):

```nix
# Throwaway verification host for the desktop package list — NOT a real
# target machine, and NOT hosts/mimir/. Proves the package list and the
# two program-module enables (programs.throne, programs.kdeconnect)
# evaluate and build together — no VM boot needed, see
# docs/superpowers/specs/2026-08-10-desktop-packages-design.md
# "Testing Scope" for why a functional test isn't warranted here.
{ ... }:
{
  imports = [
    ../../modules/nixos/desktop-apps.nix
    ../../modules/nixos/boot.nix
  ];

  fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
  boot.loader.grub.device = "/dev/vda";

  system.stateVersion = "24.05";
}
```

- [ ] **Step 2: Register `nixosConfigurations.test-desktop-apps` in `flake.nix`**

```nix
nixosConfigurations.test-desktop-apps = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [ ./hosts/test-desktop-apps/configuration.nix ];
};
```

- [ ] **Step 3: Disk-budget check, then verify**

`df -h /`, GC if projected free space would drop under ~5GB (this task's dry-build will pull real packages — RubyMine, VSCode, Chrome, and friends are large; budget accordingly, more so than the smaller modules in earlier plans).

```bash
nix flake check --no-build --option substituters "https://cache.nixos.org/" --option extra-substituters ""
nix build .#nixosConfigurations.test-desktop-apps.config.system.build.toplevel --dry-run --option substituters "https://cache.nixos.org/" --option extra-substituters ""
```
Expected: both pass cleanly — the dry-run confirms every package/derivation in the closure would actually build/fetch, without spending the time or disk to do so for real.

- [ ] **Step 4: Commit**

```bash
git add hosts/test-desktop-apps/configuration.nix flake.nix
git commit -m "Add throwaway test-desktop-apps host for eval + dry-build verification"
```

---

## Task 3: Documentation

**Files:**
- Modify: `README.md`
- Modify: `system-plan.md` (§5.4, §5.8 in particular — both have stale content this plan corrects)

**Interfaces:** none — documentation only.

- [ ] **Step 1: Update `system-plan.md`**

- §5.4: fix `jetbrains.rubymine` → `jetbrains.ruby-mine`, with a one-line note on why (renamed upstream) and the `nix search`-doesn't-honor-`allowUnfree` gotcha, so a future reader doesn't get confused by the same false negative.
- §5.8: replace the custom-AppImage/`autoPatchelfHook`/`nix-ld` packaging description entirely — Throne is a plain nixpkgs package now, with its own `programs.throne` module. Keep the nekoray→Throne succession history (still accurate), drop everything about hand-rolling a derivation.
- Note near §5.1.1/§5.1.2 (or wherever fits) that these are now implemented in `modules/nixos/desktop-apps.nix`, not just planned.

- [ ] **Step 2: Add a section to `README.md`**

Add a section (matching the structure of the existing module sections) covering: what `desktop-apps.nix` is, that it's system-level for now (not home-manager, sequencing choice), how to verify it, and an "Известные ограничения" list:
- No `libvirtd`/`kvm` group membership for any user yet — real-install-time step.
- Package list is system-wide, not yet reorganized into home-manager (future task).
- The two surprises found during research (RubyMine rename, Throne no longer needing custom packaging) — worth a pointer here too, in case someone re-derives package lists from `system-plan.md`'s history without reading this plan.

- [ ] **Step 3: Commit**

```bash
git add README.md system-plan.md
git commit -m "Document desktop-apps.nix, correct stale RubyMine/Throne info in system-plan.md"
```
