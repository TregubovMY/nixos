# `modules/home/shell.nix` + `zellij.nix` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the first real `modules/home/*` content — `shell.nix` (zsh + starship + eza + git config) and `zellij.nix` (substituted for `tmux`) — verified with a real build against a throwaway host. Full rationale, including every home-manager option verified against this repo's pinned rev: `docs/superpowers/specs/2026-08-11-shell-zellij-design.md`.

**Architecture:** Two new home-manager modules under `modules/home/`, both plain (no arguments). A throwaway `hosts/test-shell/` host (new, separate from `hosts/test-home-manager/`) wires them in via `home-manager.users.testuser` and proves a real build succeeds.

**Tech Stack:** `zellij`, `eza`, `starship` — all already in `nixpkgs`, all with existing home-manager modules. No new flake input.

## Global Constraints

- No `programs.git.settings.user` (name/email) — real personal identity, deferred to real-install time. See design doc "Deliberately no...".
- No neovim, kitty, direnv, podman, mise — confirmed out of scope for this round, see design doc "Out of Scope".
- Every non-trivial `.nix` file gets WHY-comments per `CLAUDE.md`.
- This sandbox's `install.determinate.systems` substituter is unreachable — always pass `--option substituters "https://cache.nixos.org/" --option extra-substituters ""` on `nix build`/`nix flake check` commands.
- Nix flakes only evaluate git-tracked files — `git add` new files *before* running `nix flake check`/`nix build` on them, not just at the end (hit as a real error in the home-manager round).

---

## Task 1: `modules/home/shell.nix` + `modules/home/zellij.nix`

**Files:**
- Create: `modules/home/shell.nix`
- Create: `modules/home/zellij.nix`

**Interfaces:**
- Produces: two plain home-manager modules (implicit `{ ... }`, no custom arguments) — reference them directly by path from a `home-manager.users.<name>` block's `imports`.
- Consumes (Task 2): imported by `hosts/test-shell/configuration.nix` via `home-manager.users.testuser.imports`.

- [ ] **Step 1: Write `modules/home/shell.nix`**

```nix
# First real modules/home/* content (home-manager dotfiles, not just
# infrastructure) -- zsh + starship + eza + git config/aliases. See
# docs/superpowers/specs/2026-08-11-shell-zellij-design.md "Research
# findings" for the home-manager option details confirmed here (eza's
# auto-generated ls aliases, git's non-obsolete `settings` option,
# starship's auto zsh-integration).
{ ... }:
{
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = true;
    shellAliases = {
      ".." = "cd ..";
      "..." = "cd ../..";
      gs = "git status";
      gc = "git commit";
      gp = "git push";
      gl = "git pull";
      gd = "git diff";
    };
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true; # generates ls/ll/la/lt/lla aliases
      # automatically -- confirmed by reading home-manager's own
      # eza.nix module source at this repo's pinned rev, not assumed.
    git = true; # adds --git to the generated `eza` alias -- shows git
      # status markers (modified/untracked/etc.) inline in listings
  };

  programs.starship.enable = true; # zsh integration auto-enables once
    # programs.zsh.enable = true (confirmed by eval, see design doc) --
    # default prompt preset, no custom starship.toml content yet.

  programs.git = {
    enable = true;
    # programs.git.aliases/extraConfig are obsolete in this repo's
    # pinned home-manager (confirmed via a real eval warning) -- the
    # current, non-obsolete shape is this single `settings` attrset.
    settings = {
      alias = {
        co = "checkout";
        br = "branch";
        st = "status";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
    };
    # Deliberately no settings.user (name/email) -- real personal
    # identity, same real-install-time boundary as SSH/GPG host keys and
    # users.users.* elsewhere in this repo. Git already prompts clearly
    # the first time it's needed without one.
  };
}
```

- [ ] **Step 2: Write `modules/home/zellij.nix`**

```nix
# Zellij, substituted for the `tmux` system-plan.md §3/§5.3 originally
# named -- requested explicitly (newer, more popular multiplexer).
# Zellij's native WASM plugin system covers what tmux needed
# tpm/tmux-resurrect/tmux-continuum for, so no plugin-manager equivalent
# is needed here. See docs/superpowers/specs/
# 2026-08-11-shell-zellij-design.md "Tool substitution".
{ ... }:
{
  programs.zellij = {
    enable = true;
    # Matches the upstream default (false) -- set explicitly so the
    # decision is documented, not silently implicit. Auto-attaching to
    # an existing session on every new shell (what enableZshIntegration
    # turns on) is a common tmux-adjacent surprise; opt-in later if
    # actually wanted.
    enableZshIntegration = false;
  };
}
```

- [ ] **Step 3: Syntax-check**

