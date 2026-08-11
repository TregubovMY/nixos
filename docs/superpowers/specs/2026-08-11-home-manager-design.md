# home-manager Infrastructure Design

## Goal

Wire home-manager into this flake as reusable infrastructure — the flake
input, a small NixOS module enabling it with the "integrated with NixOS"
settings, and a throwaway test host proving the plumbing composes and
builds. Real dotfile content (`modules/home/*`: tmux, neovim, shell,
waybar, Hyprland configs) and Hyprland itself are explicitly out of scope
— both already deferred here by name in
`docs/superpowers/specs/2026-08-10-desktop-packages-design.md`'s "Out of
Scope" section ("home-manager itself — separate, later task; this plan's
packages may move there once it exists"). This round is that later task,
scoped narrowly the same way every prior round in this repo has been
(disko, Secure Boot, secrets, desktop packages — one focused plan each).

## Why NixOS-module-integrated, not standalone

`system-plan.md` §2's architecture table already names home-manager's role
as "Dotfiles, пользовательские пакеты, привязка к NixOS-модулям" — tied to
NixOS modules, not a separately-run `home-manager switch`. That means
`home-manager.nixosModules.home-manager` imported into a `nixosSystem`
call (same pattern `disko.nixosModules.disko` and
`lanzaboote.nixosModules.lanzaboote` already use), with
`home-manager.users.<name>` configured inside the NixOS config itself, so
one `nixos-rebuild switch` activates both the system and the user's home
generation together.

## Flake input

```nix
inputs.home-manager = {
  url = "github:nix-community/home-manager";
  inputs.nixpkgs.follows = "nixpkgs";
};
```
No `release-*` branch pin: this repo tracks `nixpkgs/nixos-unstable`
(`flake.nix`), and home-manager's `master` branch is the one meant to
track nixpkgs-unstable — a `release-*` branch would drag in a different,
older nixpkgs pin philosophy that conflicts with `follows`.

## Module

```
modules/nixos/home-manager.nix
```
```nix
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
}
```
- `useGlobalPkgs = true`: home-manager reuses the host's own already-
  evaluated `pkgs` instead of importing nixpkgs a second time — cheaper,
  and keeps `nixpkgs.config.allowUnfree` (set per-host, e.g.
  `hosts/test-desktop-apps/`, `hosts/mimir/configuration.nix`) visible to
  home-manager's own packages too.
- `useUserPackages = true`: `home.packages` installs into
  `/etc/profiles/per-user/<name>` (the modern, NixOS-module-integrated
  path) instead of the legacy `~/.nix-profile`.
- No per-user block here — that's host-specific (see below), not this
  module's job, same boundary `disko-luks-btrfs.nix`'s parameterization
  and `secure-boot.nix`'s host-independence already established.
- Requires `home-manager.nixosModules.home-manager` imported at the flake
  level alongside this module (same pattern as `disko.nixosModules.disko`
  in `flake.nix` today) — this module only sets options that module
  provides, it doesn't import it itself.

## What's genuinely reusable vs. host-specific

`home-manager.users.<name> = { home.stateVersion = "24.05"; };` is
**not** reusable — the username is host-specific, same boundary
`users.users.*` already has in this repo (README: "ещё нет реального
пользователя... это шаг реальной установки"). `hosts/mimir/` doesn't have
a real user yet (its `configuration.nix`, from the skeleton round, has no
`users.users.*` block), so it gets no `home-manager.users.*` block either
in this round — adding one now would mean inventing a username with no
real backing, the same anti-pattern the mimir-skeleton design explicitly
avoided for `hardware-configuration.nix`. This round proves the mechanism
via a throwaway user on a throwaway host instead.

## Test host

```
hosts/test-home-manager/
  configuration.nix   # mirrors hosts/test-desktop-apps/'s shape exactly:
                       # ext4 /dev/vda1 + grub, no qemu-vm.nix import
                       # (eval + build only, no manual VM boot needed)
```
```nix
{ ... }:
{
  imports = [
    ../../modules/nixos/boot.nix
    ../../modules/nixos/home-manager.nix
  ];

  fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
  boot.loader.grub.device = "/dev/vda";

  users.users.testuser = {
    isNormalUser = true;
    home = "/home/testuser";
  };
  home-manager.users.testuser = {
    home.stateVersion = "24.05";
  };

  system.stateVersion = "24.05";
}
```
`testuser` exists only to give `home-manager.users.*` something to bind
to — same throwaway-only status as `hosts/test-disko-luks/`'s virtual
disk or `hosts/test-secrets/`'s test SSH key. Not a preview of `mimir`'s
real username.

Register in `flake.nix` alongside the existing throwaway hosts:
```nix
nixosConfigurations.test-home-manager = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    home-manager.nixosModules.home-manager
    ./hosts/test-home-manager/configuration.nix
  ];
};
```

## Testing — why eval + a real build, no VM boot

Same reasoning as the desktop-packages round's "Testing Scope": with no
dotfile content yet, there's no runtime activation behavior worth a VM
boot over (no symlinks being placed, no service being started). What *is*
new and worth confirming for real: home-manager's own activation-script
and per-user-profile derivations actually build, not just evaluate —
unlike a flat package list, home-manager introduces its own build-time
machinery (`home-manager-generation`, the activation script derivation)
that a plain `nix flake check --no-build` (eval-only) or `--dry-run`
(lists what *would* build, doesn't build it) wouldn't exercise.

1. `nix flake check --no-build` — eval-only, routine after every edit.
2. `nix build .#nixosConfigurations.test-home-manager.config.system.build.toplevel`
   (no `--dry-run`) — actually builds the closure, including
   home-manager's activation script and `testuser`'s profile derivation.
   Cheap relative to the VM tests elsewhere in this repo (no QEMU/OVMF
   involved), so building for real instead of dry-running is worth it
   here specifically.

## Out of Scope (unchanged from the desktop-packages round's own list, still true)

- Hyprland itself and its supporting daemons (waybar, mako, hyprlock,
  hypridle, hyprpaper, fuzzel, cliphist, polkit agent) — separate, larger,
  already-prioritized-later task (`system-plan.md` §5.2).
- `modules/home/*` dotfiles (tmux, neovim, shell, waybar config,
  `hypr/quick-translate.lua`'s eventual home-manager wiring) — need
  home-manager to exist first (this round), populated after.
- `hosts/mimir/`'s real user and real `home-manager.users.*` content —
  real-install-time step, same boundary as every other "real hardware"
  gap named in this repo (`hardware-configuration.nix`, Secure Boot
  enrollment, real `secrets/secrets.yaml`).
