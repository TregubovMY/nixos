# Desktop Package List Design

## Goal

Add the remaining declarative package list from `system-plan.md` §5 that
doesn't need custom infrastructure: IDE/editors (§5.4), AI coding agents as
host packages (§5.5), communication/browser (§5.6), API/network (§5.7),
proxy client — Throne (§5.8), remote desktop + KDE Connect (§5.1.1/5.1.2,
already decided 2026-08-10), virtualization (§5.9), media (§5.10). Verified
via `nix flake check`/dry-build — no VM functional test needed (see
"Testing scope" below for why).

**Consolidates what was originally scoped as two separate tasks** (package
list, and Throne as a custom package) into one: research turned up that
Throne is now a plain nixpkgs package with its own NixOS module
(`programs.throne`), not the custom AppImage/binary-wrapping derivation
`system-plan.md` §5.8 originally called for — no meaningfully separate
task remains once that's true. `system-plan.md` §5.8 is stale on this
point and gets corrected as part of this plan.

## Research findings that change what's in `system-plan.md` — verified fresh, not assumed

- **Throne is in nixpkgs** (`pkgs.throne`, 1.1.2, built from source — not
  from GitHub release binaries) with its own module,
  `programs.throne.enable = true` (+ `.tunMode.enable` if TUN mode is
  wanted — auto-configures polkit so DNS works without repeated
  password prompts, avoids needing `setuid`). `system-plan.md` §5.8's
  custom-derivation plan (AppImage/`autoPatchelfHook`/`nix-ld`) is
  obsolete; delete it, reference the real module instead.
- **`jetbrains.rubymine` doesn't exist — renamed to `jetbrains.ruby-mine`**
  (hyphenated, matches `rust-rover`'s naming). Not a removal: `nix search`
  looked empty because it doesn't honor `nixpkgs.config.allowUnfree = true`
  (that module option only applies to the `pkgs` instance built for the
  real NixOS host — bare `nix search` evaluates against nixpkgs' own
  default `allowUnfree = false` and silently drops unfree packages that
  fail to evaluate). Confirmed real via
  `NIXPKGS_ALLOW_UNFREE=1 nix eval --impure`: `jetbrains.ruby-mine`,
  version 2026.2. Worth a comment at the point of use warning future
  editors that `nix search` alone can't be trusted for unfree packages in
  this repo — a real, reusable gotcha, not a one-off.
- Everything else checked (`vscode`, `postman`, `google-chrome`,
  `telegram-desktop`, `wayvnc`, `remmina`) resolves under its expected
  name, no surprises.

## File Placement

`system-plan.md` §3's structure puts GUI/user-facing apps under
`modules/home/apps.nix` (home-manager) — but home-manager itself isn't
built in this repo yet (a separate, later task, per the user's own stated
priority order). Putting these packages in a **system-level**
`modules/nixos/desktop-apps.nix` (`environment.systemPackages`) now, with a
comment noting the likely future move into home-manager once that layer
exists, is the pragmatic choice — it gets the packages usable without
blocking on unrelated, larger, separately-prioritized work. Not a
permanent architectural decision, just sequencing.

```
modules/nixos/desktop-apps.nix
```

## Testing Scope — why no VM functional test

Unlike the disk/boot, Secure Boot, or secrets plans, this one has no
runtime *mechanism* to prove (no encryption chain, no signing chain, no
activation-time decryption) — it's a flat list of package references plus
two NixOS module enables (`programs.throne`, `programs.kdeconnect`) whose
own correctness is upstream's responsibility, already exercised by
nixpkgs' own CI. The real risk here is narrower and cheaper to check:
do the package names/attributes actually resolve and build. `nix flake
check` (eval) plus a dry-build (`--dry-run`, confirms derivations would
actually build/fetch without spending the time to do so) covers that
completely. Building a nixosTest to prove "vscode's binary exists in the
closure" would be ceremony this problem doesn't need.

## Verification

1. `nix search`/`nix eval --impure` (per the RubyMine gotcha above) to
   confirm every non-obvious package attribute name before writing the
   module — don't trust names carried over from `system-plan.md` without
   checking, since it's already been wrong twice in this one pass.
2. `nix flake check --no-build` — eval correctness.
3. `nix build .#nixosConfigurations.<throwaway-host>.config.system.build.toplevel --dry-run`
   — confirms real buildability without spending the time/disk on a full
   build. A throwaway host importing `desktop-apps.nix` (reuse
   `hosts/test-vm/`'s plain shape, or add a new minimal one — plan-time
   decision) is enough; no VM boot needed per "Testing Scope" above.

## Out of Scope

- Hyprland itself and its supporting daemons (waybar, mako, hyprlock,
  hypridle, hyprpaper, fuzzel, cliphist, polkit agent) — separate,
  larger, already-prioritized-later task.
- home-manager itself — separate, later task; this plan's packages may
  move there once it exists.
- Bluetooth manager: no action needed, `blueman` already confirmed and
  decided (2026-08-10) — not re-litigated here, `bluez`/`blueman` was
  already in `system-plan.md` §5.1's base-system list before this plan.
