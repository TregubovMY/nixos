# Parameterized disko disk layout: GPT -> ESP -> two LUKS2 containers
# (root: btrfs with root/home/nix subvolumes; swap: a dedicated partition,
# NOT a btrfs subvolume swapfile). Full rationale for the two-container
# split (vs. swap-as-subvolume) and the resumeDevice mechanism below:
# docs/superpowers/specs/2026-08-08-disk-boot-foundation-design.md
# "Disk Architecture" and "Hibernate" sections. Short version: a btrfs
# swapfile's hibernate-resume behavior has a real history of breaking
# under boot.initrd.systemd.enable (nixpkgs issue #213122); a dedicated
# LUKS-wrapped swap partition with disko's own `resumeDevice = true` flag
# sidesteps that whole bug class.
#
# `device` and `swapSize` are parameters (not hardcoded) so the exact same
# module is reused by both hosts/test-disko-luks/ (device = "/dev/vda",
# a small swapSize to fit the throwaway test disk) and, later, the real
# hosts/mimir/ (device = "/dev/sdb", swapSize = "34G" to match the old
# .trash/disko.nix's number — adjust if mimir's actual RAM differs, since
# hibernate needs swap >= RAM).
{ device, swapSize ? "34G" }:
{
  disko.devices = {
    disk = {
      main = {
        inherit device;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            # Explicit `priority` on every partition (not relying on
            # attribute-name sort order) per disko's own migration docs
            # (docs/table-to-gpt.md): the new `type = "gpt"` layout uses
            # `priority` to determine the actual partition number/order,
            # not declaration order or key name. cryptswap gets a fixed
            # size and priority 2 so it's carved out BEFORE cryptroot
            # claims the rest via `size = "100%"` at priority 3.
            ESP = {
              priority = 1;
              size = "1024M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            cryptswap = {
              priority = 2;
              size = swapSize;
              content = {
                type = "luks";
                name = "cryptswap";
                settings.allowDiscards = true;
                # No settings.keyFile and no randomEncryption: this must be
                # a fixed-passphrase LUKS container, not disko's random-key
                # swap encryption — randomEncryption makes hibernation
                # impossible outright (confirmed via disko issue #604 and
                # the NixOS wiki's Swap page: the key doesn't survive a
                # reboot, so a hibernate image written under one random key
                # can never be read back). Interactive passphrase prompt by
                # default (no passwordFile set here) — real install must
                # use the SAME passphrase as cryptroot below, see this
                # plan's Global Constraints.
                content = {
                  type = "swap";
                  resumeDevice = true; # disko's own flag: sets
                    # boot.resumeDevice to this (decrypted, mapped) device
                    # declaratively — see disko's lib/types/swap.nix.
                };
              };
            };
            cryptroot = {
              priority = 3;
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                settings.allowDiscards = true;
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "/root" = {
                      mountpoint = "/";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    "/home" = {
                      mountpoint = "/home";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    "/nix" = {
                      mountpoint = "/nix";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
