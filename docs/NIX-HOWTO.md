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

## Поставить готовый бинарник с GitHub (не из nixpkgs)

Сначала всегда проверить `nix search nixpkgs <имя>` — если пакета там
нет (частый случай для узких/новых инструментов), оборачивать бинарник
в свою derivation в `modules/nixos/packages/<имя>.nix`
(правило — CLAUDE.md "Правила для пакетов"), не качать и не запускать
руками: тогда он версионируется, попадает под `nix-collect-garbage` как
обычный пакет, и `autoPatchelfHook` сам поправит ему динамический
линковщик/RPATH под NixOS (без этого готовый Linux-бинарник не
запустится — NixOS не FHS-дистрибутив, см. раздел про `nix-ld` в
system-plan.md).

Готовый рабочий пример в этом репо — `modules/nixos/packages/kandev.nix`
(скачивает прямо с реестра npm, но техника для GitHub releases та же):

```nix
{ lib, stdenv, fetchurl, autoPatchelfHook }:

stdenv.mkDerivation rec {
  pname = "мой-инструмент";
  version = "1.2.3";

  src = fetchurl {
    url = "https://github.com/<owner>/<repo>/releases/download/v${version}/<asset>-linux-x64.tar.gz";
    hash = ""; # см. ниже, как получить
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ]; # если бинарнику нужен libstdc++ и т.п.

  installPhase = ''
    mkdir -p $out/bin
    cp мой-инструмент $out/bin/
  '';

  meta = {
    description = "...";
    homepage = "https://github.com/<owner>/<repo>";
    platforms = [ "x86_64-linux" ];
  };
}
```

Получить `hash` (nix откажется собирать с пустым — подскажет реальный
при первой попытке, либо сразу так):
```bash
nix store prefetch-file --json https://github.com/<owner>/<repo>/releases/download/v1.2.3/<asset>-linux-x64.tar.gz | jq -r .hash
```

Подключить: `environment.systemPackages` нужного модуля в
`modules/nixos/` через `pkgs.callPackage ./packages/<имя>.nix { }`
(как `kandev.nix` подключён в `modules/nixos/packages/agent-sandbox.nix`).

Если инструмент нужен **разово, не как часть системы** — быстрее без
derivation вообще, раз `nix-ld` уже включён (`modules/nixos/nix-ld.nix`):
```bash
curl -LO https://github.com/<owner>/<repo>/releases/download/v1.2.3/<asset>-linux-x64.tar.gz
tar xzf <asset>-linux-x64.tar.gz && ./мой-инструмент   # просто запускается
```
Минус — не версионируется и не защищён от `nix-collect-garbage`
(обычный файл в `$HOME`), годится только для одноразовой/временной штуки.

## Старый компилятор для конкретного проекта

Симптом: `mise install ruby@2.5.1` (или любой другой старый язык/гем с
native extensions) падает на сборке с ошибками вида "incompatible pointer
types" / "too many arguments to function", хотя тулчейн (gcc/make/headers)
в системе есть. Причина: код писался под старые версии GCC, где это было
предупреждением; современный GCC (14+, у нас системный — 15.x) по
умолчанию делает такие предупреждения ошибками. Патчить старый код
нецелесообразно — возьми для **этого одного проекта** старый GCC из
nixpkgs, не трогая системный компилятор остальной системы.

**Важно**: `nix-shell -p gcc13 ...` НЕ работает надёжно — другие пакеты в
том же списке могут транзitively притащить системный gcc раньше в PATH, и
`gcc --version` всё равно покажет 15.x (проверено живьём). Правильно —
переопределить весь `stdenv` целиком через готовый nixpkgs-атрибут
`pkgs.gcc13Stdenv` (есть `gcc49Stdenv` … `gccNNStdenv` под почти любую
версию):

Разовая проверка:
```bash
nix-shell -E '
  let pkgs = import <nixpkgs> {};
  in pkgs.mkShell.override { stdenv = pkgs.gcc13Stdenv; } {
    packages = with pkgs; [ gnumake autoconf bison patch gnum4 perl
      zlib.dev readline.dev libyaml.dev libffi.dev gdbm.dev ncurses.dev libxcrypt ];
  }
' --run 'mise install ruby@2.5.1'
```

