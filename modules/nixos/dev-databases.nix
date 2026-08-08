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
      # Fully-qualified image ref (docker.io/library/... rather than the
      # short name "postgres:16"): NixOS's podman ships with no
      # unqualified-search registries configured in
      # /etc/containers/registries.conf (unlike Docker, which defaults to
      # Docker Hub) — a short name fails at container start with "short-name
      # \"postgres:16\" did not resolve to an alias and no unqualified-search
      # registries are defined". Found via build-vm verification (Task 3).
      # Qualifying the ref avoids having to also configure
      # registries.conf/short-name aliasing.
      image = "docker.io/library/postgres:16";
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
      # Fully-qualified for the same reason as postgres above.
      image = "docker.io/library/redis:7";
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
