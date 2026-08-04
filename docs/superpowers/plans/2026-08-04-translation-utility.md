# Quick-Translate Utility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A hotkey-toggled Hyprland scratchpad terminal running an interactive translation loop (`quick-translate.sh`, via `translate-shell`), matching `system-plan.md` §5.11.

**Architecture:** Two independently-testable pieces: (1) a plain bash script with real, unit-testable logic (direction detection, translation loop), packaged as a Nix derivation (`pkgs.writeShellApplication`) so `translate-shell`/`wl-clipboard` are on its `PATH` declaratively; (2) a Hyprland config snippet (`windowrulev2` + keybind + special workspace) delivered as a plain `.conf` file meant to be `source`d from the user's real Hyprland config once the fuller Hyprland/home-manager module exists (a separate, not-yet-built subsystem) — its runtime correctness can only be confirmed visually by the user, per `CLAUDE.md`'s stated agent limitation on Hyprland.

**Tech Stack:** bash, `translate-shell` (`trans`), `wl-clipboard` (`wl-copy`), `kitty`, Hyprland `windowrulev2`/`bind`/special workspaces.

## Global Constraints

- Direction detection: Cyrillic input → `ru→en` (`trans -brief :en`), everything else → `en→ru` (`trans -brief :ru`) — per `system-plan.md` §5.11 step 3.
- The script is a persistent loop, not a one-shot popup — stays alive reading lines until the window is closed, translation history stays visible in the terminal's scrollback — per §5.11 (a deliberate earlier design decision, not optional).
- Every translation result is also copied to the clipboard via `wl-copy`, not just printed — per §5.11 step 4.
- Verify `translate-shell` and `wl-clipboard` package names in nixpkgs before use (`nix search nixpkgs translate-shell`, `nix search nixpkgs wl-clipboard`) per `CLAUDE.md`'s "search before inventing" rule — don't assume attribute names from memory.
- Before writing the Hyprland `.conf` snippet, check current Hyprland `windowrulev2`/special-workspace syntax against upstream docs (https://wiki.hyprland.org) — this syntax changes across Hyprland versions, per `CLAUDE.md`.
- Every non-trivial shell/Nix file gets WHY-comments per `CLAUDE.md`.
- The agent cannot visually verify Hyprland behavior — the `.conf` snippet's actual runtime correctness (hotkey toggles the window, sizing/position look right, translation is legible) is a **mandatory flagged manual follow-up**, not something to silently assume works — matches how `--gui` was handled in the `agent-sandbox` plan.

---

## File Structure

```
flake.nix                                  # minimal: nixpkgs input, one package output
modules/nixos/packages/quick-translate.nix # pkgs.writeShellApplication wrapping the script
scripts/quick-translate.sh                 # the actual interactive translate loop (source of truth)
scripts/quick-translate-test.sh            # bash test suite, mocks trans/wl-copy via PATH shadowing
hypr/quick-translate.conf                  # Hyprland windowrulev2 + bind + exec-once snippet
README.md                                  # usage docs + manual-verification checklist
```

`modules/nixos/packages/quick-translate.nix` is a plain `{ pkgs }: derivation`, not a NixOS module — same YAGNI reasoning as `agent-sandbox.nix`: it only needs to produce a package, not configure a running system.

---

## Task 1: `quick-translate.sh` — TDD the translation loop logic

**Files:**
- Create: `scripts/quick-translate.sh`
- Test: `scripts/quick-translate-test.sh`

**Interfaces:**
- Produces: a script reading lines from stdin, writing the translation to stdout per line, calling `wl-copy` with the translation, looping until stdin closes (EOF) or it reads a line consisting of exactly `.exit` (Hyprland can't easily send Ctrl+D to a running script inside a terminal, so an explicit designed exit path matters too — relying only on process signals wouldn't cover how a human actually closes this from a keyboard).

- [ ] **Step 1: Write the failing test**

Create `scripts/quick-translate-test.sh`:

```bash
#!/usr/bin/env bash
# Test harness for quick-translate.sh: shadows `trans` and `wl-copy` with
# fake executables on PATH so the test doesn't need real network access or
# a real Wayland clipboard — verifies the script's own logic (direction
# detection, loop behavior, clipboard-copy call), not translate-shell's or
# wl-clipboard's correctness.
set -euo pipefail

fail() { echo "FAIL: $1" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Fake `trans`: echoes back "[LANG] query" so the test can assert which
# direction the script picked, without hitting the real network.
cat > "$tmp/trans" <<'EOF'
#!/usr/bin/env bash
# Usage in real trans: trans -brief :LANG "text". Args here: -brief :LANG text
lang="${2#:}"
echo "[$lang] $3"
EOF
chmod +x "$tmp/trans"

# Fake `wl-copy`: records what it was given via stdin, so the test can
# assert the translation was actually copied to the clipboard.
cat > "$tmp/wl-copy" <<EOF
#!/usr/bin/env bash
cat > "$tmp/clipboard.txt"
EOF
chmod +x "$tmp/wl-copy"

export PATH="$tmp:$PATH"
script="$(cd "$(dirname "$0")" && pwd)/quick-translate.sh"

# Test 1: Cyrillic input -> ru->en direction
out="$(printf 'привет\n.exit\n' | bash "$script")"
echo "$out" | grep -q '\[en\] привет' || fail "cyrillic input should translate to en, got: $out"

# Test 2: Latin input -> en->ru direction
out="$(printf 'hello\n.exit\n' | bash "$script")"
echo "$out" | grep -q '\[ru\] hello' || fail "latin input should translate to ru, got: $out"

# Test 3: result gets copied to the clipboard
printf 'hello\n.exit\n' | bash "$script" > /dev/null
[ -f "$tmp/clipboard.txt" ] || fail "wl-copy was never called"
grep -q '\[ru\] hello' "$tmp/clipboard.txt" || fail "clipboard content wrong: $(cat "$tmp/clipboard.txt")"

# Test 4: .exit terminates cleanly (script must not hang / must exit 0)
printf '.exit\n' | timeout 5 bash "$script" || fail "script did not exit cleanly on .exit"

# Test 5: EOF (no .exit) also terminates cleanly
printf 'hello\n' | timeout 5 bash "$script" > /dev/null || fail "script did not exit cleanly on EOF"

echo "All tests passed."
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x scripts/quick-translate-test.sh && bash scripts/quick-translate-test.sh`
Expected: FAIL — `scripts/quick-translate.sh: No such file or directory` (script doesn't exist yet).

- [ ] **Step 3: Write the implementation**

Create `scripts/quick-translate.sh`:

```bash
#!/usr/bin/env bash
# Interactive translate loop for the Hyprland scratchpad terminal — see
# system-plan.md §5.11. Persistent (not one-shot): keeps reading lines
# until EOF or an explicit `.exit`, so translation history stays visible
# in the terminal's scrollback across multiple lookups in one session.
set -uo pipefail  # no -e: a single bad `trans` call shouldn't kill the loop

while IFS= read -r line; do
  [ "$line" = ".exit" ] && break
  [ -z "$line" ] && continue

  # Cyrillic present -> assume Russian input, translate to English;
  # otherwise assume English input, translate to Russian. Matches
  # system-plan.md §5.11's stated direction-detection rule.
  if [[ "$line" =~ [а-яА-ЯёЁ] ]]; then
    target=en
  else
    target=ru
  fi

  translation="$(trans -brief ":$target" "$line")"
  echo "$translation"
  printf '%s' "$translation" | wl-copy
done
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/quick-translate-test.sh`
Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add scripts/quick-translate.sh scripts/quick-translate-test.sh
git commit -m "Add quick-translate.sh with TDD-covered direction/loop logic"
```

---

## Task 2: Package via Nix

**Files:**
- Create: `flake.nix`
- Create: `modules/nixos/packages/quick-translate.nix`

**Interfaces:**
- Consumes: `scripts/quick-translate.sh` (Task 1).
- Produces: a `quick-translate` package/executable with `trans` and `wl-copy` guaranteed on its `PATH`.

- [ ] **Step 1: Verify package names in nixpkgs**

```bash
nix search nixpkgs translate-shell
nix search nixpkgs wl-clipboard
```
Expected: both resolve to real attribute names (expected `translate-shell` and `wl-clipboard` — confirm the exact printed names, they're what Step 2 must reference; if either differs, use the printed name instead).

- [ ] **Step 2: Write the package**

Create `modules/nixos/packages/quick-translate.nix`:

```nix
# Wraps scripts/quick-translate.sh as a Nix package so `trans`/`wl-copy`
# are guaranteed present on PATH wherever this is installed, without
# depending on them being separately declared in a host's package list.
{ pkgs }:
pkgs.writeShellApplication {
  name = "quick-translate";
  runtimeInputs = [ pkgs.translate-shell pkgs.wl-clipboard ];
  text = builtins.readFile ../../../scripts/quick-translate.sh;
}
```

- [ ] **Step 3: Write the flake**

Create `flake.nix`:

```nix
{
  description = "quick-translate — Hyprland scratchpad translation utility (see docs/superpowers/plans/2026-08-04-translation-utility.md).";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system}.quick-translate = import ./modules/nixos/packages/quick-translate.nix { inherit pkgs; };
    };
}
```

- [ ] **Step 4: Build and smoke-test**

Run: `nix build .#quick-translate && ./result/bin/quick-translate <<< $'hello\n.exit'`
Expected: prints a Russian translation of "hello" (this is a real network call to whatever backend `trans` defaults to — if this environment has no outbound network, expect a network error here specifically, not "command not found"; a network error still confirms packaging itself is correct even if the live translation can't be reached in a sandboxed dev environment).

- [ ] **Step 5: Commit**

```bash
git add flake.nix modules/nixos/packages/quick-translate.nix
git commit -m "Package quick-translate as a Nix flake output"
```

---

## Task 3: Hyprland config snippet

**Files:**
- Create: `hypr/quick-translate.conf`

**Interfaces:**
- Consumes: `quick-translate` package (Task 2) — the terminal's exec-once launches it inside a `kitty` instance tagged with a distinct class.

- [ ] **Step 1: Look up current Hyprland windowrulev2/special-workspace syntax**

Before writing the snippet, check https://wiki.hyprland.org for the current `windowrulev2`, `exec-once`, and special-workspace (`togglespecialworkspace`) syntax — it has changed across Hyprland versions (per `CLAUDE.md`). Confirm: (a) how to give a `kitty` window a distinguishing class/app-id (kitty's `--class` flag or `-o` override), (b) current `windowrulev2` syntax for float/size/position + `workspace special:<name> silent`, (c) current bind syntax for `togglespecialworkspace`.

- [ ] **Step 2: Write the snippet**

Create `hypr/quick-translate.conf` (adjust exact flag/syntax names if Step 1's research found the below stale — this is a best-effort starting point, not gospel; note any correction made in the task report):

```
# Quick-translate scratchpad terminal — see system-plan.md §5.11 and
# docs/superpowers/plans/2026-08-04-translation-utility.md. Source this
# file from your main hyprland.conf: `source = ~/nixos/hypr/quick-translate.conf`
# (path depends on where this repo is checked out).

# Launch hidden in the special workspace at Hyprland startup, so the first
# hotkey press is instant instead of waiting for kitty+the script to boot.
exec-once = [workspace special:magic silent] kitty --class quick-translate -e quick-translate

# Fixed size/position float window, not tiled — quake-style dropdown feel.
windowrulev2 = float, class:^(quick-translate)$
windowrulev2 = size 800 500, class:^(quick-translate)$
windowrulev2 = move 50%-400 100, class:^(quick-translate)$
windowrulev2 = workspace special:magic silent, class:^(quick-translate)$

# Toggle visibility — same hotkey shows/hides, window and its scrollback
# history stay alive underneath (not closed) between toggles.
bind = $mainMod, T, togglespecialworkspace, magic
```

- [ ] **Step 3: Commit**

```bash
git add hypr/quick-translate.conf
git commit -m "Add Hyprland scratchpad config for quick-translate"
```

---

## Task 4: README + mandatory manual-verification checklist

**Files:**
- Create: `README.md` (or extend, if one already exists in this worktree from another plan)

**Interfaces:** none — documentation only.

- [ ] **Step 1: Write usage docs and the flagged manual-verification checklist**

Add to `README.md`:

```markdown
## Утилита перевода (quick-translate)

Плавающий терминал на Hyprland special workspace `magic` с интерактивным
скриптом перевода внутри — `$mainMod+T` показывает/прячет окно, история
переводов остаётся в скролбэке между вызовами. Детали — system-plan.md §5.11.

Подключение: `source = <путь-до-репо>/hypr/quick-translate.conf` в
основном `hyprland.conf`.

### Известные ограничения

Скрипт (`scripts/quick-translate.sh`) покрыт тестами и собран Nix-пакетом
(`nix build .#quick-translate`) — эта часть проверена. Но Hyprland-конфиг
(`hypr/quick-translate.conf`) **не проверялся визуально** — у агента нет
возможности "посмотреть глазами" на Hyprland (см. CLAUDE.md). Перед тем как
полагаться на это в реальной работе, нужно вручную проверить на настоящем
десктопе:
- `$mainMod+T` действительно показывает/прячет окно нужного размера в
  нужном месте экрана;
- окно не закрывается при повторном нажатии — скрывается, скролбэк не
  теряется;
- вставка текста (Ctrl+Shift+V) и перевод реально работают в реальном
  Wayland-окружении.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Document quick-translate usage and manual-verification checklist"
```
