# Shared boot-loader module: systemd-boot + the modern systemd-based
# initrd. boot.initrd.systemd.enable is needed for a working LUKS unlock
# prompt under systemd-boot on current NixOS, and (per the design doc's
# Hibernate section) is also the initrd that's able to auto-detect a
# resume device via EFI variables on recent NixOS versions. No separate
# luks.nix module: disko's own module already registers both LUKS
# containers (boot.initrd.luks.devices) from disko-luks-btrfs.nix's own
# description — there is nothing LUKS-specific left to configure here.
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;

  # Ограничить число generations, которые остаются загрузочными пунктами
  # в меню systemd-boot -- без этого еженедельный nix.gc (nix-settings.nix)
  # чистит store, но старые ядра/initrd всё равно копятся на ESP, пока
  # жива их generation-ссылка, а ESP обычно маленький. Держит то же число,
  # что secure-boot.nix задаёт для lanzaboote-хостов.
  boot.loader.systemd-boot.configurationLimit = 5;
}
