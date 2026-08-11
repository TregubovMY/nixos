# `hosts/mimir/` Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `hosts/mimir/disk-config.nix` and `hosts/mimir/configuration.nix` — real host identity + composition of the four already-VM-proven modules (`disko-luks-btrfs.nix`, `secure-boot.nix`, `secrets.nix`, `desktop-apps.nix`) — then update the now-stale "`hosts/mimir/` ещё не существует" claims across `README.md`/`system-plan.md`. Full rationale: `docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md`.

**Architecture:** Two new files under `hosts/mimir/`, no other module changes. `disk-config.nix` is a thin wrapper around `disko-luks-btrfs.nix` using the real values (`/dev/sdb`, `34G`) that module's own header comment already documents. `configuration.nix` imports that plus `secure-boot.nix`/`secrets.nix`/`desktop-apps.nix` and sets host identity. Neither file is registered in `flake.nix` — no hardware-configuration.nix exists yet, so registering now would break `nix flake check` for the whole repo.

**Tech Stack:** Plain Nix, no new dependencies — reuses modules built in prior rounds.

## Global Constraints

- Do **not** register `nixosConfigurations.mimir` in `flake.nix` — this plan's deliverable is unregistered, unbuildable-by-design files (see design doc, "What this is not").
- Do **not** create `hardware-configuration.nix`, `users.users.max`, or any real `secrets/secrets.yaml`/`.sops.yaml` content — all explicitly out of scope, see design doc "Deliberately not included in this round".
- No real hardware access this round (confirmed with the human partner) — everything here is declarative-only, verified with `nix-instantiate --parse`, not `nix flake check` (which wouldn't touch these files anyway since they're unregistered).
- Every non-trivial `.nix` file gets WHY-comments per `CLAUDE.md`.

---

## Task 1: `hosts/mimir/` skeleton files

**Files:**
- Create: `hosts/mimir/disk-config.nix`
- Create: `hosts/mimir/configuration.nix`

**Interfaces:**
- Consumes: `modules/nixos/disko-luks-btrfs.nix` (`{ device, swapSize ? "34G" }`), `modules/nixos/secure-boot.nix`, `modules/nixos/secrets.nix`, `modules/nixos/desktop-apps.nix` — all existing, unmodified.
- Produces: nothing consumed by later tasks in this plan (Task 2 only edits prose docs, not these files) — but future real-install work (out of scope here) will import `configuration.nix` from `flake.nix` once `hardware-configuration.nix` exists.

- [ ] **Step 1: Write `hosts/mimir/disk-config.nix`**

```nix
# Real disk-layout wrapper for mimir — device and swapSize are not new
# decisions here, they're already documented as the intended real values
# in disko-luks-btrfs.nix's own header comment. This file just gives that
# documented intent a real caller. NOT registered in flake.nix yet (see
# docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md) — needs
# a real hardware-configuration.nix first, which needs mimir itself.
import ../../modules/nixos/disko-luks-btrfs.nix {
  device = "/dev/sdb";
  swapSize = "34G";
}
```

- [ ] **Step 2: Write `hosts/mimir/configuration.nix`**

```nix
# Real host identity + module composition for mimir. Deliberately
# incomplete and NOT registered as nixosConfigurations.mimir in flake.nix
# — see docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md
# for exactly what's missing (hardware-configuration.nix, flake.nix
# registration, users.users.max, real secrets/secrets.yaml content) and
# why each is a separate, future, real-hardware-only step, not this file's
# job. Do not treat this file's mere existence as "mimir is installable."
{
  imports = [
    ./disk-config.nix
    ../../modules/nixos/secure-boot.nix # not boot.nix — lanzaboote
      # replaces systemd-boot rather than layering on it (secure-boot.nix
      # itself force-disables boot.loader.systemd-boot.enable); mimir
      # wants Secure Boot per system-plan.md §2/§4.
    ../../modules/nixos/secrets.nix
    ../../modules/nixos/desktop-apps.nix
  ];

  networking.hostName = "mimir";
  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "ru_RU.UTF-8";

  # Required because desktop-apps.nix pulls in unfree packages (RubyMine,
  # Chrome, VSCode, Postman) and flake.nix's allowUnfree = true only
  # applies to its own loose `pkgs` instance (packages.${system}), not to
  # any nixosSystem call — same requirement hosts/test-desktop-apps/
  # already has, see system-plan.md §2.
  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "24.05"; # matches every other host in this repo
}
```

- [ ] **Step 3: Syntax-check both files**

