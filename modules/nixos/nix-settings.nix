# Enables nix-command + flakes system-wide -- gap found live: every
# nixos-install/nixos-rebuild call needed a manual NIX_CONFIG workaround
# (nixos-install/nixos-rebuild are their own wrapper scripts, not `nix`
# itself, so they don't accept --extra-experimental-features). Once this
# is deployed, the installed system's own /etc/nix/nix.conf has both
# enabled, so no more per-command workarounds are needed for any future
# `nix`/`nixos-rebuild` call on this host.
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Автоочистка стора — запрошено live 2026-08-13, на фоне явного
  # дискового бюджета из CLAUDE.md (машина разработки без запасного
  # диска, ENOSPC у случайного процесса — угроза самой системе, не
  # просто неудобство).
  #
  # --delete-older-than, а НЕ `nix-collect-garbage -d`: последнее рушит
  # все прошлые generations сразу же, без окна на откат. С
  # --delete-older-than старые generations (и их непереживающие GC
  # store-пути) чистятся только по возрасту, оставляя реальную
  # возможность отката на недавние поколения.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Дедупликация одинаковых файлов в сторе через хардлинки — чистый
  # выигрыш по месту почти без цены (небольшой CPU-оверхед на build).
  nix.settings.auto-optimise-store = true;

  # Подстраховка на лету: если во время сборки свободное место падает
  # ниже min-free, nix-daemon сам чистит старое (после nix.gc'а есть что
  # чистить -- --delete-older-than освобождает generations под GC) до
  # max-free, не дожидаясь следующего еженедельного прогона gc. Прямое
  # смягчение ENOSPC-риска, описанного в CLAUDE.md.
  nix.settings.min-free = 2 * 1024 * 1024 * 1024; # 2GiB
  nix.settings.max-free = 10 * 1024 * 1024 * 1024; # 10GiB

  # No trusted-users entry here on purpose -- `root` already is one by
  # Nix's own default (man nix.conf), and every `nixos-rebuild
  # switch`/`build-vm` in this repo already runs via `sudo`, i.e. already
  # talks to nix-daemon as a trusted user. That's what makes the
  # `impure-env` proxy recipe in docs/NIX-HOWTO.md ("Собрать пакет,
  # который блокируют без прокси") work with zero permanent nix.conf
  # change -- found live 2026-10-19 chasing RubyMine's fetchurl
  # (download.jetbrains.com answers HTTP 451 for RU IPs, see
  # hosts/common.nix's desktopApps.rubymine.enable comment). Adding `max`/
  # `@wheel` here explicitly would do nothing this doesn't already cover,
  # while matching man nix.conf's own warning ("equivalent to giving that
  # user root access") to a wider set of commands than just `sudo
  # nixos-rebuild`.
}
