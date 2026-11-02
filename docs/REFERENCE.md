# Справочник по компонентам

Подробности и история решений по каждому модулю — раньше это был README
(до 2026-10-06). Коротко о репозитории — `../README.md`, установка —
`INSTALL.md`, базовые действия в Nix — `NIX-HOWTO.md`, архитектура —
`../system-plan.md`. Ссылки вида «README, раздел …» в комментариях кода
ведут сюда.


Переносимая NixOS-конфигурация: disko + LUKS, systemd-boot/Secure Boot,
Hyprland + DankMaterialShell (DMS), home-manager. Полное описание
архитектуры и решений — `system-plan.md`. Инструкции для агента,
работающего в этом репозитории — `CLAUDE.md`. Открытые задачи — `TODO.md`.

Секреты (пароли, SSH-ключи, GPG-ключ, конфиг прокси) — всё в **Bitwarden**,
не в git. sops-nix в этом репозитории не используется — было опробовано под
один секрет (GPG-ключ), но решение от 2026-08-18 (`system-plan.md` §6/§7)
перенесло и его в Bitwarden, а вся sops-инфраструктура удалена как
неиспользуемая.

Один хост — `hosts/mimir/` (`.#mimir`): disko+LUKS+btrfs, Secure Boot,
Hyprland + DankMaterialShell, home-manager со всеми дотфайлами
(shell/zellij/ghostty/direnv/mise/neovim), песочницы агентов. Ставится
одним скриптом `bin/install-host` (см. «Установка на реальную машину»),
перед этим — прогон в VM по `docs/INSTALL.md`. Одноразовые хосты для
проверки модулей по отдельности (`test-*`, `mimir-vm-*`) удалены
2026-10-06 — `.#mimir` собирает все модули вместе, их история в git.

## Установка

Перенесено в `INSTALL.md` (2026-10-06): `bin/install-host <машина> <диск>`.

## Песочница для AI-агентов (agent-sandbox) — убрана из master (2026-11-02)

Podman-песочница (группы проектов `@имя`, одноразовые `--here`, kandev/dsh
внутри контейнера, сервисы `agent-services.nix`, тесты с фейковым podman)
убрана по решению пользователя: остаётся одна VM (`agent-vm`, раздел ниже).
Код, тесты и вся история решений — в ветке `agent-sandbox` (этот раздел,
«Одна песочница: агенты и доски», «Аналоги `agent-sandbox`»). Вернуть —
`git merge agent-sandbox` или cherry-pick нужного.

## Postgres/Redis для локальной разработки

Общий Postgres 16 + Redis 7 для всех локальных проектов (декларативные
podman-контейнеры, `modules/nixos/dev-databases.nix`) — поднимаются вместе
с системой, ничего не нужно ставить/поднимать вручную на уровне проекта.

- Postgres: `127.0.0.1:5432`, пользователь `postgres`, **без пароля**
  (`POSTGRES_HOST_AUTH_METHOD=trust`) — локальная машина, БД доступна
  только с localhost, реального смысла в пароле нет.
- Redis: `127.0.0.1:6379`, без аутентификации, по той же причине.
- Данные — `/var/lib/dev-postgres` / `/var/lib/dev-redis` (владелец uid/gid
  999 — так `postgres`-пользователь Debian-based образа устроен внутри
  контейнера; `systemd.tmpfiles.rules` в `dev-databases.nix` создаёт эти
  директории с правильным владельцем сам). Оба сервиса общие для всех
  проектов на машине (одна БД-инстанция, разные БД/namespaces внутри), как
  обычно устроена локальная разработка нескольких проектов на одной
  машине.
- `virtualisation.oci-containers.backend = "podman"` сам по себе НЕ
  включает podman — нужен ещё `virtualisation.podman.enable = true`,
  который `dev-databases.nix` до недавнего исправления не выставлял вовсе
  (найдено через `nix eval`, реальный латентный баг, не гипотетический).
  Теперь выставляется явно и здесь, и отдельно в `modules/nixos/podman.nix`
  (см. ниже) — NixOS не конфликтует, если два модуля независимо ставят
  одно и то же значение.

## Разметка диска и загрузка (disko + LUKS + systemd-boot)

Переиспользуемые модули под реальную машину:
`modules/nixos/disko-luks-btrfs.nix` (параметризованный disko-модуль —
`{ device, swapSize ? "34G" }`: GPT → ESP → два LUKS2-контейнера — `cryptroot`
с `btrfs` (subvolumes `/`, `/home`, `/nix`) и отдельный `cryptswap` с
`resumeDevice = true` для hibernate) и `modules/nixos/boot.nix`
(systemd-boot + systemd-initrd). Почему два LUKS-контейнера вместо одного и
как устроен `resumeDevice` — `system-plan.md` §4 и design doc
(`docs/superpowers/specs/2026-08-08-disk-boot-foundation-design.md`).

Проверка:
- **`nix flake check` в этом репозитории больше не дешёвая проверка** —
  `checks.<system>.disko-luks-btrfs` реально загружает две виртуалки
  (disko-VM-тест, минуты, не секунды). Для быстрой eval-only проверки
  после каждой правки — `nix flake check --no-build`. Полный
  `nix flake check -L` — когда действительно нужно функциональное
  подтверждение (см. CLAUDE.md, "Цикл разработки", шаг 1). Именно
  `-L`-прогон подтверждает, что оба LUKS-контейнера настоящие
  (`cryptsetup isLuks`), `btrfs`-subvolumes на месте (`root`/`home`/`nix`
  смонтированы), своп активен именно на расшифрованном mapper-устройстве
  (не на сыром разделе), и `resume=/dev/mapper/cryptswap` есть в
  `/proc/cmdline` активированной системы.
- `nix flake check --no-build` — что модули диска эвалятся в составе
  `.#mimir`; сама разметка на виртуальном диске — `docs/INSTALL.md`.

### Известные ограничения

- **Настоящий hibernate-and-resume цикл может быть подтверждён только на
  реальном железе.** VM-тест доказал, что сам механизм
  `LUKS → swap → resumeDevice` реально работает — своп активен на
  правильном mapper-устройстве, `resume=` попадает в kernel cmdline. Чего
  он **не** доказывает — что `systemctl hibernate` и последующий resume
  реально проходят целиком.
- **Оба LUKS-контейнера при реальной установке должны получить ОДИНАКОВУЮ
  парольную фразу — иначе загрузка спросит пароль дважды.** Подтверждено
  на VM-репетиции (2026-08-12) реальной ручной установкой:
  при одинаковом пароле LUKS действительно спрашивает его только один раз.