Run: `nix-instantiate --parse modules/home/shell.nix modules/home/zellij.nix`
Expected: no errors (syntax only — Task 2's real build is the actual eval+activation test).

- [ ] **Step 4: Commit**

```bash
git add modules/home/shell.nix modules/home/zellij.nix
git commit -m "Add modules/home/shell.nix + zellij.nix (zsh/starship/eza/git, zellij not tmux)"
```

---

## Task 2: Throwaway host + real build verification

**Files:**
- Create: `hosts/test-shell/configuration.nix`
- Modify: `flake.nix` (register `nixosConfigurations.test-shell`)

**Interfaces:**
- Consumes: `modules/nixos/boot.nix`, `modules/nixos/home-manager.nix` (both existing, unmodified), `modules/home/shell.nix` + `modules/home/zellij.nix` (Task 1), `home-manager.nixosModules.home-manager` (already a flake input from the home-manager infrastructure round).

- [ ] **Step 1: Write `hosts/test-shell/configuration.nix`**

```nix
# Throwaway verification host for modules/home/shell.nix + zellij.nix --
# NOT a real target machine, and NOT hosts/mimir/. Mirrors
# hosts/test-home-manager/'s shape (ext4 /dev/vda1 + grub, throwaway
# testuser, no qemu-vm.nix) but is a separate host, not an extension of
# it -- keeps hosts/test-home-manager/ as the pure "infra only, no
# content" proof its own header comment already documents, unmutated.
# See docs/superpowers/specs/2026-08-11-shell-zellij-design.md "Testing"
# for why this gets a real build, not just eval/dry-run: unlike the
# Hyprland round, this content has real activation-time behavior
# (dotfiles actually get written).
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
    imports = [
      ../../modules/home/shell.nix
      ../../modules/home/zellij.nix
    ];
    home.stateVersion = "24.05";
  };

  system.stateVersion = "24.05";
}
```

- [ ] **Step 2: Register `nixosConfigurations.test-shell` in `flake.nix`**

After the existing `nixosConfigurations.test-hyprland = ...;` block (ends right before the `# Real, functional verification (not just eval) of the disk/boot` comment that introduces `checks.${system}`), insert:

```nix
      # Throwaway verification host for modules/home/shell.nix +
      # zellij.nix — see docs/superpowers/specs/
      # 2026-08-11-shell-zellij-design.md. Real build (not dry-run), no
      # VM boot — see hosts/test-shell/configuration.nix's own header
      # comment.
      nixosConfigurations.test-shell = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          home-manager.nixosModules.home-manager
          ./hosts/test-shell/configuration.nix
        ];
      };

      # Real, functional verification (not just eval) of the disk/boot
```

- [ ] **Step 3: `git add` the new files so Nix can see them**

Run: `git add hosts/test-shell/configuration.nix flake.nix`

- [ ] **Step 4: Run the eval-only check**

Run: `nix flake check --no-build --option substituters "https://cache.nixos.org/" --option extra-substituters ""`
Expected: passes cleanly, including `nixosConfigurations.test-shell` evaluating without error.

- [ ] **Step 5: Run the real build**

Run: `nix build .#nixosConfigurations.test-shell.config.system.build.toplevel --option substituters "https://cache.nixos.org/" --option extra-substituters ""`
Expected: succeeds — confirms the full activation-script chain (shell aliases, `.gitconfig`, `starship.toml`, zellij config) actually builds.

- [ ] **Step 6: Cleanup**

Run: `rm -f result`

- [ ] **Step 7: Commit**

```bash
git commit -m "Add throwaway test-shell host + real build verification"
```

---

## Task 3: Documentation

**Files:**
- Modify: `README.md`
- Modify: `system-plan.md`

**Interfaces:** none — documentation only.

- [ ] **Step 1: Add a `## Shell и Zellij (modules/home/*)` section to `README.md`**

Insert after the existing `## Hyprland` section (ends right before `## Перевод по хоткею (Crow Translate)`):

```markdown
## Shell и Zellij (modules/home/*)

Первое реальное содержимое `modules/home/*` (home-manager-дотфайлы, не
только инфраструктура) — `modules/home/shell.nix` и
`modules/home/zellij.nix`.

`shell.nix`: zsh (`programs.zsh.autosuggestion`/`syntaxHighlighting`/
`historySubstringSearch` — нативные опции home-manager, отдельный
менеджер плагинов не нужен) + алиасы (`..`, `...`, `gs`/`gc`/`gp`/`gl`/`gd`)
+ eza вместо `ls` (`ll`/`la`/`lt`/`lla` генерируются автоматически через
`programs.eza.enableZshIntegration`) + starship (промпт, zsh-интеграция
включается автоматически) + git (`programs.git.settings` — текущее,
не-obsolete имя опции; алиасы `co`/`br`/`st`, `init.defaultBranch = "main"`,
`pull.rebase = true`). Без `user.name`/`user.email` — это реальная
персональная информация, тот же шаг реальной установки, что и SSH/GPG-
ключи, `users.users.*`.

`zellij.nix`: `programs.zellij.enable = true;` вместо `tmux`
(`system-plan.md` §3/§5.3 изначально называли `tmux` — заменено по
явной просьбе на более новый и популярный инструмент; нативные WASM-плагины
Zellij закрывают то, для чего `tmux` нужны были `tpm`/`tmux-resurrect`/
`tmux-continuum`). `enableZshIntegration = false` — осознанно, чтобы не
подключаться автоматически к существующей сессии в каждом новом шелле.

Проверка — та же глубина, что у home-manager-инфраструктуры (реальная
активация, не только eval):
- `nix flake check --no-build` — eval-only проверка композиции
  (`hosts/test-shell/`, одноразовый хост с тестовым пользователем
  `testuser`).
- `nix build .#nixosConfigurations.test-shell.config.system.build.toplevel`
  — реальная сборка (не dry-run): подтверждает, что весь конфиг реально
  собирается, включая activation-скрипт с настоящими дотфайлами.

### Известные ограничения

- **neovim, kitty, direnv/nix-direnv, podman, mise** (`system-plan.md`
  §5.3) — не в этом раунде. neovim — отдельная, заметно большая задача
  (LazyVim/kickstart.nvim + Ruby-стек); остальные — настоящие пробелы, не
  забыты.
- **Никакой визуальной/интерактивной проверки** — агент не может
  запустить настоящий login-shell и посмотреть, как выглядит промпт или
  работают алиасы интерактивно; это шаг на реальном хосте.
- **`hosts/mimir/`'у некому назначать реальные дотфайлы** — реального
  пользователя всё ещё нет, та же причина, по которой у него нет
  `users.users.*`/`home-manager.users.*`.
```

- [ ] **Step 2: Update `system-plan.md` §3's file tree and status note**

Find (the `tmux.nix` line inside §3's file tree):
```
    tmux.nix
```
Replace with:
```
    zellij.nix                # tmux заменён на Zellij, см. README
```

Find (the current §3 status paragraph):
```
**Статус реализации этой структуры:** `boot.nix`/`disko-luks-btrfs.nix`/
`secure-boot.nix`/`secrets.nix`/`desktop-apps.nix`/`hyprland.nix`
реализованы (см. §4-§6, README); home-manager подключён как
инфраструктура без дотфайлов (см. README, раздел «home-manager»);
`hosts/mimir/` существует как skeleton (см. §4). `modules/home/*`,
`Makefile` — всё ещё аспирационная часть этой структуры, не построены.
```
Replace with:
```
**Статус реализации этой структуры:** `boot.nix`/`disko-luks-btrfs.nix`/
`secure-boot.nix`/`secrets.nix`/`desktop-apps.nix`/`hyprland.nix`
реализованы (см. §4-§6, README); home-manager подключён как
инфраструктура (см. README, раздел «home-manager»), и уже с первым
реальным содержимым — `modules/home/shell.nix` +
`modules/home/zellij.nix` (см. README, раздел «Shell и Zellij»);
`hosts/mimir/` существует как skeleton (см. §4). `modules/home/neovim.nix`
и `Makefile` — всё ещё аспирационная часть этой структуры, не построены.
```

- [ ] **Step 3: Update `system-plan.md` §5.3**

The section currently reads (heading, then one fenced package-list block
— reproduced here as plain text, not nested fences, to keep this step
unambiguous):

> `### 5.3 Терминал / dev-инструменты`, followed by a fenced block whose
> first line is `tmux, tpm, tmux-resurrect, tmux-continuum, vim-tmux-navigator (плагины)`
> and whose `zsh + starship` line ends `"искать готовые решения" из CLAUDE.md`
> (the exact block already shown in full earlier in this repo's
> `system-plan.md` — Task 3 Step 1 of the Hyprland plan touched the
> neighboring §5.2 block the same way, for reference).

Two edits to that block:
1. Add a status line right after the `### 5.3` heading (before the fenced
   block), matching how §5.2 got its own status line in the Hyprland
   round: `**Частично реализовано** в \`modules/home/shell.nix\` +
   \`modules/home/zellij.nix\` (2026-08-11) — zsh+starship+eza+git и
   Zellij (не tmux — см. README, раздел «Shell и Zellij», про замену).
   neovim, kitty, direnv/nix-direnv, podman, mise — ещё нет.`
2. Inside the fenced block, replace only the first line —
   `tmux, tpm, tmux-resurrect, tmux-continuum, vim-tmux-navigator (плагины)`
   — with `zellij (вместо tmux — нативные WASM-плагины, отдельный
   tpm/tmux-resurrect/tmux-continuum не нужен)`, and replace the
   `zsh + starship ...` three-line entry (`zsh + starship (промпт) +
   плагины ... из CLAUDE.md`) with: `zsh + starship (промпт) + плагины
   (автодополнение, подсветка синтаксиса, поиск по истории) —
   реализовано через нативные home-manager опции
   (programs.zsh.autosuggestion/syntaxHighlighting/historySubstringSearch),
   отдельный менеджер плагинов не понадобился`. Every other line in the
   block (`neovim ...`, `kitty ...`, `direnv ...`, `podman ...`, `mise
   ...`) stays exactly as-is.

- [ ] **Step 4: Commit**

```bash
git add README.md system-plan.md
git commit -m "Document modules/home/shell.nix + zellij.nix, correct tmux->zellij in system-plan.md"
```
