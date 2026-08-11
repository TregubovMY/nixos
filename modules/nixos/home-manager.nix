# Enables home-manager as NixOS-module-integrated infrastructure (not
# standalone `home-manager switch`) — matches system-plan.md §2's
# architecture table ("привязка к NixOS-модулям"). Requires
# home-manager.nixosModules.home-manager imported alongside this module at
# the flake level (same pattern disko.nixosModules.disko already uses) —
# this file only sets the options that module provides, it doesn't import
# it itself. No per-user home-manager.users.<name> block here: that's
# host-specific (a real username), same boundary users.users.* already has
# in this repo — see docs/superpowers/specs/2026-08-11-home-manager-design.md.
{
  # Reuses the host's own already-evaluated pkgs instead of importing
  # nixpkgs a second time -- cheaper, and keeps nixpkgs.config.allowUnfree
  # (set per-host, e.g. desktop-apps.nix-importing hosts) visible to
  # home-manager's own packages too.
  home-manager.useGlobalPkgs = true;
  # Installs home.packages into /etc/profiles/per-user/<name> (the modern,
  # NixOS-module-integrated path) instead of the legacy ~/.nix-profile.
  home-manager.useUserPackages = true;
}
