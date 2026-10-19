# Interactive podman for ad-hoc project containers (system-plan.md §5.3)
# -- distinct from dev-databases.nix's declarative
# virtualisation.oci-containers usage, though both need the same
# underlying virtualisation.podman.enable (safe to set true in both; the
# NixOS module system only errors on *conflicting* values for a plain
# bool option, not identical ones set by multiple modules).
{ config, lib, pkgs, ... }:
{
  virtualisation.podman.enable = true;

  # docker/docker-compose for project repos that ship a docker-compose.yml
  # and expect the real Docker CLI/socket -- asked live 2026-10-19. Not a
  # second container engine (dockerd): podman already implements the
  # Docker Engine API, so this just exposes it the way Docker tooling
  # expects, instead of running two daemons/storage backends side by side
  # for the same job.
  #   dockerCompat: aliases the `docker` command itself to `podman`.
  #   dockerSocket: symlinks /run/docker.sock to podman's own socket
  #     (nixpkgs nixos/modules/virtualisation/podman/default.nix) -- the
  #     exact path Docker tooling (docker-compose, SDKs, testcontainers)
  #     checks by default, no DOCKER_HOST override needed in a project's
  #     own .env/CI config. Conflicts with virtualisation.docker.enable by
  #     a hard assertion (only one can own that socket) -- another reason
  #     not to also enable real Docker.
  virtualisation.podman.dockerCompat = true;
  virtualisation.podman.dockerSocket.enable = true;

  # "Users must be in the podman group in order to connect" (dockerSocket
  # option doc) -- without this, docker-compose from a project would get
  # a permission-denied talking to /run/docker.sock despite the socket
  # existing. Same root-equivalent caveat as that option's own docs give:
  # group members can reach podman's root-owned storage/images, matching
  # what being in `wheel` (sudo) already grants `max` on this machine.
  users.users.max.extraGroups = [ "podman" ];

  # docker-compose v2 (Go binary, talks the real Docker Engine API) --
  # NOT podman-compose (a separate Python reimplementation with its own
  # compatibility gaps); pointing the real docker-compose at
  # dockerSocket's /run/docker.sock is the closest match to how it
  # behaves against actual Docker, for existing docker-compose.yml files
  # that were written/tested against real Docker.
  environment.systemPackages = [ pkgs.docker-compose ];

  # Podman ships with NO unqualified-search registries configured by
  # default (unlike Docker Hub being implicit in real Docker) -- confirmed
  # live via dev-databases.nix's own postgres/redis containers, which had
  # to use fully-qualified `docker.io/library/postgres:16` refs to avoid
  # "short-name ... did not resolve to an alias" at container start.
  # docker-compose.yml files from an existing project almost always use
  # short names (`postgres:16`, `redis:7`, ...) and aren't ours to rewrite
  # -- so unlike dev-databases.nix's own containers, the fix here is at
  # the registry config, not the image refs. `registries.settings` is the
  # current (non-deprecated) nix option; it maps to containers-registries
  # .conf's `[registries.search]` TOML table 1:1.
  virtualisation.containers.registries.settings.search.registries = [ "docker.io" ];

  # Rootless podman (pasta) cannot reach the host's loopback from a
  # container by default: `host.docker.internal:host-gateway` resolves to
  # 169.254.1.2, and connecting to it gives "connection refused" for
  # services bound to 127.0.0.1 -- e.g. dev-databases.nix's postgres
  # (published on 127.0.0.1:5432). Project compose files (eshk's crypton
  # and broker) reach the host database exactly that way. Verified live
  # 2026-10-19: `--network=pasta:--map-host-loopback,169.254.1.2` makes
  # 169.254.1.2:5432 reach the host's 127.0.0.1:5432. Set as the default
  # pasta option so no project needs per-container network flags.
  # Only the rootless pasta backend reads it; rootful netavark ignores it.
  virtualisation.containers.containersConf.settings.network.pasta_options = [
    "--map-host-loopback"
    "169.254.1.2"
  ];
}
