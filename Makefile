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

.PHONY: check check-full dry vm disko-test mimir-vm-disko mimir-vm-install

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

# hosts/mimir-vm-rehearsal/ manual install, run from inside the rehearsal
# VM's NixOS installer session (see
# docs/superpowers/plans/tingly-doodling-phoenix.md) -- two separate
# targets, not one combined, since both are interactive (LUKS passphrase
# prompts) and you'll want to watch each finish before the next.
# --extra-experimental-features: the plain installer ISO doesn't enable
# nix-command/flakes by default. disko pinned to this repo's own
# flake.lock rev, so the CLI run here matches what flake.nix's
# disko.nixosModules.disko actually evaluates against.
mimir-vm-disko:
	sudo nix --extra-experimental-features 'nix-command flakes' run \
		github:nix-community/disko/ff8702b4de27f72b4c78573dfb89ec74e36abdf1 -- \
		--mode disko ./hosts/mimir-vm-rehearsal/disk-config.nix

mimir-vm-install:
	sudo nixos-install --extra-experimental-features 'nix-command flakes' \
		--flake .#mimir-vm-rehearsal