Run: `nix-instantiate --parse hosts/mimir/disk-config.nix hosts/mimir/configuration.nix`
Expected: no errors (syntax only — these files aren't registered in `flake.nix`, so there is no eval-level check to run yet; that happens at the real-install step per the design doc).

- [ ] **Step 4: Commit**

```bash
git add hosts/mimir/disk-config.nix hosts/mimir/configuration.nix
git commit -m "Add hosts/mimir/ skeleton: disk-config.nix + configuration.nix"
```

---

## Task 2: Update stale "`hosts/mimir/` ещё не существует" documentation

**Files:**
- Modify: `README.md`
- Modify: `system-plan.md`

**Interfaces:** none — documentation only. Depends on Task 1 having landed (references `docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md`, which already exists regardless, and the new files' names).

- [ ] **Step 1: `README.md` — disk/boot section known-limitations bullet**

Find and replace:

```
- **`hosts/mimir/` (реальный хост) ещё не существует.** Этот раунд работы
  даёт только переиспользуемые, VM-проверенные модули — реальная установка
  на `mimir` (генерация `hardware-configuration.nix`, `hosts/mimir/`,
  `nixos-install`) отдельный, явно запрашиваемый шаг в будущем (см. design
  doc, "Real Install Boundary").
```

with:

```
- **`hosts/mimir/` (реальный хост) существует только как skeleton.**
  `disk-config.nix` + `configuration.nix` составляют переиспользуемые,
  VM-проверенные модули под реальную identity машины (см.
  `docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md`), но
  не зарегистрированы в `flake.nix` и не собираются — реальная установка
  (генерация `hardware-configuration.nix`, регистрация в `flake.nix`,
  `nixos-install`) остаётся отдельным, явно запрашиваемым шагом в будущем
  (см. design doc, "Real Install Boundary").
```

- [ ] **Step 2: `README.md` — Secure Boot section known-limitations bullet**

Find and replace:

```
- **`hosts/mimir/` (реальный хост) всё ещё не существует.** Включение
  `secure-boot.nix` на реальной машине — будущий, явно запрашиваемый шаг,
  наравне с реальным enroll ключей.
```

with:

```
- **`hosts/mimir/configuration.nix` уже импортирует `secure-boot.nix`**
  (см. `docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md`),
  но хост не зарегистрирован в `flake.nix` и не собирается — реальное
  включение на физической машине, наравне с реальным enroll ключей,
  остаётся будущим, явно запрашиваемым шагом.
```

- [ ] **Step 3: `README.md` — desktop-apps known-limitations bullet (groups)**

Find and replace:

```
- **Группы `libvirtd`/`kvm` никому не назначены** — в этом репозитории
  ещё нет реального пользователя (`hosts/mimir/` не существует), назначать
  группы некому. Это шаг реальной установки, не этого модуля.
```

with:

```
- **Группы `libvirtd`/`kvm` никому не назначены** — в этом репозитории
  ещё нет реального пользователя (`hosts/mimir/configuration.nix` не
  объявляет `users.users.*` — см. skeleton design doc), назначать группы
  некому. Это шаг реальной установки, не этого модуля.
```

- [ ] **Step 4: `README.md` — allowUnfree note**

Find and replace:

```
объявляет `nixpkgs.config.allowUnfree = true;` сам — и любой будущий
  реальный хост (`hosts/mimir/`) должен сделать то же самое в своём
  `configuration.nix`, иначе dry-build/сборка упадёт. Подробности —
  `system-plan.md` §2.
```

with:

```
объявляет `nixpkgs.config.allowUnfree = true;` сам — `hosts/mimir/configuration.nix`
  уже делает то же самое в своём skeleton (см.
  `docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md`),
  иначе dry-build/сборка упадёт, когда хост будет зарегистрирован.
  Подробности — `system-plan.md` §2.
```

- [ ] **Step 5: `README.md` — secrets known-limitations bullet**

Find and replace:

```
- **`secrets/secrets.yaml`/`.sops.yaml` пока без реального содержимого** —
  у этого репозитория ещё нет ни одного настоящего получателя
  (`hosts/mimir/` не существует).
```

with:

```
- **`secrets/secrets.yaml`/`.sops.yaml` пока без реального содержимого** —
  у этого репозитория ещё нет ни одного настоящего получателя (`mimir` не
  установлен физически, реального SSH-хост-ключа для `ssh-to-age` пока
  нет, хотя `hosts/mimir/configuration.nix` уже импортирует `secrets.nix`
  — см. skeleton design doc).
```

- [ ] **Step 6: `system-plan.md` §4 — disk/boot paragraph**

Find and replace:

```
(systemd-boot + systemd-initrd). `hosts/mimir/` (реальная целевая машина)
этим модулям пока не построен — это ещё аспирационная структура §3;
проверка идёт через одноразовый VM-хост `hosts/test-disko-luks/`
```

with:

```
(systemd-boot + systemd-initrd). `hosts/mimir/` (реальная целевая машина)
существует как skeleton (`disk-config.nix` + `configuration.nix`, см.
`docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md`) — не
зарегистрирован в `flake.nix` и не собирается без реального
`hardware-configuration.nix`; проверка идёт через одноразовый VM-хост
`hosts/test-disko-luks/`
```

- [ ] **Step 7: `system-plan.md` §6 — secrets known-limitations bullet**

Find and replace:

```
- **`secrets/secrets.yaml`/`.sops.yaml` в этом репозитории пока вообще не
  существуют.** Этот раунд работы не создаёт реального получателя — для
  `ssh-to-age` нужен реальный SSH-хост-ключ реальной машины, а
  `hosts/mimir/` ещё не существует. Создавать `secrets/secrets.yaml`,
  зашифрованный "в никуда" (без единого настоящего получателя), было бы
  пустым жестом — оба файла остаются реально-install-time шагом.
```

with:

```
- **`secrets/secrets.yaml`/`.sops.yaml` в этом репозитории пока вообще не
  существуют.** Этот раунд работы не создаёт реального получателя — для
  `ssh-to-age` нужен реальный SSH-хост-ключ реальной машины, а `mimir` ещё
  не установлен физически (хотя `hosts/mimir/configuration.nix` уже
  импортирует `secrets.nix` как skeleton — см.
  `docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md`).
  Создавать `secrets/secrets.yaml`, зашифрованный "в никуда" (без единого
  настоящего получателя), было бы пустым жестом — оба файла остаются
  реально-install-time шагом.
```

- [ ] **Step 8: Commit**

```bash
git add README.md system-plan.md
git commit -m "Document hosts/mimir/ skeleton: update stale 'does not exist yet' claims"
```
