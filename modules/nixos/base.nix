# Base system layer, system-plan.md §5.1: what a laptop needs to be usable
# right after the first boot, before any desktop/dev modules matter.
#
# Found missing while preparing hosts/mimir for a real install
# (2026-10-05): §5.1 listed networkmanager / bluez+blueman / base CLI
# tools, but no module ever enabled them. `nix eval` of mimir-vm-full
# showed networking.networkmanager.enable = false -- the VM rehearsals
# never noticed because QEMU's wired virtio NIC works with the default
# dhcpcd. On real hardware that means no Wi-Fi after install.
{ config, pkgs, ... }:
{
  # NetworkManager, not plain wpa_supplicant (networking.wireless): Wi-Fi
  # profiles via nmcli/nmtui and DMS's own network widget, which talks to
  # NetworkManager over D-Bus. Wi-Fi passwords live in NM profiles
  # (system-plan.md §6 table).
  networking.networkmanager.enable = true;

  # nixos-facter (hosts/mimir, hardware.facter.reportPath) turns on
  # dhcpcd per detected interface via networking.interfaces.<n>.useDHCP
  # (nixpkgs nixos/modules/hardware/facter/networking/default.nix). With
  # NetworkManager managing interfaces that would be a second DHCP client
  # fighting it, so the facter DHCP part is switched off here. The option
  # exists whether or not a host actually uses facter (the facter module
  # is always part of nixpkgs' module list), so this is safe everywhere.
  hardware.facter.detected.dhcp.enable = false;

  # Bluetooth itself is enabled by facter when the report contains a
  # bluetooth controller (facter/bluetooth.nix); blueman is the GUI for it
  # (§5.1 explains why blueman and not overskride). Following the
  # hardware flag instead of forcing it on keeps hosts without bluetooth
  # (VMs) free of a useless tray applet.
  services.blueman.enable = config.hardware.bluetooth.enable;

  # Battery level and power profiles for the DMS bar (it reads both over
  # D-Bus). power-profiles-daemon rather than TLP: they conflict, and
  # power-profiles-daemon is what desktop shells, DMS included, can switch
  # from the UI.
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;

  # Firmware updates (BIOS/EC/SSD) through LVFS: `fwupdmgr refresh &&
  # fwupdmgr update`. Matters for a laptop, costs nothing when idle.
  services.fwupd.enable = true;

  # §5.1 base CLI. ripgrep/fd/git also come with home-manager's neovim
  # module for the user, but they belong here too: they must work for root
  # and in a TTY rescue session without home-manager.
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    htop
    btop
    ripgrep
    fd
    fzf
    jq
    tree
    unzip
    gnupg
  ];
}
