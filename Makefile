# Shortcuts for the dev cycle documented in CLAUDE.md ("Makefile-шорткаты
# (если есть/нужно завести)") -- kept simple and obviously named, per
# that section's own instruction. HOST selects which
# nixosConfigurations.<HOST> a target applies to, e.g.:
#   make dry HOST=test-hyprland
#
# dry/vm use nixos-rebuild, which isn't on PATH in the dev sandbox this
# repo was largely built in (see CLAUDE.md) -- these two targets are for
# a real NixOS machine, where nixos-rebuild is standard.
SYSTEM := x86_64-linux

.PHONY: check check-full dry vm disko-test

check:
	nix flake check --no-build

check-full:
	nix flake check -L

dry:
	nixos-rebuild dry-build --flake .#$(HOST)

vm:
	nixos-rebuild build-vm --flake .#$(HOST) && ./result/bin/run-*-vm

disko-test:
	nix build .#checks.$(SYSTEM).disko-luks-btrfs -L
