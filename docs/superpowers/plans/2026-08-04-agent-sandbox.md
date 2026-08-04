# Agent Sandbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `claude-code`/`opencode` run against a real project (with internet access, a visible browser, and per-project language versions via `mise`) inside a disposable rootless-Podman container, so a misbehaving agent can't touch files, secrets, or processes outside that one project.

**Architecture:** A single Nix-built container image (`agent-sandbox:latest`) holds `mise`, the agent CLIs, git/curl/ripgrep, and Chromium + Wayland client libs — but no pinned language runtimes; those come from `mise install` reading the mounted project's own `.tool-versions`/`mise.toml` at container start. A thin bash wrapper (`bin/agent-sandbox`) runs `podman run --rm` with only the target project directory bind-mounted (`--userns=keep-id` so file ownership matches the host user), default bridge networking (deliberately unrestricted — see Global Constraints), and an optional `--gui` flag that passes through the host's Wayland socket and `/dev/dri` so the agent's browser is visible on the desktop.

**Tech Stack:** Nix flakes, `pkgs.dockerTools.buildLayeredImage`, rootless Podman, `mise`, bash.

## Global Constraints

- No egress network restriction on the sandbox — full internet is intentional (design decision from `system-plan.md` §9.2/§9.6), don't add an allowlist/proxy.
- Only the project directory is ever bind-mounted into the container — never `$HOME`, never `secrets/secrets.yaml`, never another project's directory.
- Language/runtime versions (ruby, node, ...) are never hardcoded into the image — always resolved by `mise` from the project's own config at container start.
- Before any build step that downloads/builds Chromium or the full image (large — plausibly 1–2GB), check `df -h` per `CLAUDE.md`'s "Дисковый бюджет при разработке": if projected free space after the build would drop below ~5GB, run `nix-collect-garbage -d` first, and if still tight, stop and ask the user rather than proceeding.
- Every non-trivial `.nix`/shell file gets comments explaining *why*, per `CLAUDE.md`'s "Комментарии и документация в коде" — not what the code does, but why this approach (link to source docs/issues where a technique came from an external reference).
- This plan intentionally does **not** touch `hosts/`, `disko`, `luks`, or the rest of the host system — those are a separate, not-yet-brainstormed subsystem. This flake starts minimal (just enough to build the sandbox image) and is expected to be merged into the fuller host flake later.

---

## File Structure

```
flake.nix                                  # minimal flake: nixpkgs input, one package output
modules/nixos/packages/agent-sandbox.nix   # image derivation (pure function: { pkgs } -> derivation)
bin/agent-sandbox                          # bash wrapper: podman run invocation
README.md                                  # usage docs (new file if none exists yet)
```

`modules/nixos/packages/agent-sandbox.nix` is deliberately a plain `{ pkgs }: ...` function, not a NixOS module with `options`/`config` — it only needs to produce a package, not configure a running system, so a module wrapper would be needless ceremony (YAGNI). If a later plan wires this into `hosts/<host>/configuration.nix` as an installed system package, that's a one-line `environment.systemPackages` addition at that point, not something to speculatively build now.

---

## Task 1: Container image derivation + flake scaffold

**Files:**
- Create: `flake.nix`
- Create: `modules/nixos/packages/agent-sandbox.nix`

**Interfaces:**
- Produces: `modules/nixos/packages/agent-sandbox.nix` exports a function `{ pkgs }: <derivation>` building an OCI/Docker image tarball. `flake.nix` exposes it as `packages.x86_64-linux.agent-sandbox-image`.

- [ ] **Step 1: Check disk headroom before the build**

Run: `df -h /`
Expected: free space comfortably above 5GB after accounting for ~1-2GB the Chromium download/build may need. If it's tight, run `nix-collect-garbage -d` first per `CLAUDE.md`.

- [ ] **Step 2: Write the image derivation**

Create `modules/nixos/packages/agent-sandbox.nix`:

