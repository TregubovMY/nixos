# Throwaway verification host for the desktop package list — NOT a real
# target machine, and NOT hosts/mimir/. Proves the package list and the
# two program-module enables (programs.throne, programs.kdeconnect)
# evaluate and build together — no VM boot needed, see
# docs/superpowers/specs/2026-08-10-desktop-packages-design.md
# "Testing Scope" for why a functional test isn't warranted here.
{ ... }:
{
  imports = [
    ../../modules/nixos/desktop-apps.nix
    ../../modules/nixos/boot.nix
  ];

  fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
  boot.loader.grub.device = "/dev/vda";

  system.stateVersion = "24.05";

  # desktop-apps.nix pulls in several unfree packages (jetbrains.ruby-mine,
  # google-chrome, vscode, postman). flake.nix's `config.allowUnfree = true`
  # only applies to the loose `pkgs` instance used for `packages.${system}`
  # (the agent-sandbox image) — it is NOT threaded into any nixosSystem
  # call, so without this the dry-build fails outright with "Refusing to
  # evaluate package ... unfree license". CLAUDE.md's packages rule says
  # unfree support "уже должно быть включено в flake.nix/configuration.nix"
  # — it wasn't, for any host; this is the first host to actually need it,
  # so this is where the gap surfaces. A real host (hosts/mimir/ once it
  # exists) will need the same line in its own configuration.nix.
  nixpkgs.config.allowUnfree = true;
}