## Secure Boot (lanzaboote)

`modules/nixos/secure-boot.nix` — отдельный модуль, не надстройка над
`boot.nix`: lanzaboote заменяет `systemd-boot`
(`boot.loader.systemd-boot.enable = lib.mkForce false`), а не добавляется
поверх него — этого требует собственная документация lanzaboote. Хосты с
Secure Boot импортируют `secure-boot.nix` **вместо** `boot.nix`, не вместе
с ним, и поэтому сам несёт остальные настройки `boot.nix`
(`boot.initrd.systemd.enable = true`, нужный `disko-luks-btrfs.nix` для
LUKS-промпта), а не полагается на наследование: `boot.lanzaboote.enable =
true` с `pkiBundle = "/var/lib/sbctl"` (текущий рекомендованный путь),
`boot.loader.efi.canTouchEfiVariables = true`, и `pkgs.sbctl` в
`environment.systemPackages` для реального `sbctl create-keys`/
`enroll-keys`.

Проверка — двумя раздельными чеками:
- `nix flake check --no-build` — eval-only, что `disko-luks-btrfs.nix` и
  `secure-boot.nix` эвалятся вместе без конфликтов опций (в составе
  `.#mimir`).
- `nix flake check -L` — реальный VM-boot, `checks.<system>.secure-boot-signing`:
  вендоренная копия upstream-теста lanzaboote, эмпирически подтвердившая,
  что Secure Boot реально работает с `boot.initrd.systemd.enable = true`
  (`bootctl status` внутри VM показал "Secure Boot: enabled (user)").

**Подтверждено реальной загрузкой (VM-репетиция, 2026-08-12).**
Комбинация disko+LUKS+btrfs+Secure-Boot установлена и загружена в QEMU/OVMF
VM: LUKS спросил пароль один раз, после `sbctl enroll-keys` `bootctl status`
показал `Secure Boot: enabled`, `systemctl --failed` пуст. Тогдашние
хост `mimir-vm-rehearsal` и скрипты `bin/mimir-vm-*` удалены (2026-10-06) —
их заменил `bin/install-host` против настоящего `.#mimir`
(`docs/INSTALL.md`); история в git.

### Известные ограничения

- **Настоящая генерация ключей и enroll в UEFI происходят только на реальном
  железе.** Этот репозиторий никогда не генерирует и не коммитит ключи
  Secure Boot.
- **Остаётся непроверенным реальное железо `hosts/mimir/`** — другой
  размер диска/раздела, реальные Option ROM вместо `--yes-this-
  might-brick-my-machine` в VM без TPM, реальный `sbctl enroll-keys` в
  прошивке машины (не в OVMF), и hibernate-цикл.

## Полная репетиция десктопа (история)

Хост `hosts/mimir-vm-full` и скрипты `bin/mimir-full-*` (удалены
2026-10-06, теперь — `bin/install-host` + `docs/INSTALL.md`) прогоняли
весь десктоп в VM до появления настоящего `.#mimir`.

Живые находки в ходе репетиции (все уже исправлены, оставлены как
задокументированные баги, а не гипотетические):
- `programs.zsh.enable = true` нужен и на системном уровне (не только в
  home-manager) — иначе `users.users.max.shell = pkgs.zsh` не резолвится
  в `/etc/shells`, и пользователь остаётся на bash.
- `programs.dank-material-shell.systemd.enable = true` обязателен, если
  при `dms setup` было выбрано "Use systemd for session management? Yes"
  (дефолт/рекомендация самого DMS) — без этого получается чистая пустая
  Hyprland-сессия без DMS вообще.
- DMS-сгенерированный `hyprland.lua` сам выполняет
  `systemctl --user start hyprland-session.target` при старте — юнит
  с этим именем в этом репозитории больше никто не создаёт
  (`wayland.windowManager.hyprland`, который раньше его создавал, больше
  не используется, см. ниже) — `modules/home/hyprland.nix` теперь
  пересоздаёт именно этот таргет-юнит вручную.
- `jetbrains.ruby-mine`'s `fetchurl` реально получает HTTP 451 от
  `download.jetbrains.com` (гео/санкционная блокировка — не VM-специфичный
  глюк). На `hosts/mimir/` RubyMine выключен опцией
  `desktopApps.rubymine.enable = false` до настройки Throne (VLESS-конфиг
  из Bitwarden), затем включается обратно.

## Nix: автоочистка стора (`modules/nixos/nix-settings.nix`)

Добавлено вживую на фоне явного дискового бюджета машины разработки (см.
`CLAUDE.md`, "Дисковый бюджет"): `nix.settings.experimental-features =
[ "nix-command" "flakes" ]` (иначе `nixos-install`/`nixos-rebuild` не
принимают `--extra-experimental-features` — это отдельные wrapper-скрипты,
не сам `nix`), плюс:

- `nix.gc = { automatic = true; dates = "weekly"; options =
  "--delete-older-than 14d"; }` — именно `--delete-older-than`, не
  `nix-collect-garbage -d`: второе рушит все прошлые generations сразу и
  без окна на откат, первое чистит только по возрасту.
- `nix.settings.auto-optimise-store = true` — дедупликация одинаковых
  файлов в сторе хардлинками.
- `nix.settings.min-free`/`max-free` (2GiB/10GiB) — если во время сборки
  место падает ниже `min-free`, `nix-daemon` сам подчищает старое до
  `max-free`, не дожидаясь еженедельного `nix.gc`.

## Десктопные пакеты (desktop-apps.nix)

`modules/nixos/desktop-apps.nix` — декларативный список десктопных
приложений и связанных сервисов (system-plan.md §5.4-§5.10, §5.1.1,
§5.1.2): IDE (RubyMine, VSCode), AI coding agents для разового
интерактивного запуска (`claude-code`, `opencode` — sandboxed-путь для
работы над конкретным проектом отдельный, см. секцию про agent-sandbox
выше), коммуникация/браузер (Telegram, Chrome, Firefox), Postman,
удалённый стол в обе стороны (`wayvnc` + `remmina`), медиа (`mpv`,
`yt-dlp`, `pavucontrol`, `playerctl`), KDE Connect
(`programs.kdeconnect.enable`), прокси-клиент Throne
(`programs.throne`, `tunMode.enable = true`), виртуализация
(`virtualisation.libvirtd` + `programs.virt-manager`), и — добавлено позже
основного списка §5.x — Obsidian (заметки) и `awatcher` (трекер времени,
Wayland/Hyprland-совместимый: `activitywatch`'ный `aw-watcher-window` под
Wayland требует отдельный, слабо поддерживаемый
`aw-watcher-window-wayland`; `awatcher` — самостоятельный трекер с полной
поддержкой Hyprland через `wlr-foreign-toplevel-management`/
`ext-idle-notify-v1`, в одном бинарнике вместе с `aw-server-rust`).

