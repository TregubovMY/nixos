# Crow Translate Hotkey Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up Crow Translate (an existing, actively-maintained translator app already packaged in nixpkgs) so a Hyprland hotkey translates the current text selection, replacing the earlier custom scratchpad-terminal design.

**Architecture:** No custom application code is needed — `pkgs.crow-translate` is used as-is. Two pieces: (1) an autostart launch of Crow Translate at Hyprland session start (it needs to be running for its D-Bus service to be callable), and (2) a Hyprland bind calling its documented D-Bus method (`io.crow_translate.CrowTranslate` / `/io/crow_translate/CrowTranslate/MainWindow` / `translateSelection()`) to translate the current selection on hotkey press. This replaces `system-plan.md` §5.11's original scratchpad-terminal design — see that section for the updated writeup. **Update 2026-08-08:** written directly in Hyprland's Lua config format (`hyprland.lua`), not the classic hyprlang `.conf` — see the "Superseded" note under Task 2 below for why.

**Tech Stack:** nixpkgs `crow-translate`, D-Bus (`gdbus` or `dbus-send` — verify which is available/idiomatic in Task 1), Hyprland Lua config (`hl.on`/`hl.bind`, see Task 2).

## Global Constraints

- Verify the `crow-translate` package name in nixpkgs before use (`nix search nixpkgs crow-translate`) — per `CLAUDE.md`'s "search before inventing" rule. Do not write a custom derivation; it's already packaged.
- Before writing the Hyprland config snippet, check current Hyprland syntax against https://wiki.hypr.land (per `CLAUDE.md` — syntax changes across versions; note the domain — `wiki.hyprland.org` is stale, the project moved to `wiki.hypr.land`).
- Wayland has no native global-shortcut API — this is why the D-Bus method + Hyprland's own bind-to-shell-command mechanism is the integration point, not a "global hotkey" registered by the app itself. Don't try to configure Crow Translate's own (X11-only) hotkey settings.
- The agent cannot visually verify Hyprland behavior — the snippet's actual runtime correctness (hotkey fires, translation popup appears, text selection is correctly picked up) is a **mandatory flagged manual follow-up**, not something to silently assume works — same pattern as the `agent-sandbox` plan's `--gui` flag.
- Every non-trivial shell/Nix/Lua file gets WHY-comments per `CLAUDE.md`.

---

## File Structure

```
hypr/quick-translate.lua    # autostart + bind snippet (Lua — hyprlang .conf is deprecated as of Hyprland 0.55, see Task 2)
README.md                   # usage docs + manual-verification checklist
```

No `flake.nix`/package derivation needed — `crow-translate` is a plain nixpkgs package, referenced by name wherever the real host's package list eventually lives (not yet built — see `system-plan.md` §3). This plan only produces the Hyprland integration snippet and docs; the actual `environment.systemPackages`/home-manager package-list addition is a one-line change deferred to whoever wires up the real host.

---

## Task 1: Verify the package and the D-Bus invocation

**Files:** none — verification only, informs Task 2's exact command.

- [ ] **Step 1: Confirm the package**

Run: `nix search nixpkgs crow-translate`
Expected: resolves to `crow-translate` (confirm the exact attribute name printed — use it verbatim in Task 2 if different).

- [ ] **Step 2: Confirm the D-Bus call tool and method**

