# `hosts/mimir/` Skeleton Design

## Goal

Write the two files the disk/boot foundation design doc already earmarked
for this exact step (`docs/superpowers/specs/2026-08-08-disk-boot-foundation-design.md`,
"Real Install Boundary", steps 2): `hosts/mimir/disk-config.nix` and
`hosts/mimir/configuration.nix`, composing the four already-VM-proven
modules (`disko-luks-btrfs.nix`, `secure-boot.nix`, `secrets.nix`,
`desktop-apps.nix`) under `mimir`'s real host identity. No hardware
present for this round (confirmed with the human partner) — so this is
declarative preparation only, not an install.

## What this is not

Per that same design doc, an earlier draft's placeholder
`hardware-configuration.nix` was rejected specifically because a
placeholder sitting in the real host's directory risks being forgotten and
mistaken for real content. This design avoids that trap differently: it
creates only files whose content is genuinely real and final (host
identity, module composition), skips the file that can't be genuine yet
(`hardware-configuration.nix`), and does not register `nixosConfigurations.mimir`
in `flake.nix` — so there is nothing here that evaluates, builds, or could
be mistaken for a working host. `nix flake check` for the rest of the repo
is unaffected.

## Files

```
hosts/mimir/
  disk-config.nix       # thin wrapper, real values already documented in
                         # disko-luks-btrfs.nix's own header comment
  configuration.nix     # host identity + module composition
```

`disk-config.nix`:
```nix
import ../../modules/nixos/disko-luks-btrfs.nix {
  device = "/dev/sdb";
  swapSize = "34G";
}
```
`/dev/sdb` and `34G` are not new decisions — `disko-luks-btrfs.nix`'s own
header comment already names both as the real values for "later, the real
`hosts/mimir/`". This file just gives that documented intent a real
caller.

`configuration.nix`:
```nix
{
  imports = [
    ./disk-config.nix
    ../../modules/nixos/secure-boot.nix   # not boot.nix — replaces it
    ../../modules/nixos/secrets.nix
    ../../modules/nixos/desktop-apps.nix
  ];

  networking.hostName = "mimir";
  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "ru_RU.UTF-8";

  # Same requirement every desktop-apps.nix-importing host already has
  # (hosts/test-desktop-apps/, system-plan.md §2) — desktop-apps.nix pulls
  # unfree packages and nixpkgs.config.allowUnfree from flake.nix's loose
  # `pkgs` instance doesn't propagate into any nixosSystem call.
  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "24.05"; # matches every other host in this repo
}
```
`secure-boot.nix` is imported instead of `boot.nix`, matching the
secure-boot design doc's own stated architecture (lanzaboote *replaces*
systemd-boot, not layered on top) — `boot.nix` is for hosts that don't
want Secure Boot, and `mimir` does (system-plan.md §2/§4).

## Deliberately not included in this round

- **`hardware-configuration.nix`** — only `nixos-generate-config`, run on
  the real machine, can produce this honestly.
- **`nixosConfigurations.mimir` in `flake.nix`** — would fail to evaluate
  without hardware-configuration.nix; not registering it keeps `nix flake
  check` green for the rest of the repo and keeps this host visibly
  "not wired up yet" rather than silently broken.
- **`users.users.max`** — README already documents user-creation as a
  real-install-time step (no one to assign `libvirtd`/`kvm` groups to
  yet); unchanged by this design.
- **Real `secrets/secrets.yaml` / `.sops.yaml` content** — needs `mimir`'s
  real SSH host key (`ssh-to-age`), which only exists after install.
  `secrets.nix` is still safe to import: per system-plan.md §6, sops-nix
  options are just eval-time values — nothing here builds or activates
  this host, so the missing file causes no failure at this stage.

## Real Install Boundary (unchanged principle, now one step shorter)

The disk/boot and Secure Boot design docs both listed three follow-up
steps for when the real install happens. This design does step 2 (module
composition + host identity) ahead of time, since it needs no hardware.
Steps 1 and 3 remain explicitly future, physical-access, user-requested
work:
1. `nixos-generate-config` on `mimir` itself → real `hardware-configuration.nix`.
2. ~~Write `disk-config.nix` + `configuration.nix`~~ — this design.
3. Register `nixosConfigurations.mimir` in `flake.nix`, then the full
   real-install sequence (`sbctl create-keys`/`enroll-keys`, real
   `secrets/secrets.yaml` recipient, `users.users.max`, `nixos-install`).

## Documentation updates

`README.md` and `system-plan.md` both currently say `hosts/mimir/` "ещё не
существует" in several places (disk/boot, Secure Boot, secrets, desktop
package sections). Update each to reflect the new partial state: the
directory now holds a real, reviewed skeleton (identity + module wiring),
still not buildable or registered, real install still a separate future
step. Keep each edit local to where the stale claim already lives rather
than adding a new consolidated status section — matches how these docs
already track state incrementally per round of work.
