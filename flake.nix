{
  # Scoped to what actually exists so far: the agent-sandbox package, a
  # throwaway test-vm host for the dev-databases module, and (new) the
  # disko/boot modules for the disk foundation design plus their own
  # throwaway verification host. Not yet the full host flake (Hyprland,
  # home-manager, sops-nix, hosts/mimir) — see system-plan.md §3.
  description = "agent-sandbox package + dev-databases test-vm + disk/boot foundation (see system-plan.md)";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.disko = {
    url = "github:nix-community/disko";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, ... }:
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
      packages.${system} = rec {
        agent-sandbox-image =
          import ./modules/nixos/packages/agent-sandbox.nix { inherit pkgs; };
        # Bare `nix build` (no attribute) resolves to `.default` —
        # without this it fails outright since there's only one package
        # and its name isn't `default` (final review, M8).
        default = agent-sandbox-image;
      };

      # Throwaway verification host for the dev-databases module (Postgres+
      # Redis via oci-containers) — see docs/superpowers/plans/
      # 2026-08-04-postgres-redis.md and hosts/test-vm/configuration.nix's
      # own header comment for why this isn't a real target machine.
      nixosConfigurations.test-vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./hosts/test-vm/configuration.nix ];
      };

      # Throwaway verification host for the disk/boot foundation design
      # (disko-luks-btrfs.nix + boot.nix) — see docs/superpowers/specs/
      # 2026-08-08-disk-boot-foundation-design.md. NOT the real mimir host.
      nixosConfigurations.test-disko-luks = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          ./hosts/test-disko-luks/configuration.nix
        ];
      };
    };
}