Постоянно для проекта — `shell.nix` в его корне (direnv уже настроен
системно, см. `modules/home/direnv.nix`, так что всё активируется само
при `cd`):
```nix
# shell.nix
let pkgs = import <nixpkgs> {};
in pkgs.mkShell.override { stdenv = pkgs.gcc13Stdenv; } {
  packages = with pkgs; [ gnumake autoconf bison patch gnum4 perl
    zlib.dev readline.dev libyaml.dev libffi.dev gdbm.dev ncurses.dev libxcrypt ];
}
```
```bash
echo "use nix" > .envrc
direnv allow
```
Дальше просто `cd` в проект — gcc13 и остальной тулчейн на PATH
автоматически, остальные проекты это не затрагивает.

## Собрать пакет, который блокируют без прокси (RubyMine и т.п.)

Симптом: `nixos-rebuild`/`nix build` падает на `fetchurl` с HTTP 451 или
обрывом соединения — сайт пакета блокирует запросы из РФ без VPN/прокси
(так ведёт себя `download.jetbrains.com` для RubyMine, см. комментарий
над `desktopApps.rubymine.enable` в `modules/nixos/desktop-apps.nix` и
`hosts/common.nix`). Запуск
`nixos-rebuild` обычным образом не подхватывает прокси автоматически:
`nix-daemon` — отдельный systemd-сервис со своим окружением, он не видит
`HTTP_PROXY`/`HTTPS_PROXY` из графической сессии (их выставляет Throne,
см. `docs/throne-routing.md` в репозитории gg-wp — и то только пока
Throne запущен, не постоянно).

Постоянно прописывать прокси в `nix.conf` **не стоит** — тогда вообще
любая сборка fixed-output-деривации (не только эта) будет падать с
connection-refused в момент, когда Throne не запущен (например, сразу
после перезагрузки, до логина). Передавать его нужно только на одну
конкретную команду через `impure-env` (`man nix.conf`) — а он действует
только для **trusted users**. Отдельно делать себя trusted-user в
`nix.conf` не нужно: `root` в нём уже по умолчанию (встроенное поведение
Nix, не наша настройка), а `nixos-rebuild switch`/`build-vm` в этом
репозитории и так всегда запускается через `sudo` — демон уже видит
вызывающего как root.

**`make switch HOST=<host>` и `make vm HOST=<host>` делают это сами** —
проверяют живым TCP-коннектом на `127.0.0.1:2080` (локальный listener
Throne), и если он поднят, сами подставляют `impure-env` на эту одну
команду; если нет — печатают явно, что собирают без прокси (значит
RubyMine и подобное может упасть 451), и собирают как обычно. Ничего
вручную передавать не нужно — но и неявной магии нет: перед сборкой
всегда видно одну строку `==> ...`, какой путь был выбран. Детали — сам
`Makefile`, цель `with_proxy_if_up`.

Если нужно собрать/проверить фикс отдельно, без полного switch/vm —
дешевле всего прямой сборкой одного пакета (не всей системы), тем же
приёмом вручную:
```bash
sudo env NIX_CONFIG='impure-env = http_proxy=http://127.0.0.1:2080 https_proxy=http://127.0.0.1:2080' \
  nix build nixpkgs#jetbrains.ruby-mine --no-link
```
(`env`, а не просто `sudo VAR=... команда` — `sudo` не раскрывает
`VAR=значение` перед собственной командой как обычный шелл, нужен
отдельный процесс `env`, который выставит переменную и передаст
управление дальше). Порт `2080` — `inbound_socks_port` в собственной БД
Throne, `~/.config/Throne/config/throne.db`; проверить, вдруг поменяли в
UI Throne (тогда и `Makefile`'ный `PROXY_PORT` поправить). Работает
только потому, что `fetchurl` в nixpkgs уже сам объявляет
`http_proxy`/`https_proxy` в своих `impureEnvVars`
(`lib.fetchers.proxyImpureEnvVars`) — на стороне самого пакета ничего
менять не нужно.

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
