# Hyprland Module + Packages Design

## Goal

Add the Hyprland compositor stack from `system-plan.md` §5.2 —
`programs.hyprland.enable` plus the surrounding package list (waybar,
fuzzel, mako, hyprlock/hypridle, grim/slurp/wf-recorder, hyprpaper,
cliphist, polkit agent, Qt theming) — as a declarative module, verified
via eval + dry-build, same testing depth as `desktop-apps.nix`. No real
Hyprland configuration content (keybinds, waybar widgets, theme, exec-once
autostart) — that needs home-manager dotfiles (`modules/home/*`), already
named as a separate, later task by both
`docs/superpowers/specs/2026-08-10-desktop-packages-design.md` ("Out of
Scope": "Hyprland itself and its supporting daemons... separate, larger,
already-prioritized-later task") and
`docs/superpowers/specs/2026-08-11-home-manager-design.md` ("Out of
Scope": "Hyprland itself and its supporting daemons... separate, larger,
already-prioritized-later task"). This round is that task, scoped the
same narrow way every prior round in this repo has been — and scoped
narrower than "Hyprland" might first suggest: module + packages only, not
config content, confirmed with the human partner before writing this spec.

## Research findings — verified against this repo's pinned nixpkgs, not assumed

Per `CLAUDE.md`'s "verify claims against real sources" rule and the same
discipline `desktop-apps.nix`'s design doc already established (it caught
`jetbrains.rubymine` → `jetbrains.ruby-mine` and Throne's real package
status this same way) — every package name below was checked with `nix
eval` against this flake's actual locked `nixpkgs`, not copied from
`system-plan.md` §5.2 verbatim.

- **`programs.hyprland.enable = true` already does more than "install the
  hyprland package."** Evaluated the module's real option defaults on
  this repo's pinned nixpkgs:
  - `xdg.portal.enable` defaults to `false` repo-wide, but
    `programs.hyprland.enable = true` sets it to `true` (confirmed by
    evaluating a real `nixosSystem` with only `programs.hyprland.enable =
    true;` set — `config.xdg.portal.enable` came back `true`).
  - `programs.hyprland.portalPackage` already defaults to
    `xdg-desktop-portal-hyprland` (version 1.4.1 in this repo's pin) — so
    that package does **not** get a separate `environment.systemPackages`
    entry; it's already wired in as the portal backend.
  - `programs.hyprland.xwayland.enable` defaults to `true`.
  - Net effect: `system-plan.md` §5.2 listing
    `hyprland, xdg-desktop-portal-hyprland` as two flat package bullets is
    slightly misleading — only `hyprland` needs a real declaration
    (`programs.hyprland.enable`), the portal comes for free.
- **`qt6ct` (bare) doesn't exist** — `nix eval` on it errors "has been
  renamed to/replaced by `qt6Packages.qt6ct`". Confirmed real name:
  `qt6Packages.qt6ct`.
- **`qt5ct` isn't a top-level attribute either** — real path is
  `libsForQt5.qt5ct`.
- **Kvantum needs both Qt5 and Qt6 variants, at different paths** —
  `libsForQt5.qtstyleplugin-kvantum` (pname `qtstyleplugin-kvantum5`) for
  Qt5 apps, `kdePackages.qtstyleplugin-kvantum` (pname
  `qtstyleplugin-kvantum`) for Qt6 apps. `system-plan.md` §5.2's single
  bullet "qt5/qt6ct + kvantum" collapses what's actually four packages.
- **Polkit agent: `hyprpolkitagent` chosen over `polkit-gnome`.**
  `system-plan.md` §5.2 left this an explicit either/or
  ("hyprpolkitagent или polkit-gnome"). Both attributes resolve
  (`polkit_gnome` → pname `polkit-gnome`, confirmed to still exist, not
  archived like `nekoray` was), but `hyprpolkitagent` is Hyprland's own
  project, purpose-built and actively maintained for this exact
  compositor, rather than a GNOME component borrowed outside its native
  DE. This decision corrects `system-plan.md` §5.2's open either/or into
  a real choice.
- **`playerctl` is already in `modules/nixos/desktop-apps.nix`** (§5.10
  Медиа, confirmed by reading the file) — not duplicated here, even
  though `system-plan.md` §5.10 describes it as "медиаклавиши через
  Waybar/Hyprland-бинды." No overlap between this module and
  `desktop-apps.nix`.

## Module

```
modules/nixos/hyprland.nix
```
```nix
{ pkgs, ... }:
{
  programs.hyprland.enable = true;

  environment.systemPackages = with pkgs; [
    waybar
    fuzzel
    mako
    hyprlock
    hypridle
    grim
    slurp
    wf-recorder
    hyprpaper
    cliphist
    wl-clipboard
    hyprpolkitagent
    libsForQt5.qt5ct
    qt6Packages.qt6ct
    libsForQt5.qtstyleplugin-kvantum
    kdePackages.qtstyleplugin-kvantum
  ];
}
```
No module arguments beyond the implicit `pkgs` — same shape as
`desktop-apps.nix`, unlike `disko-luks-btrfs.nix`'s explicit
parameterization (nothing here is host-specific).

## Test Host

```
hosts/test-hyprland/
  configuration.nix   # mirrors hosts/test-desktop-apps/'s shape exactly:
                       # ext4 /dev/vda1 + grub, no qemu-vm.nix import
```
Imports `boot.nix` + `hyprland.nix`. No `nixpkgs.config.allowUnfree`
expected to be needed — every package above is FOSS, but this gets
confirmed for real during implementation (dry-build fails loudly and
specifically if wrong, same as the `desktop-apps.nix` round's own
discovery process).

## Testing — why eval + dry-build, no VM boot, no real build

Same reasoning as `desktop-apps.nix`'s "Testing Scope": `programs.hyprland.enable`
is structurally the same kind of thing as `programs.throne.enable` /
`programs.kdeconnect.enable`, both already proven there — a NixOS module
enable plus a flat package list, no custom activation-time machinery like
home-manager's own activation script needed a real build to catch. The
real risk is narrower and cheaper: do the package names/attributes
actually resolve and build, which the Research findings above already
partly de-risked by hand. No VM boot is possible or useful here regardless
— Hyprland needs a real GPU/display to do anything observable, and no
agent in this sandbox can "look at" a compositor; that's explicitly a
human-only verification step once real dotfiles exist (see
`CLAUDE.md`: "Агент не может 'посмотреть глазами' на Hyprland").

1. `nix flake check --no-build` — eval-only, routine after every edit.
2. `nixos-rebuild dry-build --flake .#test-hyprland` (or `nix build
   .#nixosConfigurations.test-hyprland.config.system.build.toplevel
   --dry-run` if `nixos-rebuild` isn't on `PATH`, per established
   precedent) — confirms every package attribute actually resolves and
   would build/fetch, without spending the time to do so.

## Out of Scope (unchanged from prior rounds' own lists, still true)

- Real Hyprland configuration content — `hyprland.conf`/`hyprland.lua`,
  keybinds, `exec-once` autostart entries (including
  `hypr/quick-translate.lua`'s eventual wiring, and `kdeconnectd`
  autostart already noted as needed in `desktop-apps.nix`'s KDE Connect
  section), waybar widget config, mako notification styling, hyprlock/
  hypridle timeout policy, hyprpaper wallpaper path. All of this needs
  `modules/home/*` (home-manager dotfiles), which exists as infrastructure
  now (`docs/superpowers/specs/2026-08-11-home-manager-design.md`) but has
  no content yet — a separate, later task.
- `hosts/mimir/`'s real Hyprland session — needs a real user
  (`home-manager.users.<name>`), which doesn't exist yet, same boundary
  every other "real hardware" gap in this repo already has.
- Visual/behavioral verification of Hyprland itself — not possible from
  this sandbox at all, real-hardware-and-human-eyes-only, unchanged by
  this or any future round until someone is physically at a booted
  `mimir`.
