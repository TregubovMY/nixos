{
  # One real host (nixosConfigurations.mimir), the agent-sandbox image, and
  # VM checks for the disk layout, Secure Boot signing and the sandbox CLI.
  # The per-module throwaway hosts (test-*, mimir-vm-*) were removed on
  # 2026-10-06: .#mimir composes every module, so `nix flake check
  # --no-build` evaluating it covers what they did; the real install
  # rehearsal is now bin/mimir-install against .#mimir in a VM
  # (docs/vm-check.md). Their history is in git.
  #
  # sops-nix deliberately NOT an input (was, briefly, for a single GPG-key
  # secret) — system-plan.md §7 resolved that secret to Bitwarden too,
  # same place SSH keys and the Throne proxy config already live (§6/§7):
  # nothing in this repo's actual secret inventory needs to exist before
  # network login/Bitwarden unlock, which was sops-nix's one remaining
  # reason for being here. See system-plan.md §6 for the full writeup.
  description = "NixOS for mimir: disko+LUKS, Secure Boot, Hyprland+DMS, home-manager, agent sandboxes (see system-plan.md)";

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

  # DankCalendar (AvengeMedia/dankcalendar, MIT): standalone calendar with
  # Google/Microsoft/CalDAV accounts, background sync and native event
  # reminders, rendered inside the DMS panel (DMS's "dankcal" calendar
  # backend talks to its socket). Requested 2026-10-06 for Google Calendar
  # notifications. Merged into nixpkgs on 2026-09-25 (PR #556440), but our
  # nixpkgs pin is older, so it comes from upstream's own flake instead of
  # a full nixpkgs bump -- same pattern as dank-material-shell above,
  # pinned to an explicit commit. Builds with our nixpkgs (needs Go >=
  # 1.26.4; ours has 1.26.5). Its own dank-qml-common input is NOT made to
  # follow DMS's: the two may need different revisions of that library.
  inputs.dank-calendar = {
    url = "github:AvengeMedia/dankcalendar/7f72bd70d1cd5182b5514fec7562955dcaeaab04";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nixpkgs, disko, lanzaboote, home-manager, dank-material-shell, dank-calendar, ... }:
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
      # The sandbox root directory (no container image any more, see
      # modules/nixos/packages/agent-sandbox.nix). On the host it arrives
      # through modules/nixos/agent-sandbox.nix; this output is for building
      # / testing it without a rebuild: `nix build .#agent-sandbox-rootfs`
      # and AGENT_SANDBOX_ROOTFS=./result agent-sandbox ...
      packages.${system} = rec {
        agent-sandbox-rootfs =
          (import ./modules/nixos/packages/agent-sandbox.nix { inherit pkgs; }).rootfs;
        default = agent-sandbox-rootfs;
      };

      # Machines: every hosts/<name>/ with a configuration.nix becomes
      # nixosConfigurations.<name> (the shared part is hosts/common.nix,
      # the hardware report hosts/<name>/facter.json). A new machine is a
      # new folder -- bin/install-host creates it on first install.
      nixosConfigurations =
        let
          hostNames = builtins.filter
            (n: builtins.pathExists (./hosts + "/${n}/configuration.nix"))
            (builtins.attrNames (nixpkgs.lib.filterAttrs (_: t: t == "directory") (builtins.readDir ./hosts)));
          mkHost = name: nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              disko.nixosModules.disko
              lanzaboote.nixosModules.lanzaboote
              home-manager.nixosModules.home-manager
              dank-material-shell.nixosModules.default
              # DMS's / DankCalendar's home-manager options only exist when
              # their homeModules are injected via sharedModules, not just
              # by importing the nixosModules above (found live).
              {
                home-manager.sharedModules = [
                  dank-material-shell.homeModules.default
                  dank-calendar.homeModules.default
                ];
              }
              (./hosts + "/${name}/configuration.nix")
            ];
          };
        in
        nixpkgs.lib.genAttrs hostNames mkHost;

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

        # bin/agent-sandbox's own logic (argument parsing, the env
        # allowlist that keeps Jira/GitLab tokens out of the container,
        # --workdir validation, exit-code passthrough, up/exec wiring),
        # tested against a fake `podman` -- see the header of
        # tests/agent-sandbox-test.sh. Unlike the two VM tests around it
        # this one is cheap (bash + shellcheck, seconds), so a plain
        # `nix build .#checks.x86_64-linux.agent-sandbox-cli` or `make
        # test` is fine to run after every change to the wrapper.
        agent-sandbox-cli =
          pkgs.runCommand "agent-sandbox-cli-test"
            {
              nativeBuildInputs = with pkgs; [
                bash
                coreutils
                gawk
                gnugrep
                shellcheck
              ];
            }
            ''
              cp -r ${./bin} bin
              cp -r ${./tests} tests
              chmod -R u+w .
              shellcheck -x bin/agent-sandbox tests/agent-sandbox-test.sh
              bash tests/agent-sandbox-test.sh
              touch $out
            '';

        # Confirms Secure Boot works with this repo's exact
        # boot.initrd.systemd.enable = true choice, via lanzaboote's own
        # upstream test architecture (vendored, see
        # modules/nixos/secure-boot-test/systemd-initrd.nix — that file's
        # header comment has the full provenance + WHY writeup). Does NOT
        # exercise disko-luks-btrfs.nix or secure-boot.nix — see
        # docs/superpowers/specs/2026-08-10-secure-boot-design.md "Two
        # Checks, Not One Combined Test". Module composition between those
        # two is covered by evaluating .#mimir (`nix flake check --no-build`).
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