Пакеты объявлены на уровне `environment.systemPackages`, **не** через
home-manager — сознательная последовательность (home-manager подключён
позже, список пакетов уже был нужен раньше). Когда состав `hosts/mimir/`
устаканится, часть этого списка (то, что по смыслу пользовательское, а не
системное) стоит пересмотреть — см. `system-plan.md` §3.

Проверка — `nix flake check --no-build` (вычисляет `.#mimir`, куда
подключены все модули) и прогон в VM по `docs/INSTALL.md`.

### Известные ограничения

- Группа `libvirtd` назначается пользователю в самом хосте
  (`hosts/mimir/configuration.nix`, `users.users.max.extraGroups`), не в
  этом модуле — пользователи хост-специфичны.
- RubyMine можно выключить опцией `desktopApps.rubymine.enable` — на
  `hosts/mimir` выключен до настройки Throne (HTTP 451 от JetBrains).
- `jetbrains.ruby-mine` (через дефис, не `jetbrains.rubymine` — атрибут
  переименован апстримом), `nix search` по обоим именам показывает пусто
  независимо от переименования (не учитывает `allowUnfree`) — проверять
  через `NIXPKGS_ALLOW_UNFREE=1 nix eval --impure`.
- **`nixpkgs.config.allowUnfree = true` из `flake.nix` не пропагирует в
  `nixosConfigurations`** — применяется только к отдельному
  `pkgs`-инстансу для `packages.${system}` (agent-sandbox-образ). Каждый
  хост с unfree-пакетами (сейчас это `hosts/mimir/`) объявляет
  `nixpkgs.config.allowUnfree = true;` сам.

## Obsidian-вольт + notebooklm-py (modules/nixos/notebooklm-tooling.nix)

Собрано по итогам `docs/superpowers/user/NixOS setup.md` (чек-лист,
написанный 2026-08-20 по факту реальной установки на текущей, не-NixOS
машине разработки) — что из того чек-листа декларативно, а что остаётся
ручным шагом реальной установки.

**Декларативно (уже в репозитории):**
- `obsidian` и `anki` — пакеты, `modules/nixos/desktop-apps.nix` (§5.x,
  добавлены вживую 2026-08-13/2026-08-19).
- `yt-dlp` — там же, есть в nixpkgs напрямую.
- `uv` и `playwright-driver.browsers` — отдельный модуль
  `modules/nixos/notebooklm-tooling.nix`, подключён в `hosts/mimir/`. Модуль выделен отдельно от `desktop-apps.nix`,
  потому что это не просто пакеты, а пакет + системные
  `environment.variables`, обвязывающие один конкретный воркэраунд:
  Playwright (тянется `notebooklm-py`) по умолчанию скачивает Chromium
  универсальной Linux-сборкой, ждущей FHS-путей вроде `/lib64`, которых на
  NixOS нет — `PLAYWRIGHT_BROWSERS_PATH` указывает на патченный
  `playwright-driver.browsers` из nixpkgs вместо этого,
  `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` не даёт Playwright параллельно
  тянуть несовместимый билд поверх.
- Тот же `uv` + `playwright-driver.browsers` (плюс те же две переменные)
  продублированы и в `agent-sandbox` (`modules/nixos/packages/
  agent-sandbox.nix`) — если claude-code/opencode запускаются внутри
  песочницы (см. секцию про agent-sandbox выше), а не прямо на хосте, им
  для того же тулинга нужна та же обвязка внутри контейнера. Персистентность
  `uv tool install "notebooklm-py[browser]"` между перезапусками
  контейнера (он `--rm`, ничего не остаётся сам по себе) обеспечивает
  общий на все проекты named volume `agent-uv-tools` — та же логика,
  что и у `agent-mise` в известных ограничениях ниже.

**Остаётся ручным шагом (не в Nix — реальная идентичность/учётки, тот же
принцип, что и SSH/GPG-ключи и `programs.git.settings.user` в
`modules/home/shell.nix`):**
- `ssh-keygen` под Obsidian-синк и добавление публичного ключа в GitHub;
  `git clone git@github.com:TregubovMY/Obsidian-Athena.git` — сам вольт,
  все community-плагины (QuickAdd, Templater, Dataview, Yanki, Homepage,
  obsidian-git) лежат внутри вольта в `.obsidian/plugins/` и приезжают
  вместе с клоном, отдельно их ставить не нужно; `obsidian-git` внутри
  вольта уже настроен на автокоммит/автопуш.
- `uv tool install "notebooklm-py[browser]"` — самого пакета в nixpkgs
  нет (чистый PyPI-пакет), `uv` только даёт изолированный venv для этой
  установки, сама установка не декларативна.
- `notebooklm login` — вход в гугл-аккаунт при первом запуске, тоже не
  автоматизируется.
- AnkiConnect (код аддона `2055492159` через Anki → Tools → Add-ons → Get
  Add-ons) — аддон внутри уже установленного Anki, не системный пакет.
- Если Obsidian (Electron) на конкретном GPU показывает чёрный экран —
  `--unsupported-gpu` в команде запуска; не захардкожено в модуль, т.к.
  зависит от конкретного железа, а не от системы вообще.

## Hyprland + DankMaterialShell (DMS)