```nix
# Podman image for sandboxed AI coding agents (claude-code/opencode).
# Design: system-plan.md §9. Language runtimes (ruby/node/...) are
# deliberately NOT baked in here — mise resolves them per-project at
# container start (see the entrypoint below), so this image stays
# generic across every project instead of needing a rebuild per stack.
{ pkgs }:

let
  # podman's `--userns=keep-id` runs the container's process under the
  # *host* uid — but this minimal image's /etc/passwd only knows about
  # the uid baked in at build time, so tools that call getpwuid() (git,
  # bash prompt, mise) fail with "I have no name!" for any other host
  # uid. Standard fix: synthesize the missing /etc/passwd entry for
  # whatever uid we're actually running as, before doing anything else.
  # Verify this is still the recommended approach before relying on it —
  # see CLAUDE.md "Искать готовые решения" — nixpkgs' dockerTools gains
  # new helpers for this periodically (e.g. `dockerTools.fakeNss`).
  entrypoint = pkgs.writeShellScript "agent-sandbox-entrypoint" ''
    set -euo pipefail

    if ! getent passwd "$(id -u)" > /dev/null 2>&1; then
      echo "agent:x:$(id -u):$(id -g)::/home/agent:${pkgs.bashInteractive}/bin/bash" >> /etc/passwd
    fi

    export HOME=/home/agent
    export MISE_DATA_DIR=/home/agent/.local/share/mise
    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

    cd /workspace
    # Only run mise install if the project actually pins versions —
    # an agent working on a non-mise project shouldn't wait on this.
    if [ -f .tool-versions ] || [ -f mise.toml ] || [ -f .mise.toml ]; then
      mise install
    fi

    if [ "$#" -eq 0 ]; then
      exec ${pkgs.bashInteractive}/bin/bash -l
    else
      exec "$@"
    fi
  '';
in
pkgs.dockerTools.buildLayeredImage {
  name = "agent-sandbox";
  tag = "latest";

  contents = with pkgs; [
    bashInteractive
    coreutils
    gitMinimal
    curl
    ripgrep
    mise
    cacert
    claude-code
    opencode
    chromium
    dockerTools.usrBinEnv
    dockerTools.binSh
  ];

  extraCommands = ''
    mkdir -p home/agent tmp
    chmod 1777 tmp
  '';

  config = {
    Entrypoint = [ "${entrypoint}" ];
    WorkingDir = "/workspace";
  };
}
```

- [ ] **Step 3: Write the flake scaffold**

Create `flake.nix`:

```nix
{
  # Minimal flake scoped to the agent-sandbox package only. Not yet
  # merged with the host flake (disko/hyprland/hosts) — that's a
  # separate, not-yet-designed subsystem (see system-plan.md).
  description = "agent-sandbox: podman-песочница для AI coding agents";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
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
      packages.${system}.agent-sandbox-image =
        import ./modules/nixos/packages/agent-sandbox.nix { inherit pkgs; };
    };
}
```

- [ ] **Step 4: Verify the flake evaluates**

Run: `nix flake check`
Expected: no errors (this flake has no NixOS configurations or hosts to check yet, so this mostly validates syntax).

- [ ] **Step 5: Build the image**

Run: `nix build .#agent-sandbox-image -L`
Expected: succeeds, produces `./result` (a `.tar.gz` OCI image). This is the expensive step from the Global Constraints disk check — if it fails partway with an out-of-space error, run `nix-collect-garbage -d` and retry once; if it fails again, stop and report rather than retrying indefinitely.

- [ ] **Step 6: Commit**

```bash
git add flake.nix modules/nixos/packages/agent-sandbox.nix
git commit -m "Add agent-sandbox container image derivation"
```

---

## Task 2: Verify the image actually works (not just builds)

**Files:** none new — this task exercises Task 1's output.

**Interfaces:**
- Consumes: `./result` from Task 1 (the built image tarball), `agent-sandbox:latest` image name/tag baked into it.

Building successfully doesn't prove the entrypoint's `/etc/passwd` workaround, `mise`, or TLS certs actually work at runtime — this task is the gate for that. Podman isn't installed on this dev machine yet, so use `nix shell` rather than a permanent install.

