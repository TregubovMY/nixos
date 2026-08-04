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
