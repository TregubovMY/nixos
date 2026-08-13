# Full-system VM rehearsal -- NOT hosts/mimir/ (no real
# hardware-configuration.nix, no secrets.nix -- sops needs a real SSH
# host key, chicken-and-egg for a VM that doesn't exist until installed;
# see docs/superpowers/plans/tingly-doodling-phoenix.md), and broader in
# scope than hosts/mimir-vm-rehearsal/ (which only proved disko+LUKS+
# btrfs+Secure Boot boot). This host pulls in everything else this repo
# has actually built: modules/nixos/hyprland.nix, desktop-apps.nix,
# dev-databases.nix, podman.nix, home-manager.nix at the system level
# (modules/nixos/hyprland.nix is NOT optional here -- home-manager's own
# hyprland.nix below deliberately sets package = null, expecting the
# NixOS module to provide the actual Hyprland binary; missing this import
# once already produced a real "Hyprland: command not known" during the
# live rehearsal), plus a real home-manager user
# (max, matching the username already anticipated by
# docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md)
# importing hyprland.nix/neovim.nix/shell.nix/zellij.nix/ghostty.nix/
# direnv.nix/mise.nix -- the actual day-to-day desktop config, not just
# the disk/boot layer.
{ pkgs, ... }:
{
  imports = [
    ./disk-config.nix
    ../../modules/nixos/secure-boot.nix
    ../../modules/nixos/hyprland.nix
    ../../modules/nixos/greetd.nix
    ../../modules/nixos/nix-settings.nix
    ../../modules/nixos/desktop-apps.nix
    ../../modules/nixos/dev-databases.nix
    ../../modules/nixos/podman.nix
    ../../modules/nixos/home-manager.nix
    ../../modules/nixos/nix-ld.nix
  ];

  # Same gap as hosts/mimir-vm-rehearsal/ -- no hardware-configuration.nix,
  # so the initrd needs the virtio block driver declared by hand. See
  # that host's configuration.nix for the full explanation.
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_scsi" ];

  # desktop-apps.nix pulls in unfree packages (rubymine, google-chrome,
  # vscode, etc, per CLAUDE.md "Правила для пакетов") -- hosts/mimir/
  # already sets this, mirrored here for the same reason.
  nixpkgs.config.allowUnfree = true;

  # jetbrains.ruby-mine's fetchurl hits HTTP 451 from
  # download.jetbrains.com (geo/sanctions block) -- real, will recur on
  # the real hosts/mimir/ install too, not a VM-only quirk. system-plan.md
  # §5.8's programs.throne (already in desktop-apps.nix) is the eventual
  # real fix, but its VLESS config lives in Bitwarden, not this repo, so
  # it isn't configured yet and wouldn't help nixos-install's own fetch
  # anyway. Not editing desktop-apps.nix itself (shared with the real
  # host, where this needs a real decision once Throne is set up) --
  # instead, overlay just this host's jetbrains.ruby-mine to an empty
  # stub so environment.systemPackages still evaluates but doesn't
  # actually try to fetch anything. VM-rehearsal-only workaround.
  nixpkgs.overlays = [
    (final: prev: {
      jetbrains = prev.jetbrains // {
        ruby-mine = prev.runCommand "ruby-mine-stub-unavailable-in-this-vm" { } ''
          mkdir -p "$out/bin"
        '';
      };
    })
  ];

  networking.hostName = "mimir-vm-full";

  # Gap found live: modules/home/shell.nix's programs.zsh.enable = true
  # (home-manager) configures zsh but does NOT change the user's actual
  # login shell -- that's users.users.<name>.shell, a NixOS-level,
  # host-specific setting (same "username is host-specific" boundary
  # CLAUDE.md already draws elsewhere, so this can't live in shell.nix
  # itself). Booting without it left `max` on bash by default, zsh
  # installed but unused. programs.zsh.enable = true at the system level
  # too (not just home-manager's) -- registers zsh in
  # environment.shells/etc/shells, which users.users.*.shell expects.
  programs.zsh.enable = true;

  # Rehearsal-only convenience, same as hosts/mimir-vm-rehearsal/'s root
  # password -- NOT how hosts/mimir/ should ever be configured (real
  # install needs a real decision about auth, see system-plan.md §7).
  users.users.max = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "max";
    shell = pkgs.zsh;
  };

  home-manager.users.max = {
    imports = [
      ../../modules/home/hyprland.nix
      ../../modules/home/neovim.nix
      ../../modules/home/shell.nix
      ../../modules/home/zellij.nix
      ../../modules/home/ghostty.nix
      ../../modules/home/direnv.nix
      ../../modules/home/mise.nix
    ];
    home.stateVersion = "24.05";
  };

  system.stateVersion = "24.05";
}
