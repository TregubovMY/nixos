# Enables nix-command + flakes system-wide -- gap found live: every
# nixos-install/nixos-rebuild call needed a manual NIX_CONFIG workaround
# (nixos-install/nixos-rebuild are their own wrapper scripts, not `nix`
# itself, so they don't accept --extra-experimental-features). Once this
# is deployed, the installed system's own /etc/nix/nix.conf has both
# enabled, so no more per-command workarounds are needed for any future
# `nix`/`nixos-rebuild` call on this host.
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
