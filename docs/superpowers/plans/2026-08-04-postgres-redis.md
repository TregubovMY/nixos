# Postgres & Redis Dev Containers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide shared, declarative PostgreSQL 16 and Redis 7 containers for local dev work via `virtualisation.oci-containers` (podman backend), verified end-to-end in a throwaway test VM.

**Architecture:** A minimal, standalone flake (`nixpkgs` only) defines one throwaway `nixosConfiguration` (`test-vm`) used only to verify this feature via `nixos-rebuild build-vm`, mirroring the earlier `agent-sandbox` plan's "minimal flake, merged into the fuller host flake later" pattern — this repo has no real `hosts/` structure yet (a separate, not-yet-planned subsystem). The reusable deliverable is `modules/nixos/dev-databases.nix`, a plain NixOS module exposing both containers.

**Tech Stack:** NixOS flakes, `virtualisation.oci-containers` (podman backend), official `postgres:16` / `redis:7` Docker Hub images.

## Global Constraints

- No Postgres password — `POSTGRES_HOST_AUTH_METHOD=trust` (the official image's supported no-auth mode). This is a local-only dev database bound to `127.0.0.1`; anyone with shell access on the machine already has the disk and everything on it, so password-gating a localhost connection adds no real protection. Decided explicitly to keep this simple — see conversation: sops/age bootstrap was considered and rejected as disproportionate ceremony for a credential with no real threat model.
- Redis: no auth either, same reasoning. Persists to disk via `--save 60 1` (RDB snapshot), not in-memory only — per `system-plan.md` §5.12.
- Both services bound to `127.0.0.1` only, not exposed beyond localhost.
- Container backend is podman (`virtualisation.oci-containers.backend = "podman"`), not docker — matches the rest of this repo's container usage (`agent-sandbox`).
- On the real target host (not yet built), persistent volumes should live under the `/persist` btrfs subvolume per `system-plan.md` §4 — this plan uses plain `/var/lib/dev-{postgres,redis}` on the throwaway test VM instead; the README must say so explicitly as a TODO for whoever wires this into the real host.
- Before `nixos-rebuild build-vm` (pulls `postgres:16` + `redis:7` images, ~500MB combined, plus VM disk overhead), check `df -h` per `CLAUDE.md`'s disk-budget rule: if projected free space would drop under ~5GB, run `nix-collect-garbage -d` first; if still tight, stop and ask.
- Every non-trivial `.nix` file gets WHY-comments (not what-comments) per `CLAUDE.md`.

---

## File Structure

```
flake.nix                          # minimal: nixpkgs input, one nixosConfiguration "test-vm"
modules/nixos/dev-databases.nix    # the reusable module: both oci-containers, no secrets involved
hosts/test-vm/configuration.nix    # throwaway test host: imports dev-databases.nix, build-vm only
README.md                          # usage docs + the /persist TODO for real-host integration
```

`modules/nixos/dev-databases.nix` is deliberately a plain NixOS module (`{ config, pkgs, ... }: { ... }`), not split into separate postgres/redis files — `system-plan.md` §5.12 treats them as one declarative unit sharing the same pattern, and splitting two ~10-line container blocks into separate files would be needless ceremony (YAGNI).

`hosts/test-vm/` is a throwaway verification host, not a real target machine — when the real `hosts/` restructuring plan (disko/LUKS/Secure Boot) happens later, `dev-databases.nix` gets imported into that real host's `configuration.nix` and `hosts/test-vm/` can be deleted.

---

## Task 1: Write `modules/nixos/dev-databases.nix` and the verification flake

**Files:**
- Create: `flake.nix`
- Create: `modules/nixos/dev-databases.nix`

**Interfaces:**
- Produces: `virtualisation.oci-containers.containers.postgres` / `.redis`, importable by any host's `configuration.nix` via `imports = [ ../../modules/nixos/dev-databases.nix ];`.

- [ ] **Step 1: Write the module**

Create `modules/nixos/dev-databases.nix`:

```nix
# Shared local-dev PostgreSQL 16 + Redis 7, declared as podman containers via
# NixOS's virtualisation.oci-containers — see system-plan.md §5.12. One
# instance shared across all local projects (separate DBs/namespaces inside),
# matching how local dev environments with multiple projects are normally
# set up.
{ config, pkgs, ... }:
{
  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers = {
    postgres = {
      image = "postgres:16";
      environment = {
        # No password: this is a localhost-only (see `ports` below) dev
        # database on a single-user machine — anyone with shell access
        # already has the disk and everything on it, so gating a loopback
        # connection with a password adds no real protection, only
        # ceremony (sops/age bootstrap). POSTGRES_HOST_AUTH_METHOD=trust
        # is the image's own officially supported no-auth mode, not a
        # workaround — see https://hub.docker.com/_/postgres "No Password".
        POSTGRES_HOST_AUTH_METHOD = "trust";
      };
      volumes = [ "/var/lib/dev-postgres:/var/lib/postgresql/data" ];
      # Bound to localhost only — this is a local dev convenience service,
      # not meant to be reachable from the network.
      ports = [ "127.0.0.1:5432:5432" ];
    };

    redis = {
      image = "redis:7";
      # --save 60 1: RDB snapshot to disk after >=1 write in 60s, so a
      # container restart doesn't silently lose all cached/queued data —
      # plain in-memory-only defeats the point of a shared dev instance.
      cmd = [ "redis-server" "--save" "60" "1" ];
      volumes = [ "/var/lib/dev-redis:/data" ];
      ports = [ "127.0.0.1:6379:6379" ];
    };
  };

  # oci-containers doesn't create its bind-mount host directories itself;
  # postgres:16's internal `postgres` user is uid/gid 999 on Debian-based
  # images (verify via `podman run --rm postgres:16 id postgres` — check
  # this still holds if bumping the image tag later, Debian base images
  # have changed this uid before). No remap happens (rootful podman), so
  # the host directory must be owned by that same uid for Postgres to be
  # able to write its data directory.
  systemd.tmpfiles.rules = [
    "d /var/lib/dev-postgres 0750 999 999 -"
    "d /var/lib/dev-redis 0750 999 999 -"
  ];
}
```

- [ ] **Step 2: Write the minimal flake**

Create `flake.nix`:

```nix
{
  description = "Postgres/Redis dev containers — standalone verification flake (see docs/superpowers/plans/2026-08-04-postgres-redis.md). Merges into the fuller host flake once hosts/ exists.";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations.test-vm = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./hosts/test-vm/configuration.nix ];
    };
  };
}
```

- [ ] **Step 3: Commit**

```bash
git add flake.nix modules/nixos/dev-databases.nix
git commit -m "Add dev-databases module: declarative Postgres+Redis containers"
```

---

## Task 2: Throwaway test host + `nix flake check`

**Files:**
- Create: `hosts/test-vm/configuration.nix`

**Interfaces:**
- Consumes: `modules/nixos/dev-databases.nix` (Task 1).

- [ ] **Step 1: Write the test host config**

Create `hosts/test-vm/configuration.nix`:

```nix
# Throwaway verification host for the dev-databases module — NOT a real
# target machine. `nixos-rebuild build-vm` generates its own actual VM
# disk/kernel boot path at build-vm time (nixos/modules/virtualisation/
# qemu-vm.nix) and doesn't use these fileSystems/boot.loader values to
# boot the VM — but `nix flake check` (and any plain evaluation of this
# nixosSystem) still runs NixOS's standard assertions, which require
# fileSystems."/" and a bootloader to be declared regardless of which
# build target you're actually going to use. So these are still required
# here even though build-vm itself ignores their real values. Once the
# full hosts/ restructuring (disko/LUKS/Secure Boot, see system-plan.md
# §3-4) exists, import dev-databases.nix into the real host's
# configuration.nix instead (with real fileSystems/disko config) and
# delete this directory.
{ config, pkgs, ... }:
{
  imports = [ ../../modules/nixos/dev-databases.nix ];

  fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
  boot.loader.grub.device = "/dev/vda";

  # Arbitrary but required by NixOS for any system closure to evaluate —
  # doesn't need to track the real nixpkgs channel version for a
  # throwaway VM that's never upgraded in place.
  system.stateVersion = "24.05";
}
```

- [ ] **Step 2: Run `nix flake check`**

Run: `nix flake check`
Expected: passes with no errors — validates module option types before building anything heavy.

- [ ] **Step 3: Commit**

```bash
git add hosts/test-vm/configuration.nix
git commit -m "Add throwaway test-vm host for dev-databases verification"
```

---

## Task 3: `build-vm` verification (Postgres + Redis actually work)

**Files:** none new — this task exercises Tasks 1-2's output.

- [ ] **Step 1: Disk-budget check**

Run: `df -h`
If projected free space after pulling `postgres:16` + `redis:7` (~500MB combined) plus VM overhead would drop under ~5GB, run `nix-collect-garbage -d` first per `CLAUDE.md`.

- [ ] **Step 2: Build and boot the VM**

```bash
nixos-rebuild build-vm --flake .#test-vm
./result/bin/run-test-vm-vm
```

- [ ] **Step 3: Inside the VM, confirm both containers are active**

```bash
systemctl status podman-postgres.service podman-redis.service
systemctl --failed
```
Expected: both `active (running)`, `systemctl --failed` prints nothing.

- [ ] **Step 4: Confirm Postgres accepts trust-auth connections**

```bash
nix shell nixpkgs#postgresql --command psql -h 127.0.0.1 -U postgres -c 'SELECT 1;'
```
Expected: prints a `1` row with no password prompt — confirms `POSTGRES_HOST_AUTH_METHOD=trust` is actually in effect.

- [ ] **Step 5: Confirm Redis responds and persists**

```bash
nix shell nixpkgs#redis --command redis-cli -h 127.0.0.1 PING
nix shell nixpkgs#redis --command redis-cli -h 127.0.0.1 SET smoke-test ok
systemctl restart podman-redis.service
sleep 2
nix shell nixpkgs#redis --command redis-cli -h 127.0.0.1 GET smoke-test
```
Expected: `PONG`, then `OK`, then (after restart) `ok` again — proves `--save 60 1` plus the `/var/lib/dev-redis` volume actually persist data across a container restart, not just in-memory.

- [ ] **Step 6: No commit needed**

Pure verification. If any step fails, fix `modules/nixos/dev-databases.nix` (Task 1), rebuild, and re-run from Step 2 — commit the fix there with `git commit -m "Fix dev-databases: <what was wrong>"`.

---

## Task 4: README

**Files:**
- Create: `README.md` (or extend, if one already exists in this worktree from another plan)

- [ ] **Step 1: Write usage docs**

Add a section to `README.md`:

```markdown
## Postgres/Redis для локальной разработки

Общий Postgres 16 + Redis 7 для всех локальных проектов (декларативные
podman-контейнеры, `modules/nixos/dev-databases.nix`) — поднимаются вместе
с системой, ничего не нужно ставить/поднимать вручную на уровне проекта.

- Postgres: `127.0.0.1:5432`, пользователь `postgres`, **без пароля**
  (`POSTGRES_HOST_AUTH_METHOD=trust`) — локальная машина, БД доступна
  только с localhost, реального смысла в пароле нет.
- Redis: `127.0.0.1:6379`, без аутентификации, по той же причине.
- Данные — в `/var/lib/dev-postgres` / `/var/lib/dev-redis` на тестовом
  хосте этого плана; **на реальной машине переносится в
  `/persist/postgres` / `/persist/redis`** (см. `system-plan.md` §4) —
  поправить пути в `dev-databases.nix` при переносе в `hosts/<host>/`.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Document dev-databases usage"
```
