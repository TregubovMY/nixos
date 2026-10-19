# Shortcuts for the dev cycle documented in CLAUDE.md ("Makefile-шорткаты
# (если есть/нужно завести)") -- kept simple and obviously named, per
# that section's own instruction. HOST selects which
# nixosConfigurations.<HOST> a target applies to, e.g.:
#   make dry HOST=mimir
#
# dry/vm use nixos-rebuild, which isn't on PATH in the dev sandbox this
# repo was largely built in (see CLAUDE.md) -- these two targets are for
# a real NixOS machine, where nixos-rebuild is standard.
SYSTEM := x86_64-linux

# Throne's local mixed SOCKS+HTTP listener (inbound_socks_port in its own
# ~/.config/Throne/config/throne.db) -- the one some fetchurl-based
# packages need to get past sanctions-geoblocking (RubyMine's
# download.jetbrains.com, see docs/NIX-HOWTO.md "Собрать пакет, который
# блокируют без прокси"). A plain `/dev/tcp` probe (bash-only, hence
# `bash -c` -- make's default $(SHELL) on NixOS is dash, which doesn't
# have it) decides per-run whether to pass it through NIX_CONFIG's
# impure-env, instead of either hardcoding it always-on (breaks every
# OTHER fixed-output fetch with connection-refused whenever Throne isn't
# running) or requiring it typed out by hand every time (found live
# 2026-10-19, user asked for exactly this instead of either extreme).
# No nix.conf trusted-users change needed for impure-env to apply here:
# `root` already is one by Nix's own default, and these two targets
# already run through `sudo`.
PROXY_PORT := 2080
define with_proxy_if_up
	@if bash -c 'exec 3<>/dev/tcp/127.0.0.1/$(PROXY_PORT)' 2>/dev/null; then \
		echo "==> Throne proxy is up on 127.0.0.1:$(PROXY_PORT) -- routing fixed-output fetches (RubyMine etc.) through it"; \
		sudo env NIX_CONFIG='impure-env = http_proxy=http://127.0.0.1:$(PROXY_PORT) https_proxy=http://127.0.0.1:$(PROXY_PORT)' $(1); \
	else \
		echo "==> No proxy listening on 127.0.0.1:$(PROXY_PORT) -- building WITHOUT it (RubyMine and similar fetches may fail with 451)"; \
		sudo $(1); \
	fi
endef

.PHONY: check check-full dry vm switch disko-test

check:
	nix flake check --no-build

check-full:
	nix flake check -L

dry:
	nixos-rebuild dry-build --flake .#$(HOST)

vm:
	$(call with_proxy_if_up,nixos-rebuild build-vm --flake .#$(HOST))
	./result/bin/run-*-vm

switch:
	$(call with_proxy_if_up,nixos-rebuild switch --flake .#$(HOST))

disko-test:
	nix build .#checks.$(SYSTEM).disko-luks-btrfs -L

# Wrapper tests for bin/agent-sandbox (fake podman, seconds) -- same
# script the `agent-sandbox-cli` flake check runs, minus shellcheck.
.PHONY: test
test:
	bash tests/agent-sandbox-test.sh
