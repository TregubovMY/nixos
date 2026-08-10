# Throwaway verification host for the secrets (sops-nix) design — NOT a
# real target machine, and NOT hosts/mimir/. Exists only to prove
# secrets.nix evaluates on a real host closure without conflicts — the
# real functional proof (does sops-nix actually decrypt something) is
# Task 3's separate, self-contained VM test, which doesn't use this host.
{ ... }:
{
  imports = [
    ../../modules/nixos/secrets.nix
    ../../modules/nixos/boot.nix
  ];

  fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
  boot.loader.grub.device = "/dev/vda";

  system.stateVersion = "24.05";
}