- [ ] **Step 1: Load the image into podman**

Run: `nix shell nixpkgs#podman --command podman load -i ./result`
Expected: output ends with `Loaded image: agent-sandbox:latest`.

- [ ] **Step 2: Verify the uid workaround works for a non-default uid**

Run: `nix shell nixpkgs#podman --command podman run --rm --user 12345:12345 agent-sandbox:latest whoami`
Expected: prints `agent` (proves the `/etc/passwd` synthesis in the entrypoint works for an arbitrary uid, which is what `--userns=keep-id` will present on the real host later).

- [ ] **Step 3: Verify the agent CLIs and mise are on PATH**

Run: `nix shell nixpkgs#podman --command podman run --rm agent-sandbox:latest bash -lc 'mise --version && claude --version && opencode --version'`
Expected: all three print a version string, no "command not found".

- [ ] **Step 4: Verify outbound TLS works (cacert wiring)**

Run: `nix shell nixpkgs#podman --command podman run --rm agent-sandbox:latest curl -sS -o /dev/null -w '%{http_code}\n' https://example.com`
Expected: `200`. A cert error here means `SSL_CERT_FILE`/`cacert` is wired wrong — fix in `modules/nixos/packages/agent-sandbox.nix` before moving on.

- [ ] **Step 5: No commit needed**

This task only ran verification commands against Task 1's artifact — nothing new to commit. If any step above failed and required a fix to `agent-sandbox.nix`, go back, amend that fix, re-run Step 5 of Task 1 to rebuild, then re-run this task's steps, and commit the fix with `git commit -m "Fix agent-sandbox image: <what was wrong>"`.

---

## Task 3: `bin/agent-sandbox` wrapper script

**Files:**
- Create: `bin/agent-sandbox`

