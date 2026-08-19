# Declarative desktop package list — system.plan.md §5.4-§5.10, §5.1.1,
# §5.1.2. Placed here (system-level environment.systemPackages), NOT
# under modules/home/ as system-plan.md §3's aspirational structure
# eventually wants: home-manager isn't built in this repo yet (separate,
# later task per explicit priority order, 2026-08-10). This is a
# sequencing choice, not a permanent one — revisit once home-manager
# exists.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # §5.4 IDE / редакторы
    # jetbrains.ruby-mine, NOT jetbrains.rubymine (renamed upstream,
    # hyphenated to match rust-rover's convention — the old name doesn't
    # exist anymore, not even as an alias/throw). `nix search` looked
    # empty for BOTH names because it doesn't honor
    # nixpkgs.config.allowUnfree=true (only applies to a real pkgs
    # instance, not bare `nix search`'s own hermetic eval) — don't take
    # `nix search`'s silence on an unfree package as evidence it's gone;
    # verify with `NIXPKGS_ALLOW_UNFREE=1 nix eval --impure` instead.
    jetbrains.ruby-mine
    vscode
    # Android Studio — запрошено live 2026-08-19, вне исходной нумерации
    # system-plan.md §5.4. Unfree, тот же allowUnfree-путь, что и
    # RubyMine/Chrome/VSCode/Postman (см. nixpkgs.config.allowUnfree в
    # hosts/mimir/configuration.nix).
    android-studio

    # §5.5 AI coding agents — host-level packages for one-off interactive
    # use (system-plan.md §5.5); the sandboxed/per-project path is
    # separate, see modules/nixos/packages/agent-sandbox.nix and README.md.
    claude-code
    opencode

    # §5.6 Коммуникация / браузер
    telegram-desktop
    google-chrome
    firefox

    # §5.7 API / сеть
    postman

    # §5.1.1 Удалённый стол (обе стороны — сервер и клиент, решено
    # 2026-08-10)
    wayvnc
    remmina

    # §5.10 Медиа
    mpv
    yt-dlp
    pavucontrol
    playerctl

    # §5.9 Виртуализация — OVMF/spice-vdagent packages; libvirtd/
    # virt-manager themselves are enabled as services/programs below, not
    # packages here
    OVMFFull
    spice-vdagent

    # Заметки / трекинг времени / карточки — запрошено live 2026-08-13
    # (obsidian/awatcher) и 2026-08-19 (anki), вне исходной нумерации
    # system-plan.md §5.x.
    obsidian
    anki
    # awatcher, NOT the plain `activitywatch` package -- проверено live:
    # activitywatch's own aw-watcher-window исторически X11-only, а под
    # Wayland/Hyprland требует отдельный aw-watcher-window-wayland,
    # который сами авторы ActivityWatch называют слабо поддерживаемым
    # (github.com/ActivityWatch/aw-watcher-window-wayland). awatcher
    # (github.com/2e3s/awatcher) — самостоятельный, лучше поддерживаемый
    # трекер с полной поддержкой Hyprland через протокол wlr
    # foreign-toplevel-management (окна) + ext-idle-notify-v1 (AFK), и
    # умеет работать в bundle-режиме (aw-server-rust + сам трекер в одном
    # бинарнике, без отдельной установки activitywatch) -- поэтому
    # только этот пакет, без activitywatch/aw-qt рядом.
    awatcher
  ];

  # §5.1.2 Телефон ↔ ПК (решено 2026-08-10) — module auto-provides
  # kdePackages.kdeconnect-kde and opens the needed firewall ports
  # (TCP/UDP 1714-1764) itself; simpler than doing it by hand in
  # networking.firewall.
  programs.kdeconnect.enable = true;

  # §5.8 Прокси-клиент — Throne (nekoray's successor). NOT a custom
  # AppImage/binary derivation as system-plan.md originally described:
  # verified (2026-08-10) it's now a plain nixpkgs package built from
  # source, with its own NixOS module that already solves the hard parts
  # (wraps the sing-box-backed core with the right capabilities via
  # setcap, auto-configures polkit for TUN-mode DNS so it doesn't need
  # repeated password prompts). tunMode.enable avoids needing full
  # setuid-root.
  programs.throne = {
    enable = true;
    tunMode.enable = true;
  };

  # §5.9 Виртуализация
  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  # No libvirtd/kvm group membership here — no real user exists yet in
  # this repo (hosts/mimir/ doesn't exist, home-manager doesn't exist).
  # That's a real-install-time step once a real user is defined, not
  # this module's job.
}
