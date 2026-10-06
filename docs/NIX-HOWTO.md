# Nix: как сделать базовые вещи

Все команды — из корня репозитория (`~/code/nixos`). Любое изменение
конфигурации = правка `.nix`-файла → проверка → применение → коммит.

## Применить изменения

```bash
make check                                       # = nix flake check --no-build, секунды; ловит ошибки
sudo nixos-rebuild switch --flake .#$(hostname)  # собрать и переключиться
```

| Команда | Что делает |
|---|---|
| `nixos-rebuild switch` | применить сейчас и сделать версией по умолчанию в меню загрузки |
| `nixos-rebuild test` | применить сейчас, но после перезагрузки вернётся прошлая — для экспериментов |
| `nixos-rebuild boot` | применится только после перезагрузки |
| `nixos-rebuild dry-build` | показать, что будет скачано/собрано, ничего не меняя |

Flake видит только файлы, известные git: новый файл сначала `git add`
(коммитить не обязательно).

## Откатиться

- В меню загрузки выбрать предыдущую версию (их там несколько).
- Или: `sudo nixos-rebuild switch --rollback`.
- Посмотреть версии: `nix-env --list-generations -p /nix/var/nix/profiles/system`.

## Найти пакет

```bash
nix search nixpkgs ripgrep          # или https://search.nixos.org/packages
```
Несвободные (unfree) пакеты `nix search` не показывает — проверять так:
`NIXPKGS_ALLOW_UNFREE=1 nix eval --impure nixpkgs#vscode.version`.

## Добавить программу

**Для всех пользователей / системную** — в список `environment.systemPackages`
подходящего модуля в `modules/nixos/`:
- базовые CLI — `modules/nixos/base.nix`;
- десктопные приложения — `modules/nixos/desktop-apps.nix`.

```nix
environment.systemPackages = with pkgs; [
  ripgrep
  htop   # ← новая строка
];
```

**Только для себя (пользователя max)** — `home.packages` в модуле
`modules/home/` (например `modules/home/shell.nix`):

```nix
home.packages = with pkgs; [ jq ];
```

Попробовать без установки: `nix shell nixpkgs#cowsay -c cowsay hi` или
`nix run nixpkgs#cowsay -- hi`.

## Настроить программу

Сначала поискать готовую опцию — у многих программ есть модуль:
- системные: https://search.nixos.org/options (`services.*`, `programs.*`);
- пользовательские (home-manager): https://home-manager-options.extranix.com
  (`programs.git.*`, `programs.zsh.*`, …).

Пример — свой алиас в zsh (`modules/home/shell.nix`):
```nix
programs.zsh.shellAliases.ll = "eza -la";
```

## Добавить свой модуль

1. Создать `modules/nixos/<тема>.nix` (системное) или `modules/home/<тема>.nix`
   (пользовательское):
   ```nix
   # Зачем этот модуль и почему так (правило репозитория — CLAUDE.md).
   { pkgs, ... }:
   {
     services.tailscale.enable = true;
   }
   ```
2. Подключить: системный — в `imports` в `hosts/common.nix` (для всех
   машин) или в `hosts/<машина>/configuration.nix` (только для неё);
   пользовательский — в `home-manager.users.max.imports` в `hosts/common.nix`.
3. `git add`, `make check`, `nixos-rebuild switch`.

## Отличие одной машины от другой

Общее — `hosts/common.nix`; только для одной машины — её
`hosts/<имя>/configuration.nix`:
```nix
{
  imports = [ ../common.nix ];
  networking.hostName = "work-pc";
  desktopApps.rubymine.enable = true;   # например, только здесь
}
```
Новая машина — просто `bin/install-host <имя> <диск>` (`INSTALL.md`).

## Обновить версии пакетов

Версии всего зафиксированы в `flake.lock`.
```bash
nix flake update                  # обновить всё (nixpkgs, home-manager, …)
nix flake update nixpkgs          # только nixpkgs
make check && sudo nixos-rebuild switch --flake .#$(hostname)
git add flake.lock && git commit -m "flake.lock: update nixpkgs"   # отдельным коммитом
```
Если после обновления что-то сломалось — откат (выше) и `git checkout flake.lock`.

## Освободить место

```bash
sudo nix-collect-garbage --delete-older-than 14d   # удалить старые версии системы и мусор
nix store optimise                                 # склеить одинаковые файлы
```
Автоочистка раз в неделю уже включена (`modules/nixos/nix-settings.nix`).
После удаления старых версий откатиться на них уже нельзя.

## Секреты

Пароли, ключи и токены **не кладутся в репозиторий** (он публичный): они в
Bitwarden. В конфиге — только ссылки на файлы с ними.

## Если что-то не собирается

Читать ошибку до конца: в ней файл и строка, но причина может быть в
модуле, который этот файл подключает. Полезно:
```bash
nix eval .#nixosConfigurations.$(hostname).config.services.openssh.enable   # значение любой опции
nix repl                                                                    # :lf . — интерактивно
```