**Interfaces:**
- Consumes: `agent-sandbox:latest` image (Task 1/2).
- Produces: a `podman run` invocation other tasks (Task 4's `--gui` handling) extend — keep the argument-building as a bash array (`args=(...)`) so Task 4 can append to it rather than rewriting the command line.

- [ ] **Step 1: Write the wrapper**

Create `bin/agent-sandbox`:

```bash
#!/usr/bin/env bash
# Wrapper around `podman run` for the agent-sandbox image. Only the
# target project directory is ever mounted in — see system-plan.md §9.2
# for why (blast-radius containment between projects, not a network
# security boundary — networking is deliberately left open).
set -euo pipefail

usage() {
  echo "Usage: agent-sandbox [--gui] <project-dir> [-- command...]" >&2
  exit 1
}

gui=0
if [ "${1:-}" = "--gui" ]; then
  gui=1
  shift
fi

project_dir="${1:-}"
[ -n "$project_dir" ] || usage
shift

# Resolve to an absolute path so relative paths like "." work regardless
# of where agent-sandbox is invoked from.
project_dir="$(cd "$project_dir" && pwd)"

# Per-project cache volume name, so two different projects' agent
# session/index caches never collide or leak into each other.
project_hash="$(printf '%s' "$project_dir" | sha256sum | cut -c1-12)"

args=(
  podman run --rm -it
  --userns=keep-id
  -v "$project_dir:/workspace"
  -v "agent-mise:/home/agent/.local/share/mise"
  -v "agent-cache-$project_hash:/home/agent/.cache"
  --network=bridge
)

if [ "$gui" = 1 ]; then
  # shellcheck disable=SC1091
  source "$(dirname "$0")/agent-sandbox-gui.sh"
fi

args+=(agent-sandbox:latest "$@")

exec "${args[@]}"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x bin/agent-sandbox`

- [ ] **Step 3: Verify project mount + correct file ownership**

```bash
mkdir -p /tmp/agent-sandbox-smoketest
echo "before" > /tmp/agent-sandbox-smoketest/file.txt
PATH="$PWD/bin:$(nix eval --raw nixpkgs#podman.outPath)/bin:$PATH" \
  ./bin/agent-sandbox /tmp/agent-sandbox-smoketest -- bash -c 'echo after > /workspace/file.txt'
```

(If `podman` isn't on `PATH` yet, run the whole block inside `nix shell nixpkgs#podman` instead of the `PATH=` trick above.)

Run: `cat /tmp/agent-sandbox-smoketest/file.txt && stat -c '%U' /tmp/agent-sandbox-smoketest/file.txt`
Expected: prints `after`, and the owner is your own host username, not `root` or some arbitrary uid — this is what `--userns=keep-id` is supposed to guarantee.

- [ ] **Step 4: Verify network is reachable from inside**

Run: `./bin/agent-sandbox /tmp/agent-sandbox-smoketest -- curl -sS -o /dev/null -w '%{http_code}\n' https://example.com`
Expected: `200`.

- [ ] **Step 5: Clean up the smoke-test scratch dir**

Run: `rm -rf /tmp/agent-sandbox-smoketest`

- [ ] **Step 6: Commit**

```bash
git add bin/agent-sandbox
git commit -m "Add agent-sandbox wrapper script"
```

---

## Task 4: `--gui` flag (Wayland/GPU passthrough)

**Files:**
- Create: `bin/agent-sandbox-gui.sh`
- Modify: `bin/agent-sandbox` (already sources this file when `--gui` is passed — no further edit needed unless Step 1 below reveals otherwise)

**Interfaces:**
- Consumes: the `args=(...)` bash array from `bin/agent-sandbox` (this script appends to it, since it's `source`d into the same shell scope).

- [ ] **Step 1: Write the GUI passthrough logic**

Create `bin/agent-sandbox-gui.sh`:

```bash
# Sourced (not executed) from bin/agent-sandbox when --gui is passed.
# Appends Wayland socket + GPU device passthrough to the `args` array
# already being built by the caller.
if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo "agent-sandbox --gui: no active Wayland session detected" \
       "(XDG_RUNTIME_DIR/WAYLAND_DISPLAY unset) — run without --gui," \
       "or from inside your Hyprland session." >&2
  exit 1
fi

wayland_socket="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
if [ ! -S "$wayland_socket" ]; then
  echo "agent-sandbox --gui: $wayland_socket is not a socket" >&2
  exit 1
fi

args+=(
  --device /dev/dri
  -e "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
  -e "XDG_RUNTIME_DIR=/run/user/host"
  -v "$wayland_socket:/run/user/host/$WAYLAND_DISPLAY"
)
```

- [ ] **Step 2: Verify the error path (this dev machine has no active Wayland session yet)**

Run: `./bin/agent-sandbox --gui /tmp || true` (any project dir is fine — it should fail before even validating the dir)
Expected: prints the "no active Wayland session detected" message and exits non-zero — proves the guard works, without needing a real compositor here.

- [ ] **Step 3: Note the deferred real-world check**

This step cannot be fully verified on the current dev machine (no Hyprland/Wayland session is running here yet, per earlier `df`/environment check). Record in the task/PR notes: "Manual follow-up once Hyprland is running on real hardware: run `agent-sandbox --gui <project-dir> -- chromium https://example.com` and confirm a visible browser window appears." Do not mark this task fully done without that manual confirmation eventually happening — flag it to the user rather than silently assuming it works.

- [ ] **Step 4: Commit**

```bash
git add bin/agent-sandbox-gui.sh
git commit -m "Add --gui Wayland/GPU passthrough to agent-sandbox"
```

---

## Task 5: README documentation

**Files:**
- Create: `README.md` (none exists yet — the old one is in `.trash/`, not reused, since the whole structure changed)

**Interfaces:** none — documentation only.

- [ ] **Step 1: Write the README**

Create `README.md`:

```markdown
# nixos

Переносимая NixOS-конфигурация: disko + LUKS, systemd-boot/Secure Boot,
Hyprland, home-manager, sops-nix. Полное описание архитектуры и решений —
`system-plan.md`. Инструкции для агента, работающего в этом репозитории —
`CLAUDE.md`.

## Песочница для AI-агентов (agent-sandbox)

`claude-code`/`opencode` не запускаются напрямую на хосте против реального
проекта — вместо этого используется песочница: короткоживущий rootless
Podman-контейнер, в который смонтирована только директория проекта.
Почему так — `system-plan.md` §9.

### Использование

```bash
bin/agent-sandbox ~/code/myproject          # интерактивный shell в /workspace
bin/agent-sandbox ~/code/myproject -- claude # сразу запустить claude-code
bin/agent-sandbox --gui ~/code/myproject     # + видимое окно браузера на десктопе
```

Версии ruby/node/etc берутся из `.tool-versions`/`mise.toml` самого
проекта через `mise install`, который выполняется автоматически при
старте контейнера — ничего не нужно ставить вручную.

### IDE

Никакого remote-forwarding настраивать не нужно: контейнер монтирует ту
же директорию проекта (bind-mount, не копия), так что RubyMine/VSCode на
хосте открывают `~/code/myproject` как обычно и видят те же файлы на
диске. Изолируется процесс выполнения агента и его сеть, а не файлы,
которые ты редактируешь.

### `--gui`

Нужна активная Wayland-сессия (Hyprland) на хосте — флаг пробрасывает
`WAYLAND_DISPLAY`-сокет и `/dev/dri`, чтобы, например, Chromium внутри
контейнера открыл окно, видимое на твоём десктопе. Без активной
Wayland-сессии команда сразу завершится с понятной ошибкой.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Add README with agent-sandbox usage docs"
```

---

## Task 6: End-to-end scenario test

**Files:** none new — full-stack verification of Tasks 1–5 together against a realistic project.

**Interfaces:**
- Consumes: `bin/agent-sandbox` (Task 3), `agent-sandbox:latest` image (Task 1).

- [ ] **Step 1: Build a minimal scratch Ruby project with a pinned version**

```bash
mkdir -p /tmp/agent-sandbox-e2e
cd /tmp/agent-sandbox-e2e
git init -q
echo "ruby 3.3.0" > .tool-versions
echo "puts RUBY_VERSION" > check.rb
cd -
```

- [ ] **Step 2: Run the sandbox against it and confirm mise resolved the pinned version**

Run: `./bin/agent-sandbox /tmp/agent-sandbox-e2e -- ruby check.rb`
Expected: prints `3.3.0`. (First run will take longer — `mise install` is compiling/downloading that Ruby version into the shared `agent-mise` volume.)

- [ ] **Step 3: Confirm the mise cache volume persists across runs**

Run: `time ./bin/agent-sandbox /tmp/agent-sandbox-e2e -- ruby check.rb`
Expected: prints `3.3.0` again, noticeably faster than Step 2 (no re-install — proves the `agent-mise` named volume is actually being reused, not just re-populated each run).

- [ ] **Step 4: Confirm project isolation — a second unrelated project doesn't see the first project's files**

```bash
mkdir -p /tmp/agent-sandbox-e2e-2
echo "isolated" > /tmp/agent-sandbox-e2e-2/marker.txt
./bin/agent-sandbox /tmp/agent-sandbox-e2e-2 -- ls /workspace
```
Expected: lists only `marker.txt` — not `check.rb`/`.tool-versions` from the first project.

- [ ] **Step 5: Clean up scratch dirs and test volumes**

```bash
rm -rf /tmp/agent-sandbox-e2e /tmp/agent-sandbox-e2e-2
nix shell nixpkgs#podman --command podman volume rm agent-mise \
  "agent-cache-$(printf '%s' /tmp/agent-sandbox-e2e | sha256sum | cut -c1-12)" \
  "agent-cache-$(printf '%s' /tmp/agent-sandbox-e2e-2 | sha256sum | cut -c1-12)" 2>/dev/null || true
```

- [ ] **Step 6: No commit needed**

Pure verification task — if any step fails, go back to the relevant earlier task, fix, recommit there, and re-run this task from Step 1.