`modules/nixos/hyprland.nix` — `programs.hyprland.enable = true;` плюс
поддерживающий пакетный список (grim/slurp/wf-recorder, hyprpaper,
cliphist/wl-clipboard, qt5ct/qt6ct+kvantum — четыре отдельных пакета на
нетривиальных путях, не два, papirus-icon-theme+hicolor-icon-theme).
Реальный конфиг/тема живёт в `modules/home/hyprland.nix` — там сейчас
**DankMaterialShell (DMS)**, Quickshell-based desktop shell, а не
ручной waybar/mako/hyprlock/hypridle/fuzzel/polkit-агент (были в этом
репозитории раньше, полностью выпилены — несколько раундов ручной темизации
через них неоднократно оценивались как "выглядит плохо/пусто"). DMS
заменяет всё перечисленное одной интегрированной системой (подтверждено
собственным README DMS: "replaces waybar, swaylock, swayidle, mako, fuzzel,
polkit").

**`~/.config/hypr/` полностью не управляется Nix/home-manager, отдаётся
DMS.** Home-manager'овский `wayland.windowManager.hyprland` модуль
безусловно клеймит `hypr/hyprland.lua` как read-only Nix-managed файл —
это блокирует собственный CLI DMS (`dms setup`, интерактивный, запускается
один раз после первого входа), которому нужно самому писать
`hyprland.lua` и `~/.config/hypr/dms/*.lua` и держать их под своим
управлением. Поэтому этот модуль вообще не использует
`wayland.windowManager.hyprland` — тот же класс "осознанно impure", что и
bootstrap `lazy.nvim` в `modules/home/neovim.nix`, только на шаг дальше
(даже не Nix-вендоренная стартовая точка — DMS разворачивает директорию с
нуля через `dms setup`).

**UWSM.** `programs.hyprland.withUWSM = true;` — без этого greetd/tuigreet
запускал сырой бинарник `Hyprland` напрямую, что сам Hyprland помечает
предупреждением "started without start-hyprland... strongly discouraged"
при каждой загрузке (реальный, задокументированный апстримом баг —
[github.com/hyprwm/Hyprland/discussions/12661](https://github.com/hyprwm/Hyprland/discussions/12661),
не косметический шум). Без UWSM компоситор не импортирует своё окружение в
systemd/D-Bus activation environment и не поднимает
`graphical-session(-pre).target` сам — то, от чего зависят порталы и
xdg-autostart, держится на удаче/порядке запуска, а не на настоящей
зависимости. `withUWSM = true` включает `programs.uwsm.enable`
автоматически и делает точкой входа `start-hyprland` — обёртку, которую
поставляет сам пакет Hyprland. `modules/nixos/greetd.nix` грузит именно её
(`--cmd start-hyprland`, не `--cmd Hyprland`). `programs.uwsm.waylandCompositors`
намеренно не заполняется вручную — это генерирует отдельный
`*.desktop`-пункт для session-picker дисплей-менеджеров (GDM/SDDM-стиля);
greetd/tuigreet здесь выбирает сессию через `--cmd` напрямую, так что
такой пункт был бы мёртвым конфигом.

**Тема/раскладка/биндинги**, поверх дефолтов DMS, через
`modules/home/hyprland.nix`:
- `bibata-cursors` — курсор (выбирается вручную в DMS Settings → Cursor,
  не Nix-управляемо).
- `QS_ICON_THEME = "Papirus-Dark"` (`environment.sessionVariables`, не
  home-manager — подхватывается раньше, чем сессионные переменные
  home-manager) — без этого у DMS в доке/таскбаре/лаунчере не было вообще
  никаких иконок приложений: в репозитории не было установлено ни одной
  icon theme.
- Раскладка `us,ru` с `CapsLock` как переключателем —
  `kb_options = "grp:caps_toggle"` (не `grp:caps_switch`, который
  переключает только пока клавиша зажата — это HOLD, не TOGGLE) +
  `resolve_binds_by_sym = true` (биндинги матчатся по символу, а не
  физической клавише, так что продолжают работать после переключения на
  ru). Компромисс: `caps_toggle` не оставляет резервной комбинации для
  обычного Caps Lock — его больше нет вообще.
- Скриншоты через `grimblast` (не встроенный DMS screenshot IPC — тот
  niri-only, под Hyprland не работает): `Print` — область, `Shift+Print`
  — весь экран, `Super+Print` — активное окно (copysave — одновременно
  копирует в буфер и пишет файл).
- `SUPER + /` — встроенная шпаргалка биндингов DMS
  (`dms ipc call hypr toggleBinds`).

**Переназначение дефолтных хоткеев DMS.** DMS хранит их не в одном месте:
`~/.config/hypr/dms/binds.lua` — часть дефолтов, которые `dms setup` может
перезаписать при обновлении (не редактировать руками); большинство же
дефолтных биндингов (навигация по окнам/workspace'ам, запуск терминала и
т.п.) на самом деле сидятся `dms setup`'ом прямо в
`~/.config/hypr/dms/binds-user.lua` — том же файле, в который дописывает
и наш `home.activation`-скрипт (см. ниже), и который DMS требует ПОСЛЕ
`binds.lua` (подтверждено чтением исходников DankMaterialShell на
закреплённом в `flake.lock` revision, не по памяти/докам сайта — сами
доки этого нюанса не описывают). Официальный способ убрать/переопределить
дефолтный бинд — `hl.unbind("КОМБО")` в `binds-user.lua` (то же самое
делает UI DMS Settings → Keyboard Shortcuts → Delete); просто забиндить
тот же комбо заново, не отвязав старый, не гарантированно то же самое.
**Это реальная, не гипотетическая ловушка**: биндинг Crow Translate ниже
изначально планировался на `SUPER+T`, но `dms setup` по умолчанию сажает
на `SUPER+T` запуск терминала прямо в `binds-user.lua` — наш
`home.activation`-скрипт дописывает в конец того же файла, так что новый
бинд тихо приземлился бы поверх/рядом с дефолтным без единого предупреждения
при сборке (Nix ничего не знает о содержимом DMS-файлов, это чистый
текстовый append). Обнаружено и исправлено сверкой с исходниками DMS
живьём — бинд перенесён на `SUPER+ALT+T`, свободный по тем же исходникам.
Практический вывод: перед тем как добавлять новый бинд через этот
механизм, стоит свериться с реальным содержимым `~/.config/hypr/dms/
binds-user.lua` на целевой машине (или с `core/internal/config/embedded/
hypr-binds-user.lua` в самом DMS на закреплённой версии) — не полагаться
на то, что комбо свободно только потому, что оно не встречается в этом
репозитории.

Поскольку `~/.config/hypr/` не Nix-managed, эти правки применяются через
`home.activation`-скрипт (не `xdg.configFile`), который **дописывает** в
уже развёрнутые DMS-файлы между BEGIN/END-маркерами, безусловно удаляя и
пересоздавая блок при каждой активации (не "добавить один раз при
отсутствии маркера" — такая идемпотентность защищает от дублирования, но
не от того, что более поздняя правка Nix-файла молча перестанет доходить
до реального конфига, если маркер уже стоит).

Проверка — `nix flake check --no-build` (вычисляет `.#mimir`, куда
подключены все модули) и прогон в VM по `docs/INSTALL.md`. Что DMS реально
стартует и биндинги работают — только вживую, в VM или на машине.

### Известные ограничения

- **Визуальная/поведенческая проверка невозможна из этой песочницы** —
  нет GPU/дисплея, и агент не может "посмотреть глазами" на компоситор в
  принципе (см. `CLAUDE.md`). Это шаг только на реальном железе с живым
  человеком.
- **`hosts/mimir/`'у некому назначать реальную Hyprland-сессию** —
  реального пользователя всё ещё нет.
- **Перевод по хоткею** (теперь Dialect, см. ниже) переподключён через тот же
  `home.activation`-механизм, что и остальные правки в этом разделе — см.
  раздел «Перевод по хоткею» ниже за деталями и известными
  ограничениями (не проверено визуально).

## home-manager

`modules/nixos/home-manager.nix` — включает home-manager как
NixOS-module-интегрированную инфраструктуру (`home-manager.useGlobalPkgs
= true`, `home-manager.useUserPackages = true`). Требует
`home-manager.nixosModules.home-manager`, импортированный на уровне
флейка вместе с этим модулем — тот же паттерн, что уже используют
`disko.nixosModules.disko`/`lanzaboote.nixosModules.lanzaboote`.

`home-manager.users.<имя>` — не часть этого модуля: имя пользователя
хост-специфично, та же граница, что уже есть у `users.users.*`. В
`hosts/mimir/` — пользователь `max` с полным набором дотфайлов
(`shell.nix`, `zellij.nix`, `ghostty.nix`, `direnv.nix`, `mise.nix`,
`neovim.nix`, `hyprland.nix`).

Дотфайлы (`modules/home/*`) сейчас реально существуют — это уже не только
инфраструктура, см. разделы «Hyprland + DankMaterialShell», «Shell,
Zellij, Ghostty», «Neovim», «podman + mise» ниже.

## Shell, Zellij, Ghostty, direnv

`modules/home/shell.nix`: zsh (`programs.zsh.autosuggestion`/
`syntaxHighlighting`/`historySubstringSearch` — нативные опции
home-manager, отдельный менеджер плагинов не нужен) + алиасы (`..`, `...`,
`gs`/`gc`/`gp`/`gl`/`gd`) + eza вместо `ls` (`ll`/`la`/`lt`/`lla`
генерируются автоматически через `programs.eza.enableZshIntegration`) +
starship (промпт, zsh-интеграция включается автоматически) + git
(`programs.git.settings` — текущее, не-obsolete имя опции; алиасы
`co`/`br`/`st`, `init.defaultBranch = "main"`, `pull.rebase = true`). Без
`user.name`/`user.email` — реальная персональная информация, шаг реальной
установки.

`modules/home/zellij.nix`: `programs.zellij.enable = true;` вместо `tmux`
(заменено по явной просьбе; нативные WASM-плагины Zellij закрывают то, для
чего `tmux` нужны `tpm`/`tmux-resurrect`/`tmux-continuum`).
`enableZshIntegration = false` — осознанно, чтобы не подключаться
автоматически к существующей сессии в каждом новом шелле.

`modules/home/ghostty.nix`: `programs.ghostty.enable = true;` — терминал,
изначально был kitty, заменён на Ghostty по явной просьбе. Резон замены:
zellij уже владеет табами/сплитами/мультиплексированием в этом
репозитории, так что собственные табы/сплиты kitty (или Ghostty) не дают
преимущества здесь — это прямая замена терминального эмулятора 1:1, не
попытка объединить несколько инструментов в один. Ghostty и Zellij не
конкурируют, а дополняют друг друга: Ghostty — эмулятор, Zellij — сессии/
детач-переприсоединение/сплиты поверх него. Без кастомизации темы/шрифта —
та же граница "не выдумывать чужие предпочтения", что у остальных
дотфайлов здесь: дефолты апстрима, реальные настройки — решение того, кто
реально пользуется терминалом.

`modules/home/direnv.nix`: `programs.direnv.enable` +
`programs.direnv.nix-direnv.enable` (авто-окружения на проект) +
zsh-интеграция.

Проверка — `nix flake check --no-build` (вычисляет `.#mimir`, куда
подключены все модули) и прогон в VM по `docs/INSTALL.md`.

### Известные ограничения

- **Никакой визуальной/интерактивной проверки** — агент не может
  запустить настоящий login-shell и посмотреть, как выглядит промпт или
  работают алиасы/Ghostty интерактивно; шаг на реальном хосте.
- **`hosts/mimir/`'у некому назначать реальные дотфайлы** — реального
  пользователя всё ещё нет.

## Neovim (modules/home/neovim.nix, LazyVim + Ruby-стек)

`modules/home/neovim.nix` — LazyVim, стартовый конфиг провендорен из
`LazyVim/starter` (получен свежим при реализации) в `modules/home/neovim/`
— `init.lua`, `lua/config/{lazy,options,keymaps,autocmds}.lua`,
`lua/plugins/{init,ruby}.lua`.

**Ruby-стек уже подключён** (`lua/plugins/ruby.lua`): импортирует
LazyVim'овский `lang.ruby` extra целиком (`ruby_lsp`/`rubocop` LSP+
форматтер, treesitter ruby-парсер, `nvim-dap-ruby`, `neotest-rspec`), плюс
`tpope/vim-rails` отдельно (не часть extra). `ruby-lsp`/`rubocop` сами по
себе — из Nix (`home.packages`), не Mason: оба серверных entry получают
`mason = false`, так что `nvim-lspconfig` резолвит их через `$PATH`, а не
через auto-install `mason-lspconfig`. Это решённый, не открытый вопрос —
Mason для остального (не-Ruby) стека LazyVim по-прежнему тащит сам по
себе, но принудительно ничего не качает без явных language extras.

Генуинно impure в рантайме: `lua/config/lazy.lua` сам клонирует
`lazy.nvim` через `git clone` при первом запуске, а тот клонирует все
плагины LazyVim по умолчанию — принятый компромисс выбора LazyVim
(запрошено явно) вместо полностью декларативной альтернативы вроде
nixvim.

`home.packages` (не `programs.neovim.extraPackages`, который не попадает
в реальный `$PATH` для сабшеллов): `ripgrep`/`fd` (telescope), `gcc`
(nvim-treesitter компилирует парсеры в рантайме), `lazygit` (дефолтный
кеймап LazyVim `<leader>gg`), `git`, `ruby-lsp`, `rubocop`.

Проверка — `nix flake check --no-build` (вычисляет `.#mimir`, куда
подключены все модули) и прогон в VM по `docs/INSTALL.md`.

### Известные ограничения

- **Первый запуск `lazy.nvim`/установка плагинов не проверены** —
  генуинно impure, сетевой, требует реального интерактивного запуска
  `nvim`; та же категория "не проверяемо из этой песочницы", что и
  визуальная проверка Hyprland.

## podman + mise (modules/nixos/podman.nix, modules/home/mise.nix)

`modules/nixos/podman.nix` — `virtualisation.podman.enable = true;` для
интерактивного использования podman под проекты, отдельно от
`dev-databases.nix`'ного `virtualisation.oci-containers` (см. выше про
латентный баг, который это заодно и вскрыло).

