# home-manager Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire home-manager into the flake as reusable, NixOS-module-integrated infrastructure — flake input, `modules/nixos/home-manager.nix`, and a throwaway test host proving it composes and actually builds. Full rationale: `docs/superpowers/specs/2026-08-11-home-manager-design.md`.

**Architecture:** `home-manager.nixosModules.home-manager` is imported at the flake level (same pattern `disko.nixosModules.disko` already uses) alongside a small reusable module (`useGlobalPkgs`/`useUserPackages` settings). No per-user `home-manager.users.<name>` block belongs in the reusable module or in `hosts/mimir/configuration.nix` yet — that's host-specific content gated on a real username, which doesn't exist. A throwaway host with a throwaway user proves the plumbing instead.

**Tech Stack:** `home-manager` (new flake input, `github:nix-community/home-manager`, `master` branch — tracks `nixos-unstable`, matching this repo's own `nixpkgs` pin).

## Global Constraints

- No real dotfile content (`modules/home/*`), no Hyprland module — both explicitly out of scope, see design doc "Out of Scope".
- No `home-manager.users.*` block added to `hosts/mimir/configuration.nix` — no real user exists yet (design doc, "What's genuinely reusable vs. host-specific").
- Disk-budget check (per `CLAUDE.md`) before Task 2's real build: if projected free space would drop under ~5GB, `nix-collect-garbage -d` first.
- This sandbox's `install.determinate.systems` substituter is unreachable — always pass `--option substituters "https://cache.nixos.org/" --option extra-substituters ""` on `nix build`/`nix flake check` commands (established fix, used in every prior round).
- Every non-trivial `.nix` file gets WHY-comments per `CLAUDE.md`.

---

## Task 1: home-manager flake input + reusable module

**Files:**
- Modify: `flake.nix`
- Create: `modules/nixos/home-manager.nix`

**Interfaces:**
- Produces: `modules/nixos/home-manager.nix` is a plain NixOS module (no arguments) — reference it directly by path in `imports`. Requires `home-manager.nixosModules.home-manager` also present in the consuming `nixosSystem`'s `modules` list.
- Consumes (Task 2): imported by `hosts/test-home-manager/configuration.nix`.

- [ ] **Step 1: Add the `home-manager` flake input**

In `flake.nix`, after the existing `inputs.sops-nix = { ... };` block (currently lines 27-30), insert:

```nix
  inputs.home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };
```

- [ ] **Step 2: Thread `home-manager` through `outputs`**

Change:
```nix
  outputs = { self, nixpkgs, disko, lanzaboote, sops-nix, ... }:
```
to:
```nix
  outputs = { self, nixpkgs, disko, lanzaboote, sops-nix, home-manager, ... }:
```

- [ ] **Step 3: Update the top-of-file header comment and `description`**

Change:
```nix
  # Scoped to what actually exists so far: the agent-sandbox package, a
  # throwaway test-vm host for the dev-databases module, the disko/boot
  # modules for the disk foundation design plus their own throwaway
  # verification host, the Secure Boot foundation, the declarative desktop
  # package list (desktop-apps.nix), and sops-nix for secrets management.
  # Not yet the full host flake (Hyprland, home-manager, hosts/mimir) —
  # see system-plan.md §3.
  description = "agent-sandbox package + dev-databases test-vm + disk/boot + Secure Boot + desktop packages + sops-nix foundations (see system-plan.md)";
```
to:
```nix
  # Scoped to what actually exists so far: the agent-sandbox package, a
  # throwaway test-vm host for the dev-databases module, the disko/boot
  # modules for the disk foundation design plus their own throwaway
  # verification host, the Secure Boot foundation, the declarative desktop
  # package list (desktop-apps.nix), sops-nix for secrets management, and
  # home-manager infrastructure (NixOS-module-integrated, no dotfile
  # content yet). Not yet the full host flake (Hyprland, hosts/mimir's
  # real user) — see system-plan.md §3.
  description = "agent-sandbox package + dev-databases test-vm + disk/boot + Secure Boot + desktop packages + sops-nix + home-manager foundations (see system-plan.md)";
```

- [ ] **Step 4: Write `modules/nixos/home-manager.nix`**

```nix
# Enables home-manager as NixOS-module-integrated infrastructure (not
# standalone `home-manager switch`) — matches system-plan.md §2's
# architecture table ("привязка к NixOS-модулям"). Requires
# home-manager.nixosModules.home-manager imported alongside this module at
# the flake level (same pattern disko.nixosModules.disko already uses) —
# this file only sets the options that module provides, it doesn't import
# it itself. No per-user home-manager.users.<name> block here: that's
# host-specific (a real username), same boundary users.users.* already has
# in this repo — see docs/superpowers/specs/2026-08-11-home-manager-design.md.
{
  # Reuses the host's own already-evaluated pkgs instead of importing
  # nixpkgs a second time -- cheaper, and keeps nixpkgs.config.allowUnfree
  # (set per-host, e.g. desktop-apps.nix-importing hosts) visible to
  # home-manager's own packages too.
  home-manager.useGlobalPkgs = true;
  # Installs home.packages into /etc/profiles/per-user/<name> (the modern,
  # NixOS-module-integrated path) instead of the legacy ~/.nix-profile.
  home-manager.useUserPackages = true;
}
```

- [ ] **Step 5: Syntax-check**

Run: `nix-instantiate --parse modules/nixos/home-manager.nix flake.nix`
Expected: no errors (syntax only — Task 2's `nix flake check --no-build` is the real eval test for this module composing correctly; `flake.nix` itself won't fully re-evaluate until Task 2 also registers the test host, since `home-manager` is now an unused `outputs` argument until then — that's expected and harmless).

- [ ] **Step 6: Commit**

```bash
git add flake.nix modules/nixos/home-manager.nix
git commit -m "Add home-manager flake input + home-manager.nix module"
```

---

## Task 2: Throwaway test host + build verification

**Files:**
- Create: `hosts/test-home-manager/configuration.nix`
- Modify: `flake.nix` (register `nixosConfigurations.test-home-manager`)

**Interfaces:**
- Consumes: `modules/nixos/boot.nix` (existing, unmodified), `modules/nixos/home-manager.nix` (Task 1), `home-manager.nixosModules.home-manager` (Task 1's flake input).

- [ ] **Step 1: Write `hosts/test-home-manager/configuration.nix`**

```nix
# Throwaway verification host for the home-manager infrastructure design —
# NOT a real target machine, and NOT hosts/mimir/. Mirrors
# hosts/test-desktop-apps/'s shape exactly (ext4 /dev/vda1 + grub, no
# qemu-vm.nix import) since this only needs eval + a real build, no VM
# boot -- see docs/superpowers/specs/2026-08-11-home-manager-design.md
# "Testing" for why.
#
# testuser exists only to give home-manager.users.* something to bind to
# -- same throwaway-only status as hosts/test-disko-luks/'s virtual disk
# or hosts/test-secrets/'s test SSH key. NOT a preview of mimir's real
# username; hosts/mimir/configuration.nix still has no users.users.* or
# home-manager.users.* block (see docs/superpowers/specs/
# 2026-08-11-mimir-host-skeleton-design.md) and this host doesn't change
# that.
{ ... }:
{
  imports = [
    ../../modules/nixos/boot.nix
    ../../modules/nixos/home-manager.nix
  ];

  fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
  boot.loader.grub.device = "/dev/vda";

  users.users.testuser = {
    isNormalUser = true;
    home = "/home/testuser";
  };
  home-manager.users.testuser = {
    home.stateVersion = "24.05";
  };

  system.stateVersion = "24.05";
}
```

- [ ] **Step 2: Register `nixosConfigurations.test-home-manager` in `flake.nix`**

After the existing `nixosConfigurations.test-secrets = ...;` block (ends right before the `# Real, functional verification (not just eval) of the disk/boot` comment that introduces `checks.${system}`), insert:

```nix
      # Throwaway verification host for the home-manager infrastructure
      # design — see docs/superpowers/specs/2026-08-11-home-manager-design.md.
      # Eval + a real (non-dry-run) build only, no VM boot — see
      # hosts/test-home-manager/configuration.nix's own header comment.
      nixosConfigurations.test-home-manager = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          home-manager.nixosModules.home-manager
          ./hosts/test-home-manager/configuration.nix
        ];
      };
```

- [ ] **Step 3: Disk-budget check**

Run: `df -h /`. GC first (`nix-collect-garbage -d`) if projected free space after this task's build would drop under ~5GB.

- [ ] **Step 4: Run the eval-only check**

Run: `nix flake check --no-build --option substituters "https://cache.nixos.org/" --option extra-substituters ""`
Expected: passes cleanly, including `nixosConfigurations.test-home-manager` evaluating without error. A real failure here (e.g. `home-manager.useGlobalPkgs` referenced before `home-manager.nixosModules.home-manager` is imported) is a genuine finding — investigate rather than working around it.

- [ ] **Step 5: Run the real build**

Run: `nix build .#nixosConfigurations.test-home-manager.config.system.build.toplevel --option substituters "https://cache.nixos.org/" --option extra-substituters ""`
Expected: succeeds — confirms home-manager's activation-script and `testuser`'s profile derivation actually build, not just evaluate (see design doc "Testing" for why a real build, not `--dry-run`, is the right check here).

- [ ] **Step 6: Cleanup**

Remove any stray `result` symlink this build created (`rm -f result`) — matches existing `.gitignore` handling for build byproducts from prior rounds.

- [ ] **Step 7: Commit**

```bash
git add hosts/test-home-manager/configuration.nix flake.nix
git commit -m "Add throwaway test-home-manager host + build verification"
```

---

## Task 3: Documentation

**Files:**
- Modify: `README.md`
- Modify: `system-plan.md`

**Interfaces:** none — documentation only.

- [ ] **Step 1: Add a `## home-manager` section to `README.md`**

Insert after the existing `## Секреты (sops-nix)` section (ends right before `## Перевод по хоткею (Crow Translate)`):

```markdown
## home-manager

`modules/nixos/home-manager.nix` — включает home-manager как
NixOS-module-интегрированную инфраструктуру (`home-manager.useGlobalPkgs
= true`, `home-manager.useUserPackages = true`), без содержимого
дотфайлов (`modules/home/*`: tmux, neovim, shell, waybar, Hyprland-конфиг
— отдельная будущая задача, ждёт самого Hyprland). Требует
`home-manager.nixosModules.home-manager`, импортированный на уровне
флейка вместе с этим модулем — тот же паттерн, что уже используют
`disko.nixosModules.disko`/`lanzaboote.nixosModules.lanzaboote`.

`home-manager.users.<имя>` — не часть этого модуля: имя пользователя
хост-специфично, та же граница, что уже есть у `users.users.*` в этом
репозитории. `hosts/mimir/configuration.nix` пока не объявляет ни того,
ни другого (см. `docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md`)
— это шаг реальной установки.

Проверка:
- `nix flake check --no-build` — eval-only проверка композиции модулей
  (`hosts/test-home-manager/`, одноразовый хост с тестовым пользователем
  `testuser`, только для этой цели).
- `nix build .#nixosConfigurations.test-home-manager.config.system.build.toplevel`
  — реальная (не dry-run) сборка: подтверждает, что деривации
  activation-скрипта home-manager и профиля пользователя действительно
  собираются, а не только эвалятся. Без VM-теста — без реальных
  дотфайлов нечего проверять поведенчески, см. design doc "Testing".

### Известные ограничения

- **Дотфайлы (`modules/home/*`) не существуют** — этот раунд даёт только
  инфраструктуру; tmux/neovim/shell/waybar/Hyprland-конфиг остаются
  отдельной будущей задачей, зависящей от самого Hyprland-модуля
  (`system-plan.md` §5.2, ещё не построен).
- **`hosts/mimir/`'у некому назначать `home-manager.users.*`** — реального
  пользователя всё ещё нет, та же причина, по которой у него нет
  `users.users.*` (см. skeleton design doc).
```

- [ ] **Step 2: Fix the now-stale `config.sops.secrets."gpg_key".path` bullet in `README.md`**

Find (in the "Секреты (sops-nix)" section's "Известные ограничения"):
```
- **`config.sops.secrets."gpg_key".path` пока без потребителя** —
  подключение к git commit signing понадобится home-manager/user-слой,
  которого в этом флейке ещё нет; отдельная будущая задача.
```
Replace with:
```
- **`config.sops.secrets."gpg_key".path` пока без потребителя** —
  home-manager-инфраструктура теперь есть (`modules/nixos/home-manager.nix`),
  но подключение к git commit signing понадобится реальный
  `home-manager.users.<имя>` на реальном хосте, которого всё ещё нет;
  отдельная будущая задача.
```

- [ ] **Step 3: Add a status note to `system-plan.md` §3**

Find (end of §3, right before `## 4. Разметка диска и загрузка`):
```
Всё, кроме `secrets/secrets.yaml`, можно свободно отдавать другому человеку —
без расшифровки секреты бесполезны, а без своего `secrets.yaml` система
просто соберётся без частей, зависящих от секретов (SSH-ключ и т.п.).

## 4. Разметка диска и загрузка
```
Replace with:
```
Всё, кроме `secrets/secrets.yaml`, можно свободно отдавать другому человеку —
без расшифровки секреты бесполезны, а без своего `secrets.yaml` система
просто соберётся без частей, зависящих от секретов (SSH-ключ и т.п.).

**Статус реализации этой структуры:** `boot.nix`/`disko-luks-btrfs.nix`/
`secure-boot.nix`/`secrets.nix`/`desktop-apps.nix` реализованы (см. §4-§6,
README); home-manager подключён как инфраструктура без дотфайлов (см.
README, раздел «home-manager»); `hosts/mimir/` существует как skeleton
(см. §4). `modules/home/*`, `hyprland.nix`, `Makefile` — всё ещё
аспирационная часть этой структуры, не построены.

## 4. Разметка диска и загрузка
```

- [ ] **Step 4: Commit**

```bash
git add README.md system-plan.md
git commit -m "Document home-manager infrastructure module and known limitations"
```
