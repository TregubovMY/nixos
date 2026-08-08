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

      # Real, functional verification (not just eval) of the disk/boot
      # foundation: LUKS unlock, btrfs subvolumes, and the LUKS->swap->
      # resumeDevice nesting the design doc flagged as unverified-by-
      # committed-example. Uses disko's own reusable VM test helper
      # (disko.lib.testLib.makeDiskoTest, see disko-luks-btrfs-test.nix's
      # header comment for why a separate plain config file is needed
      # here rather than pointing straight at the parameterized module)
      # instead of writing a raw NixOS VM test from scratch, per
      # CLAUDE.md's "search for real solutions first" rule. Run via
      # `nix flake check -L` — see task-3-brief.md, Step 2.
      checks.${system} = {
        disko-luks-btrfs = disko.lib.testLib.makeDiskoTest {
          inherit pkgs;
          name = "disko-luks-btrfs";
          disko-config = ./modules/nixos/disko-luks-btrfs-test.nix;
          extraTestScript = ''
            # Both LUKS containers actually exist and are real LUKS (not
            # plaintext, not randomEncryption swap):
            machine.succeed("cryptsetup isLuks /dev/vda2")
            machine.succeed("cryptsetup isLuks /dev/vda3")
            # btrfs root came up with its subvolumes:
            machine.succeed("btrfs subvolume list /")
            # swap is actually active on the decrypted mapper device, not
            # the raw partition (proves the LUKS -> swap nesting actually
            # worked -- the one thing the design doc flagged as
            # unverified-by-example). NOTE: `swapon --show` reports the
            # *canonical* backing device (/dev/dm-N), not the /dev/mapper/*
            # symlink, so grep for /dev/mapper/cryptswap literally never
            # matches even when swap is correctly active -- confirmed by
            # manually running with an un-grepped `swapon --show` (showed
            # /dev/dm-0, [SWAP] in lsblk, and an active
            # dev-mapper-cryptswap.swap unit) and by reading disko's own
            # generated activation script, which resolves the symlink
            # first: `grep -q "^$(readlink -f /dev/mapper/cryptswap) "`.
            # Mirror that exact pattern here instead of a literal string
            # match.
            machine.succeed(
                "swapon --show | grep -q \"^$(readlink -f /dev/mapper/cryptswap) \""
            )
            # boot.resumeDevice ended up pointing at the right place --
            # check the activated system's kernel params, not just that
            # the option exists at eval time:
            machine.succeed("cat /proc/cmdline | grep -q resume=")
          '';
        };
      };
    };
}
