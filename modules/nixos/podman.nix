# Interactive podman for ad-hoc project containers (system-plan.md §5.3)
# -- distinct from dev-databases.nix's declarative
# virtualisation.oci-containers usage, though both need the same
# underlying virtualisation.podman.enable (safe to set true in both; the
# NixOS module system only errors on *conflicting* values for a plain
# bool option, not identical ones set by multiple modules).
{ ... }:
{
  virtualisation.podman.enable = true;
}
