# nixos

Моя NixOS-конфигурация (flake): зашифрованный диск (LUKS + btrfs), Secure
Boot, рабочий стол Hyprland + DankMaterialShell, home-manager, и песочница,
в которой работают AI-агенты.

| Документ | О чём |
|---|---|
| [docs/INSTALL.md](docs/INSTALL.md) | установка — в виртуалку и на машину, что сделать после |
| [docs/NIX-HOWTO.md](docs/NIX-HOWTO.md) | базовое в Nix: добавить пакет/модуль/машину, обновить, откатить |
| [docs/DAILY-WORKFLOW.md](docs/DAILY-WORKFLOW.md) | как пользоваться день в день: редактор, файловый менеджер, горячие клавиши, растущий FAQ |
| [docs/AI-AGENTS.md](docs/AI-AGENTS.md) | работа с AI-агентами — прямо на машине и в песочнице |
| [docs/AGENT-SANDBOX.md](docs/AGENT-SANDBOX.md) | песочница агентов — команды, конфиг, шпаргалка |
| [docs/REQUESTS.md](docs/REQUESTS.md) | журнал просьб и косяков: что просили, статус, где сделано — для переноса на другую машину |
| [docs/FEATURES.md](docs/FEATURES.md) | фишки системы — что повторить на другой машине/ОС, чтобы не потерять удобство |
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

## Секреты (Bitwarden)

Пароли, ключи, токены — не в git (sops-nix из плана выведен целиком, см.
`system-plan.md` §6): всё живёт в Bitwarden как secure note, на новой
машине копируется руками в нужный файл. Общий принцип один и тот же для
всего из списка ниже — заводить новый механизм под каждый следующий
случай не нужно.

| Что | Куда (secure note в Bitwarden) | Что сделать на машине |
|---|---|---|
| SSH-ключи и `~/.ssh/config` (Host-блоки, IdentityFile) | текст `~/.ssh/config` целиком + сами ключи | скопировать руками в `~/.ssh/`, `chmod 600` на приватные ключи |
| Прокси (Throne, VLESS-Reality) | конфиг-строка/QR | импорт в приложении Throne — `docs/INSTALL.md` п.4 |
| GPG-ключ (подпись коммитов) | экспорт ключа | `gpg --import`, см. `system-plan.md` §6 |
| Логин в приватный docker-registry | `registry` + `username` + `password/token` | `docker login --compat-auth-file ~/.docker/config.json <registry>` и ввести логин/пароль из Bitwarden (`docker` уже алиас на `podman`, см. `modules/nixos/podman.nix`; `--compat-auth-file` пишет сразу в формате и по пути, которые ждёт `docker-compose`, а не в эфемерный `podman`-овский `auth.json` под `/run/user/…`, который чистится при каждом логауте/перезагрузке) |

Почему именно так, а не через `podman login` без флага — и общее решение
про sops-nix/Bitwarden — `system-plan.md` §6/§7, `docs/REFERENCE.md`.

## AI-агенты и песочница

Claude Code/OpenCode (и доски kandev/dsh) работают изолированно от
остальной машины — **`docs/AI-AGENTS.md`** (вход), **`docs/AGENT-SANDBOX.md`**
(полная шпаргалка: команды, конфиг `@имя`, IDE).

## День в день

Горячие клавиши, навигация по файлам (`z`/`y`/редактор), версии языков,
docker-compose, растущий FAQ — **`docs/DAILY-WORKFLOW.md`**.
