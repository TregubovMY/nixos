{
  # Scoped to what actually exists so far: the agent-sandbox package, a
  # throwaway test-vm host for the dev-databases module, the disko/boot
  # modules for the disk foundation design plus their own throwaway
  # verification host, the Secure Boot foundation, the declarative desktop
  # package list (desktop-apps.nix), and home-manager infrastructure
  # (NixOS-module-integrated, no dotfile content yet). Not yet the full
  # host flake (hosts/mimir's real user) — see system-plan.md §3.
  #
  # sops-nix deliberately NOT an input (was, briefly, for a single GPG-key
  # secret) — system-plan.md §7 resolved that secret to Bitwarden too,
  # same place SSH keys and the Throne proxy config already live (§6/§7):
  # nothing in this repo's actual secret inventory needs to exist before
  # network login/Bitwarden unlock, which was sops-nix's one remaining
  # reason for being here. See system-plan.md §6 for the full writeup.
  description = "agent-sandbox package + dev-databases test-vm + disk/boot + Secure Boot + desktop packages + home-manager foundations (see system-plan.md)";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.disko = {
    url = "github:nix-community/disko";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  inputs.lanzaboote = {
    url = "github:nix-community/lanzaboote/v1.1.0";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  # IMPORTANT when bumping this input: modules/nixos/secure-boot-test/ is a
  # VENDORED (copied, not live-referenced) snapshot of lanzaboote's own
  # upstream test at the rev this input resolves to right now. Bumping
  # `lanzaboote` here does NOT update that vendored copy — re-vendor it from
  # the new rev's nix/tests/lanzaboote/ and re-run `nix flake check -L`
  # (checks.${system}.secure-boot-signing) after any bump, or the check
  # silently drifts into testing stale scaffolding against a newer module.
  inputs.home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  # DankMaterialShell (Quickshell-based desktop shell) -- replaces
  # waybar/mako/hyprlock/hypridle/fuzzel entirely, see
  # modules/home/hyprland.nix's header comment for the full "why".
  # `inputs.nixpkgs.follows` here only affects DMS's OWN flake outputs
  # (packages/devShells we don't use) -- the nixosModules/homeModules we
  # actually import build dms-shell from source using WHATEVER pkgs our
  # own module system passes them (confirmed by reading
  # distro/nix/{nixos,home}.nix's `mkModuleWithDmsPkgs pkgs` plumbing),
  # i.e. this repo's own pinned nixpkgs either way -- .follows is just
  # lockfile hygiene, not load-bearing for the actual build.
  inputs.dank-material-shell = {
    # Pinned to an explicit commit (via `git ls-remote`, master HEAD at
    # the time this was added) rather than a bare branch reference --
    # GitHub's REST API (used to resolve a bare `github:owner/repo` ref
    # to a commit) was rate-limited (403) from this network at write
    # time; an explicit rev sidesteps that resolution call entirely.
    url = "github:AvengeMedia/DankMaterialShell/7974887295d2691fba5f885a899c3f8ba7ef59dd";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nixpkgs, disko, lanzaboote, home-manager, dank-material-shell, ... }:
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

      # Throwaway verification host for the Secure Boot design — see
      # docs/superpowers/specs/2026-08-10-secure-boot-design.md. Proves module
      # composition only (Check 2) — NOT a Secure-Boot-verified boot chain, see
      # hosts/test-secure-boot/configuration.nix's own header comment.
      nixosConfigurations.test-secure-boot = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          lanzaboote.nixosModules.lanzaboote
          ./hosts/test-secure-boot/configuration.nix
        ];
      };

      # Manual-install rehearsal host — see
      # docs/superpowers/plans/tingly-doodling-phoenix.md and
      # hosts/mimir-vm-rehearsal/configuration.nix's own header comment.
      # Unlike test-secure-boot above, this is meant to be installed for
      # real (disko + nixos-install, by hand, inside a user-launched VM)
      # rather than auto-built — no qemu-vm.nix, so nothing here overrides
      # the real LUKS/btrfs layout.
      nixosConfigurations.mimir-vm-rehearsal = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          lanzaboote.nixosModules.lanzaboote
          ./hosts/mimir-vm-rehearsal/configuration.nix
        ];
      };

      # Full-system VM rehearsal (disko+Secure Boot+desktop-apps+
      # dev-databases+podman+home-manager -- everything but secrets.nix)
      # -- see docs/superpowers/plans/tingly-doodling-phoenix.md and
      # hosts/mimir-vm-full/configuration.nix's own header comment.
      nixosConfigurations.mimir-vm-full = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          disko.nixosModules.disko
          lanzaboote.nixosModules.lanzaboote
          home-manager.nixosModules.home-manager
          dank-material-shell.nixosModules.default
          # home-manager.sharedModules, not just the nixosModules import
          # above -- that only wires the system-level pieces (systemd
          # deps like power-profiles-daemon). programs.dank-material-shell
          # itself is a per-user home-manager option
          # (modules/home/hyprland.nix references it), which needs the
          # homeModules side injected into every home-manager user
          # explicitly -- confirmed live: without this,
          # home-manager.users.max.programs.dank-material-shell doesn't
          # exist at all.
          { home-manager.sharedModules = [ dank-material-shell.homeModules.default ]; }
          ./hosts/mimir-vm-full/configuration.nix
        ];
      };

      # Throwaway verification host for the desktop package list design —
      # see docs/superpowers/specs/2026-08-10-desktop-packages-design.md.
      # NOT the real mimir host; eval + dry-build only (no VM boot), see
      # hosts/test-desktop-apps/configuration.nix's own header comment.
      nixosConfigurations.test-desktop-apps = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./hosts/test-desktop-apps/configuration.nix ];
      };

      # Throwaway verification host for the home-manager infrastructure
      # design — see docs/superpowers/specs/2026-08-11-home-manager-design.md.
      # Eval + a real (non-dry-run) build only, no VM boot — see
      # hosts/test-home-manager/configuration.nix's own header comment.
      nixosConfigurations.test-home-manager = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          home-manager.nixosModules.home-manager
          ./hosts/test-home-manager/configuration.nix
        ];
      };

      # Throwaway verification host for the Hyprland module + package
      # list — see docs/superpowers/specs/2026-08-11-hyprland-design.md.
      # Eval + dry-build only, no VM boot possible or useful (no GPU/
      # display in this sandbox, and no agent can visually verify a
      # compositor regardless) — see
      # hosts/test-hyprland/configuration.nix's own header comment.
      nixosConfigurations.test-hyprland = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./hosts/test-hyprland/configuration.nix ];
      };

      # Throwaway verification host for modules/home/shell.nix +
      # zellij.nix — see docs/superpowers/specs/
      # 2026-08-11-shell-zellij-design.md. Real build (not dry-run), no
      # VM boot — see hosts/test-shell/configuration.nix's own header
      # comment.
      nixosConfigurations.test-shell = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          home-manager.nixosModules.home-manager
          ./hosts/test-shell/configuration.nix
        ];
      };

      # Throwaway verification host for modules/home/neovim.nix (base
      # LazyVim) — see docs/superpowers/specs/
      # 2026-08-11-neovim-base-design.md. Real build (not dry-run), no
      # VM boot, no live plugin-install check — see
      # hosts/test-neovim/configuration.nix's own header comment.
      nixosConfigurations.test-neovim = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          home-manager.nixosModules.home-manager
          ./hosts/test-neovim/configuration.nix
        ];
      };

      # Throwaway verification host for modules/home/ghostty.nix +
      # direnv.nix — real build (not dry-run), no VM boot — see
      # hosts/test-terminal/configuration.nix's own header comment.
      nixosConfigurations.test-terminal = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          home-manager.nixosModules.home-manager
          ./hosts/test-terminal/configuration.nix
        ];
      };

      # Throwaway verification host for modules/nixos/podman.nix +
      # modules/home/mise.nix — real build (not dry-run), no VM boot —
      # see hosts/test-podman-mise/configuration.nix's own header
      # comment.
      nixosConfigurations.test-podman-mise = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          home-manager.nixosModules.home-manager
          ./hosts/test-podman-mise/configuration.nix
        ];
      };

      # Throwaway verification host for modules/home/hyprland.nix (real
      # config content) — see docs/superpowers/specs/
      # 2026-08-12-hyprland-config-design.md. Real build (not dry-run),
      # no VM boot, no live/visual check — see
      # hosts/test-hyprland-config/configuration.nix's own header
      # comment.
      nixosConfigurations.test-hyprland-config = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          home-manager.nixosModules.home-manager
          dank-material-shell.nixosModules.default
          # See nixosConfigurations.mimir-vm-full's own comment on this
          # same line -- homeModules must be injected via sharedModules
          # too, not just the nixosModules import above.
          { home-manager.sharedModules = [ dank-material-shell.homeModules.default ]; }
          ./hosts/test-hyprland-config/configuration.nix
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
      # `nix flake check -L` — see docs/superpowers/plans/
      # 2026-08-08-disk-boot-foundation.md, Task 3.
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
            # btrfs root came up with its subvolumes actually present and
            # mounted, not just "some btrfs filesystem exists" -- a bare
            # `btrfs subvolume list /` exits 0 even with zero subvolumes,
            # so it wouldn't catch a layout regression (final review, M1).
            # Subvolume names in `btrfs subvolume list` output have no
            # leading slash even though disko-luks-btrfs.nix declares them
            # as "/root"/"/home"/"/nix" (confirmed by reading disko's
            # lib/types/btrfs.nix: subvol.name is used verbatim in
            # "$MNTPOINT/''${subvol.name}", and the leading "/" collapses
            # into the mountpoint's own separator, so the subvolume is
            # actually created as "root" relative to the top of the fs).
            machine.succeed("btrfs subvolume list / | grep -q ' path root$'")
            machine.succeed("findmnt /home")
            machine.succeed("findmnt /nix")
            # swap is actually active on the decrypted mapper device, not
            # the raw partition (proves the LUKS -> swap nesting actually
            # worked -- the one thing the design doc flagged as
            # unverified-by-example). Wait for the swap unit explicitly
            # first: extraTestScript runs right after disko's own
            # `wait_for_unit("local-fs.target")`, but swap.target has no
            # ordering relation to local-fs.target, so without this the
            # swapon check below is only *usually* correct, not guaranteed
            # (final review, M3) -- in practice it already wins because the
            # mapper exists from initrd, but this branch's single most
            # load-bearing assertion shouldn't be racy.
            machine.wait_for_unit("dev-mapper-cryptswap.swap")
            # NOTE: `swapon --show` reports the *canonical* backing device
            # (/dev/dm-N), not the /dev/mapper/* symlink, so grep for
            # /dev/mapper/cryptswap literally never matches even when swap
            # is correctly active -- confirmed by manually running with an
            # un-grepped `swapon --show` (showed /dev/dm-0, [SWAP] in
            # lsblk, and an active dev-mapper-cryptswap.swap unit) and by
            # reading disko's own generated activation script, which
            # resolves the symlink first:
            # `grep -q "^$(readlink -f /dev/mapper/cryptswap) "`. Mirror
            # that exact pattern here instead of a literal string match.
            machine.succeed(
                "swapon --show | grep -q \"^$(readlink -f /dev/mapper/cryptswap) \""
            )
            # boot.resumeDevice ended up pointing at the right place --
            # check the activated system's kernel params, not just that
            # the option exists at eval time. Assert the exact value (not
            # just that "resume=" appears somewhere) so a future
            # regression to the raw partition (e.g. /dev/vda3 instead of
            # the mapper device) would actually fail this check (final
            # review, M2).
            machine.succeed(
                'grep -q "resume=/dev/mapper/cryptswap" /proc/cmdline'
            )
          '';
        };

        # Confirms Secure Boot works with this repo's exact
        # boot.initrd.systemd.enable = true choice, via lanzaboote's own
        # upstream test architecture (vendored, see
        # modules/nixos/secure-boot-test/systemd-initrd.nix — that file's
        # header comment has the full provenance + WHY writeup). Does NOT
        # exercise disko-luks-btrfs.nix or secure-boot.nix — see
        # docs/superpowers/specs/2026-08-10-secure-boot-design.md "Two
        # Checks, Not One Combined Test". Module composition between those
        # two is covered separately by hosts/test-secure-boot/ (Check 2,
        # `nix flake check --no-build`).
        secure-boot-signing = pkgs.testers.runNixOSTest {
          imports = [ ./modules/nixos/secure-boot-test/systemd-initrd.nix ];
          globalTimeout = 5 * 60;
          extraBaseModules = {
            imports = [ lanzaboote.nixosModules.lanzaboote ];
          };
        };
      };
    };
}
