# nixos

Моя NixOS-конфигурация (flake): зашифрованный диск (LUKS + btrfs), Secure
Boot, рабочий стол Hyprland + DankMaterialShell, home-manager, и песочница,
в которой работают AI-агенты.

| Документ | О чём |
|---|---|
| [docs/INSTALL.md](docs/INSTALL.md) | установка — в виртуалку и на машину, что сделать после |
| [docs/NIX-HOWTO.md](docs/NIX-HOWTO.md) | базовое в Nix: добавить пакет/модуль/машину, обновить, откатить |
| [docs/REFERENCE.md](docs/REFERENCE.md) | подробности и история решений по каждому компоненту |
| [system-plan.md](system-plan.md) | архитектура и почему так |
| [TODO.md](TODO.md) | что ещё не сделано или не проверено |
| [CLAUDE.md](CLAUDE.md) | правила для агента, работающего в этом репозитории |

## Устройство

```
flake.nix              входы (nixpkgs, home-manager, disko, lanzaboote, DMS, DankCalendar)
hosts/common.nix       всё общее для любой машины
hosts/<машина>/        configuration.nix (имя машины) + facter.json (её железо)
hosts/disk-config.nix  разметка диска (диск и размер swap задаются при установке)
modules/nixos/         системные модули: база, десктоп, Hyprland, Secure Boot, песочница…
modules/home/          пользовательские: shell, neovim, ghostty, Hyprland/DMS…
bin/                   install-host, agent-sandbox, vm-ssh-on
```

Машины: `mimir` (ноутбук). Новая — `bin/install-host <имя> <диск>`.

## Песочница агентов

AI-агенты (Claude Code, OpenCode) и доски (kandev, dsh) работают в
**rootless-контейнере podman**, а не прямо на машине. Агент видит только
папки проектов из конфига, свой домашний каталог и `/nix/store` только для
чтения; ваш `~` (SSH-ключи, браузер, другие проекты) ему не виден. Сеть
открыта — граница защиты в файлах и секретах.

Одна песочница на сферу — по конфигу в `~/.config/agent-sandbox/projects/`:

```ini
# work.conf  (study.conf, personal.conf — то же со своими папками и портами)
dir       = ~/code/work/main
mount     = ~/code/work/other
publish   = 38429:38429
autostart = kandev start --backend-port 38429
publish   = 3080:3080
autostart = dsh web --no-open --port 3081 --trusted-host 127.0.0.1:3080
autostart = socat TCP-LISTEN:3080,fork,reuseaddr TCP:127.0.0.1:3081
publish   = 4200:4200                                     # opencode web — по желанию
autostart = opencode web --hostname 0.0.0.0 --port 4200
```

```bash
agent-sandbox up @work                 # kandev → http://127.0.0.1:38429
agent-sandbox attach @work -- claude   # Claude Code в той же песочнице
agent-sandbox down @work
agent-sandbox ~/code/proj -- claude    # разово, без конфига
```

Первый раз в каждой песочнице: `claude login`, `gh auth login`,
`dsh-setup` (dsh и плагины), в kandev профиль Claude Code →
**CLI passthrough**. Языки и гемы с хоста подключаются только для чтения —
повторно не скачиваются. Подробно — `docs/REFERENCE.md`, разделы про
песочницу.

`claude` и `opencode` есть и прямо на машине — для разовых вопросов; для
работы с кодом запускайте их через `agent-sandbox`.

## Горячие клавиши (сверх стандартных DMS)

| Клавиши | Действие |
|---|---|
| SUPER+/ | шпаргалка всех клавиш DMS |
| SUPER+T | терминал (ghostty) |
| SUPER+X | меню питания (выход, перезагрузка) |
| CapsLock | переключить раскладку en/ru |
| Print / SHIFT+Print / SUPER+Print | скриншот области / экрана / окна |
| SUPER+SHIFT+Print | скриншот области с рисованием (swappy) |
| SUPER+SHIFT+R / SUPER+CTRL+R | запись области / экрана (повтор — стоп) |
| SUPER+ALT+T | перевести выделенный текст (Dialect) |