Check whether `gdbus` (part of `glib`, commonly present) or `dbus-send` is more appropriate/available in this environment — either works, prefer whichever is already a dependency of something already in the package list to avoid adding a new one gratuitously (check `nix search nixpkgs glib`/`dbus` and system-plan.md's existing package list for hints; if unclear, `gdbus` is the more common modern choice).

The documented D-Bus target (verified via crow-translate's own docs — do not re-derive from scratch, but do sanity-check it's still current for whatever version `nix search` resolved in Step 1):
- Service: `io.crow_translate.CrowTranslate`
- Object path: `/io/crow_translate/CrowTranslate/MainWindow`
- Method: `translateSelection` (interface `io.crow_translate.CrowTranslate.MainWindow`)

Example `gdbus` invocation to verify the syntax (don't run this yet — Crow Translate isn't installed in this dev sandbox, this is just to confirm you have the right command shape before writing Task 2's config):
```bash
gdbus call --session \
  --dest io.crow_translate.CrowTranslate \
  --object-path /io/crow_translate/CrowTranslate/MainWindow \
  --method io.crow_translate.CrowTranslate.MainWindow.translateSelection
```

- [ ] **Step 3: No commit needed**

Pure verification — informs Task 2's exact snippet content.

---

## Task 2: Hyprland config snippet

> **Superseded 2026-08-08:** this task originally shipped `hypr/quick-translate.conf`
> in classic hyprlang syntax (commit `cdb1c4e`). Hyprland 0.55 (released 2026-05-09)
> deprecated hyprlang in favor of a Lua config, with hyprlang support slated to be
> dropped within 1-2 more releases; since this repo had no existing Hyprland config to
> stay consistent with, the controller rewrote this directly as `hypr/quick-translate.lua`
> (commit `a7b04ec`), verified against `hyprwm/Hyprland`'s own `example/hyprland.lua` and
> wiki.hypr.land rather than assumed. The task body below is kept as historical record of
> the original (now superseded) brief — Task 3 below has been updated to reference the
> `.lua` file.

**Files:**
- Create: `hypr/quick-translate.conf`

**Interfaces:**
- Consumes: `crow-translate` binary (assumed present on `PATH` once installed on the real host — not built by this plan, see File Structure note above) and the D-Bus command confirmed in Task 1.

- [ ] **Step 1: Look up current Hyprland exec-once/bind syntax**

Check https://wiki.hyprland.org for current `exec-once` and `bind` syntax (per `CLAUDE.md` — confirm it matches what's used below, correct if the docs show something different, and note any correction in your report).

- [ ] **Step 2: Write the snippet**

Create `hypr/quick-translate.conf` (adjust the exact `gdbus`/`dbus-send` command if Task 1 found a different tool, and adjust syntax if Step 1's research found the below stale — note any correction in your report):

```
# Crow Translate hotkey integration — see system-plan.md §5.11 and
# docs/superpowers/plans/2026-08-04-translation-utility.md. Source this
# file from your main hyprland.conf: `source = ~/nixos/hypr/quick-translate.conf`
# (path depends on where this repo is checked out).
#
# Wayland has no global-shortcut API of its own — Crow Translate's D-Bus
# method is the documented integration point for compositors like
# Hyprland that can bind arbitrary shell commands to keys (unlike GNOME,
# which needs its own separate global-shortcuts D-Bus portal setup).

# Crow Translate needs to be running for its D-Bus service to answer —
# launch it hidden/minimized-to-tray at session start rather than
# requiring a manual launch before the hotkey works.
exec-once = crow-translate

# Translate the current text selection on hotkey press.
bind = $mainMod, T, exec, gdbus call --session --dest io.crow_translate.CrowTranslate --object-path /io/crow_translate/CrowTranslate/MainWindow --method io.crow_translate.CrowTranslate.MainWindow.translateSelection
```

- [ ] **Step 3: Commit**

```bash
git add hypr/quick-translate.conf
git commit -m "Add Hyprland D-Bus keybind for Crow Translate"
```

---

## Task 3: README + mandatory manual-verification checklist

**Files:**
- Create: `README.md` (or extend, if one already exists in this worktree from another plan)

**Interfaces:** none — documentation only.

- [ ] **Step 1: Write usage docs and the flagged manual-verification checklist**

Add to `README.md`:

```markdown
## Перевод по хоткею (Crow Translate)

Вместо самописного скрипта — готовое, поддерживаемое приложение
[Crow Translate](https://github.com/crow-translate/crow-translate)
(`crow-translate` в nixpkgs). `mainMod+T` переводит текущее выделение
текста через D-Bus-вызов `translateSelection` — Wayland не даёт
регистрировать глобальные хоткеи напрямую, поэтому переводом управляет
сам Hyprland-бинд, а не хоткей внутри приложения. Детали и почему выбрано
именно это решение (а не самописный скрипт) — system-plan.md §5.11.

Подключение: `require("quick-translate")` из основного `hyprland.lua`
(файл должен быть виден на Lua config path Hyprland — например, скопирован
или засимлинкован в `~/.config/hypr/`). Конфиг написан в Lua, а не в
классическом hyprlang `.conf` — начиная с Hyprland 0.55 (вышел
2026-05-09) `.conf`-формат deprecated и будет убран через 1-2 релиза, а
в этом репозитории ещё нет ни одного Hyprland-конфига, с которым нужно
было бы оставаться согласованным, так что смысла писать в устаревающем
формате не было. Приложение должно быть в списке пакетов (`crow-translate`
из nixpkgs) — добавляется туда, когда появится реальный список пакетов
хоста (см. system-plan.md §3).

### Известные ограничения

Hyprland-конфиг (`hypr/quick-translate.lua`) **не проверялся визуально**
— у агента нет возможности "посмотреть глазами" на Hyprland (см.
CLAUDE.md). Перед тем как полагаться на это в реальной работе, нужно
вручную проверить на настоящем десктопе:
- `crow-translate` действительно запускается при старте Hyprland
  и его D-Bus-сервис отвечает;
- `mainMod+T` при выделенном тексте (в любом приложении) реально
  вызывает перевод и показывает окно с результатом;
- нет конфликта хоткея `mainMod+T` с чем-то ещё уже забинженным;
- `require("quick-translate")` из основного `hyprland.lua` реально находит
  и загружает файл (зависит от того, куда именно скопирован/засимлинкован
  этот репозиторий на реальной машине).

В отличие от исходной задумки (терминал со скролбэком всех переводов),
Crow Translate показывает попап с текущим переводом, а не историю —
это осознанный компромисс (см. коммит "Pivot away from custom
quick-translate.sh to Crow Translate").
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Document Crow Translate hotkey usage and manual-verification checklist"
```