`modules/home/mise.nix` — `programs.mise.enable` + zsh-интеграция; версии
языков берутся из `.tool-versions` каждого проекта, тот же инструмент,
что использует agent-sandbox внутри (§9.3).

Проверка — `nix flake check --no-build` (вычисляет `.#mimir`, куда
подключены все модули) и прогон в VM по `docs/INSTALL.md`.

## Перевод по хоткею (Dialect)

**SUPER+ALT+T** — выделить текст и нажать: открывается окно
[Dialect](https://github.com/dialect-app/dialect) с этим текстом и сразу с
переводом (кириллица → английский, остальное → русский). Это
`translate-selection` в `modules/home/hyprland.nix`: берёт выделение через
`wl-paste --primary` (если пусто — буфер обмена) и вызывает
`dialect --text … --dest …`; уже открытое окно просто получает новый текст.
Переводчик — Google (`dconf`, ключ `/app/drey/Dialect/translators/active`):
проверено из VM — веб-переводчик Google отвечает, а провайдер Яндекса в
Dialect 2.6.1 сломан («Failed parsing HTML from yandex.com», Яндекс поменял
страницу). Сменить можно в настройках Dialect — до следующего `nixos-rebuild`.

Раньше был Crow Translate (через D-Bus `translateSelection`); заменён
2026-10-06, т.к. Crow 4.x убрал D-Bus API, переименовал бинарник в `crow` и
открывает окно только пустым — история в `system-plan.md` §5.11 и в git.

## Живые обои — убраны (2026-11-02)

Были `linux-wallpaperengine`, плагин DMS и `lockscreen-videos` (видео на
экране блокировки). Убраны по просьбе: лишняя нагрузка на GPU и отдельная
логика лока. Остались статичные обои (`~/Pictures/Wallpapers`). Если в DMS
осталось включённое видео лока — выключить в Settings → Lock Screen
(`lockScreenVideoEnabled` в `~/.config/DankMaterialShell/settings.json`).
Старые файлы: `~/.local/share/wallpaper-engine`, `~/Videos/Lockscreen`.

## Прокси и рабочий VPN

Схема (решение 2026-10-06): **по умолчанию — напрямую**, через прокси
(Throne, VLESS из Bitwarden) — только список доменов, рабочие адреса — через
рабочий VPN. Throne в TUN-режиме перехватывает трафик всех программ (и
`nix-daemon`, и контейнеров), а куда отправить каждое соединение, решают его
правила маршрутизации (ядро sing-box). Правила живут в настройках Throne, не
в git — как и сам VLESS-конфиг.

В Throne → маршрутизация:

1. Исходящее по умолчанию — **direct**.
2. → **proxy**: `jetbrains.com` (RubyMine, без прокси HTTP 451),
   `open-meteo.com` (погода в DMS — заблокирован, проверено в VM),
   `anthropic.com`, `claude.ai`, `claude.com` (Claude Code), по
   необходимости `openai.com`, `chatgpt.com`, `deepseek.com`.
3. → **direct**: `rnds.pro` и подсети рабочего VPN — их несёт OpenVPN;
   DNS для `rnds.pro` — рабочий DNS из VPN, иначе внутренние имена не
   резолвятся.

### Прокси для Claude в песочнице: два способа

**Способ 1 (основной): ничего не задавать в песочнице.** Достаточно правил
Throne выше: домены `anthropic.com`, `claude.ai`, `claude.com` уходят в
proxy, TUN ловит и трафик контейнера. Прокси не лежит в окружении агента.

**Способ 2: явный прокси** — если TUN не подходит. Claude Code читает
`HTTPS_PROXY`/`HTTP_PROXY`/`NO_PROXY`; **SOCKS не поддерживает**, нужен
HTTP-порт (у Throne/sing-box — «mixed» inbound). Из контейнера `127.0.0.1` —
это сам контейнер, поэтому Throne должен слушать адрес, достижимый из сети
podman (`host.containers.internal`), и этот порт нужно закрыть от LAN.
Задать можно в одном из двух мест:

- только для Claude — `~/.claude/settings.json` внутри песочницы:
  ```json
  { "env": { "HTTPS_PROXY": "http://host.containers.internal:2080",
             "NO_PROXY": "localhost,127.0.0.1" } }
  ```
- для всей песочницы (kandev, dsh, opencode, git, npm) — строки в
  `~/.config/agent-sandbox/projects/<имя>.conf`:
  ```ini
  env = HTTPS_PROXY=http://host.containers.internal:2080
  env = HTTP_PROXY=http://host.containers.internal:2080
  env = NO_PROXY=localhost,127.0.0.1
  ```
  Значение видит агент — логин/пароль прокси сюда не писать.

Проверка: в Claude `/status` (строка Proxy) или `claude --debug`
(лог в `~/.claude/debug/`). Порт 2080 — пример, подставьте свой.

Рабочий VPN — OpenVPN через NetworkManager (плагин в `base.nix`), один раз:
```bash
nmcli connection import type openvpn file work.ovpn
nmcli connection up work        # или переключатель в меню сети DMS
```

## Секреты

Все секреты (пароли/TOTP, SSH-ключи, GPG-ключ для подписи git-коммитов,
конфиг прокси Throne) — в **Bitwarden**, не в git. sops-nix в этом
репозитории не используется: пробовался под единственный секрет
(GPG-ключ), но решение `system-plan.md` §6/§7 (2026-08-18) перенесло и его
в Bitwarden — держать отдельный шифрующий-в-git механизм ради нуля
секретов, которым реально нужен доступ до сетевого логина, смысла не
имело. Подробности и история решения — `system-plan.md` §6/§7.

## agent-vm: microVM с Docker, решения (2026-10-30)

Код: `modules/nixos/agent-vm.nix`, `bin/agent-vm`; спецификация и модель
угроз — `docs/superpowers/specs/2026-10-30-agent-vm-design.md`. Здесь —
то, что не очевидно из кода.

- **Почему прокси, а не NAT.** Throne у пользователя пускает часть трафика
  напрямую, часть через прокси (по доменам); дома добавляется OpenVPN. NAT
  отдал бы VM таблицу маршрутов хоста, то есть и LAN, и VPN. Здесь у VM нет
  шлюза, а файрвол хоста пропускает из `agentbr` только TCP на
  `10.200.0.1:3128`.
- **Почему второй sing-box, а не Squid/tinyproxy.** Проверено на фейковом
  SOCKS-сервере: после действия `resolve` sing-box отдаёт SOCKS-upstream
  проверенный IPv4-адрес, а не имя → нет DNS-rebinding. Squid/tinyproxy
  передают имя, и Throne резолвит его второй раз. Цена: Throne видит
  IP-литералы, доменные правила работают только при sniff на его inbound.
- **Диапазоны блокировки**: `ip_is_private` (RFC1918, loopback, link-local,
  ULA) + явно `0.0.0.0/8`, `100.64.0.0/10` (CGNAT/Tailscale), `169.254/16`
  (metadata), `192.0.0.0/24`, `198.18.0.0/15` (в т.ч. пул FakeIP),
  `224.0.0.0/3`. Только IPv4: в госте IPv6 выключен.
- **Порядок правил iptables**: глобальные `allowedTCPPorts` хоста (ssh,
  LocalSend, KDE Connect) действуют на ВСЕ интерфейсы, включая `agentbr`.
  Поэтому переход в `agentvm-in` вставляется в `INPUT` перед `nixos-fw`.
  FORWARD из/в `agentbr` — DROP (у гостя нет шлюза, но взломанный может
  задать свой). Файрвол здесь — iptables-бэкенд, не nftables.
- **Ключ ssh**: `agent-vm shell` — ssh с хоста в гость. Приватный ключ в
  `/var/lib/agent-vm/` (владелец — пользователь хоста), гость получает
  только публичный через read-only virtiofs. known_hosts отключён для
  этого одного адреса: ключ хоста VM меняется при `reset`.
- **ttyd** запускается с `--check-origin`: без него любая страница в
  браузере могла бы открыть writable-websocket на `127.0.0.1:7681`
  (cross-site WebSocket hijacking).
- **Что НЕ проверено на живой VM** (только eval/сборка/фейковый SOCKS):
  загрузка гостя, bridge+tap под networkd рядом с NetworkManager, порядок
  старта `agent-vm-proxy` (адрес моста может подняться позже — юнит
  перезапускается каждые 2 с), слушает ли kandev на всех интерфейсах гостя
  (если только на localhost — понадобится socat в госте), sniff у Throne.

### agent-vm: одна VM, монтирования, сессии (2026-10-30)

- **Почему монтирования, а не клон.** Группы проектов в песочнице оказались
  неудобны; нужна одна VM, в которой `claude` запускается прямо из папки
  проекта и сессии общие. Claude хранит транскрипты по рабочему каталогу →
  путь в VM должен совпадать с путём на хосте, пользователь — тоже (имя,
  uid, `$HOME`; uid должен совпадать, virtiofs отдаёт «сырые» uid).
- **Что видно из аккаунтов.** Вместо корня `claude-accounts` целиком
  монтируются отдельно `shared/`, каждый аккаунт из `claudeAccounts` и
  `~/.config/claude-accounts` (правила по пути, ro). Симлинки внутри
  аккаунта на `shared/` относительные, поэтому работают. Не перечисленный
  аккаунт (токен входа) в VM не попадает вообще.
- **Родители точек монтирования.** systemd создаёт отсутствующие родители
  как root:root; root-овый `~/.local` ломает все программы, пишущие туда
  (так уже было в песочнице с podman). Гостевой юнит `agent-mountpoints`
  создаёт родителей от имени пользователя после монтирования тома home и
  до всех шар.
- **`/nix/store` — только `readOnly = true`.** virtiofsd работает от root на
  хосте, а microvm.nix делает `ro` только bind-монтирование `/nix/store`
  внутри гостя; источник `/nix/.ro-store` без флага остаётся записываемым,
  то есть root гостя мог бы переписать store хоста. Найдено при ревью.
- **git.** `agent-vm up` пишет в `share/` отфильтрованный gitconfig
  (user.*, init/pull, includeIf с копией user.* из подключаемых файлов,
  `commit.gpgsign=false`), гость читает его как SYSTEM-конфиг
  (`GIT_CONFIG_SYSTEM`) — собственный `git config --global` в VM главнее.
- **Аккаунт по умолчанию** (`agent-vm account X`) хранится на хосте
  (`~/.config/agent-vm/account`) и передаётся при каждом запуске как
  `CLAUDE_ACCOUNT_DEFAULT`; `--account` — `CLAUDE_ACCOUNT` (приоритет выше);
  без обоих действуют правила по пути, как на хосте. `claude-use` внутри
  VM пишет `.override` в гостевой корень, не влияя на хост.
- **Не проверено на живой VM**: загрузка, порядок `agent-mountpoints` и
  монтирований, mise/nix-ld внутри, права на `authorized_keys` для sshd.

### agent-vm: Postgres и Redis (2026-10-30)

- Штатные сервисы NixOS в госте (`services.postgresql` 16 — как в
  `dev-databases.nix`; `services.redis.servers.agent`), а не ручной запуск
  как в песочнице (там нет systemd). Только loopback, роль `postgres` без
  пароля (`trust` на loopback) — вход в VM только по ключу хоста.
- Корень гостя — tmpfs, поэтому данные лежат на отдельных образах
  (`postgres.img` → `/var/lib/postgresql`, `redis.img` →
  `/var/lib/redis-agent`); `agent-vm reset` стирает и их.
- Переменные клиента (`PGHOST`, `PGUSER`, `REDIS_URL`, а также
  `GIT_CONFIG_SYSTEM`, `DOCKER_CONFIG`, `MISE_SHARED_INSTALL_DIRS`) заданы
  через `environment.sessionVariables`, не `variables`: `agent-vm claude`
  — это `ssh host 'команда'` без login-шелла, а `variables` читает только он;
  `sessionVariables` применяет pam_env для любой сессии sshd. (Это же
  исправляет git-идентичность и Docker-прокси в `agent-vm claude`.)
- Не проверено на живой VM: права каталога данных на только что
  отформатированном томе (tmpfiles/StateDirectory должны выставить
  владельца), что pam_env реально применяется к `ssh host cmd` в этом госте.


### agent-vm: первый живой запуск (2026-10-30)

- **Нашлось**: `agent-vm-proxy` падал через 50 мс и перезапускался каждые
  2 с — sing-box при старте открывает netlink-сокет, а в юните стояло
  `RestrictAddressFamilies` без `AF_NETLINK`. Из-за этого `agent-vm test`
  «зависал»: прокси не слушал, а `docker pull` без прокси ждёт минутами.
  Воспроизведено и проверено исправление через `systemd-run --user -p
  RestrictAddressFamilies=…`. Урок: `nix flake check`/сборка не ловят
  ограничения песочницы юнита — только запуск.
- `agent-vm test` теперь сначала проверяет, что прокси слушает, и падает
  сразу с подсказкой; `docker run` обёрнуты в `timeout`.
- Загрузка гостя при этом прошла: виртуалка поднялась, sshd, Docker,
  Postgres и Redis стартовали, монтирования virtiofs отработали.
- **Второй баг первого запуска**: цепочка `agentvm-in` пропускала только
  новый TCP на 3128, поэтому ответы гостя на соединения, открытые ХОСТОМ
  (ssh, проброс портов), тоже отбрасывались: ARP разрешался, `ssh` висел,
  `agent-vm up` ждал 3 минуты. Починено правилом `ESTABLISHED,RELATED`
  первым в цепочке (соединение, начатое гостем, остаётся NEW и режется).
  `agent-vm test` проверял это только изнутри VM — до ssh не доходило.
- **Третий баг**: kandev писал `lookup kdlbs.github.io: no such host`
  (индекс плагинов). `networking.proxy` задаёт `environment.variables`, то
  есть только оболочки, а службы systemd (kandev, `dsh-install`) прокси не
  видели, а DNS и маршрута у гостя нет. Починено `systemd.globalEnvironment`
  с `HTTP(S)_PROXY`/`NO_PROXY` в обоих регистрах (Go читает оба).

### agent-vm: права Claude шире, чем на хосте (2026-10-30)

- **Почему не через `settings.json` аккаунта.** Он общий (монтируется с
  хоста), списки `allow`/`ask`/`deny` из разных файлов объединяются, а
  `allow` не перебивает `ask`: ослабить правило можно только убрав его там,
  где оно задано. Записать более мягкие правила в общий файл нельзя ещё и
  потому, что Claude перечитывает настройки на лету — запущенные сессии на
  хосте стали бы мягче.
- **Как сделано.** В гостя кладётся локальный
  `/etc/claude-code/managed-settings.json` с
  `allowManagedPermissionRulesOnly = true`: тогда действуют только его
  правила, `allow/ask/deny` из `settings.json` аккаунта игнорируются
  (`defaultMode` остаётся из аккаунта). Правила считаются из тех же списков,
  что у хоста (`passthru.permissions` в `claude-accounts.nix`): плюс
  `vmAllow`, минус `docker`/`podman` в `ask` и `sudo` в `deny`.
  Хостовый пакет `claude-accounts` при этом не изменился (тот же хеш).
- Действует после `agent-vm down && up` (гостевой `/etc`). Проверка в
  сессии: `/status` показывает managed-источник.
- Шаблон `llm-dev-template` правил разрешений для Claude не содержит (там
  только `opencode.jsonc` для OpenCode), поэтому он не менялся.

### agent-vm: один kandev, dsh, worktree'ы на хосте (2026-10-30)

- Одна VM → один kandev (38429) и один `dsh web` (3080); два kandev из
  двух групп песочницы (38429/38430) больше не нужны.
- `dsh-setup` вынесен из `agent-sandbox.nix` в `packages/dsh-setup.nix`
  (общий для песочницы и VM; деривация песочницы не изменилась — проверено
  по `drvPath`). dsh ставит служба `dsh-install` (oneshot с повтором, т.к.
  нужен прокси; ставит dsh и плагины `core` через `dsh-setup`, метка успеха
  `~/.npm-global/.dsh-plugins-core`), `dsh-web` ждёт метку (до 10 мин, чтобы
  сломанный плагин не клал веб-интерфейс); socat открывает 3081 → 3080.
- `kandevTasksDir` — в VM bind-монтирование на `~/.kandev/tasks` (служба
  `kandev`, `ExecStartPre` с `+`, от root), на хосте симлинк по тому же пути
  (tmpfiles `L`), чтобы пути worktree в git совпадали. Раньше в VM был
  симлинк — kandev 0.97 его отвергает (2026-11-02). `CLAUDE_CODE_EXECUTABLE` указывает на обёртку аккаунтов.
- Не проверено на живой VM: установка dsh через прокси, `dsh web` за
  socat, создание worktree в смонтированной папке (права, inode).

### Права Claude на хосте шире (2026-10-30)

По просьбе («подтверждения только тратят время») базовый набор в
`claude-accounts.nix` расширен: без вопроса — локальный git (merge, rebase, pull,
fetch, worktree, tag…), `podman`/`docker`, `nix build/flake check/eval/develop/run`,
сборка и тесты (`make`, `mise`, `npm/pnpm/yarn`, `bundle`, `rspec`, `go`, `cargo`,
`pytest`, `uv`…), чтение `gh`, `journalctl` и `systemctl status`. Спрашивают только
`git push`, `git reset --hard`, `git clean` (то, что уходит с машины или стирает
незакоммиченное). `deny` не тронут (секреты, `sudo`, `nixos-rebuild`, `rm -rf /`,
`git config --global`). Правила общие для хоста, песочницы и VM; VM добавляет к ним
`sudo`/`systemctl`/`psql`. Чтобы вернуть вопросы — вернуть строки из `allow` в `ask`.

## Ревью репозитория Opus, 2026-11-02: что исправлено и что осталось

Исправлено: tmpfiles agent-vm создавали родителей `~/.config`/`~/.local` как
root (сломало бы первую загрузку); virtiofsd отдавал root гостя как root хоста
(теперь `--translate-uid/gid squash-guest` + без `CAP_MKNOD`, ACL выключены);
канал «песочница → хост» через аккаунты Claude: настройки аккаунтов в песочнице/VM только на чтение, у песочницы свой файл настроек (см. `docs/AGENT-VM.md` «Настройки Claude»);
восстановление лока больше не снимает лок (`allow_session_lock_restore`);
docker/podman на хосте снова `ask`; `impure-env` в Makefile работал вхолостую
(нужна `configurable-impure-env`); shellcheck по всем `bin/*`; тест
`agent-sandbox-cli` был красным (нет `git`/`python3`, путь `claude` в `bin/ai`).

Решения пользователя 2026-11-02: loopback хоста для контейнеров podman
оставлен доступным (им пользуются compose-проекты); `--gui`, гонка `enter`,
тома `adhoc` — ушли вместе с песочницей в ветку `agent-sandbox` (гонка там
исправлена `flock`); KDE Connect сужен до LAN; устаревшие куски `hyprland.nix`
после UWSM — отдельным коммитом, проверить выходом/входом в сессию.

