# nixos

Переносимая NixOS-конфигурация: disko + LUKS, systemd-boot/Secure Boot,
Hyprland + DankMaterialShell (DMS), home-manager. Полное описание
архитектуры и решений — `system-plan.md`. Инструкции для агента,
работающего в этом репозитории — `CLAUDE.md`.

Секреты (пароли, SSH-ключи, GPG-ключ, конфиг прокси) — всё в **Bitwarden**,
не в git. sops-nix в этом репозитории не используется — было опробовано под
один секрет (GPG-ключ), но решение от 2026-08-18 (`system-plan.md` §6/§7)
перенесло и его в Bitwarden, а вся sops-инфраструктура удалена как
неиспользуемая.

Реально собираются: `agent-sandbox`, тестовый `test-vm`-хост для
`dev-databases`, диск/boot-модули (`disko-luks-btrfs.nix`/`boot.nix`/
`secure-boot.nix`) с VM-подтверждённой disko+LUKS+btrfs+Secure-Boot
разметкой, десктопный пакетный список (`desktop-apps.nix`), Hyprland +
DankMaterialShell как реальный десктоп (не только пакеты — с темой,
раскладкой, скриншотами), home-manager со всеми текущими дотфайлами
(shell/zellij/ghostty/direnv/mise/neovim). `hosts/mimir/` (реальная целевая
машина) существует только как skeleton — не зарегистрирован в `flake.nix`,
реальная установка на физическое железо ещё не происходила; всё выше
проверено через одноразовые VM-хосты, в первую очередь
`hosts/mimir-vm-full/` (см. ниже) — самую близкую к реальному хосту
репетицию, которая в этом флейке есть.

## Песочница для AI-агентов (agent-sandbox)

`claude-code`/`opencode` не запускаются напрямую на хосте против реального
проекта — вместо этого используется песочница: короткоживущий rootless
Podman-контейнер, в который смонтирована только директория проекта.
Почему так — `system-plan.md` §9.

### Установка

Нужен установленный `podman` на хосте. Образ этот флейк не публикует
никуда автоматически — собрать и загрузить в podman вручную один раз:

```bash
nix build .#agent-sandbox-image   # или просто `nix build` — есть packages.default
podman load -i ./result
```

`bin/agent-sandbox` ниже предполагает, что `agent-sandbox:latest` уже
есть в `podman images` — без этого шага первый же запуск упадёт с
"image not found".

### Использование

```bash
bin/agent-sandbox ~/code/myproject          # интерактивный shell в /workspace
bin/agent-sandbox ~/code/myproject -- claude # сразу запустить claude-code
bin/agent-sandbox --gui ~/code/myproject     # + видимое окно браузера на десктопе
```

Версии ruby/node/etc берутся из `.tool-versions`/`mise.toml` самого
проекта через `mise install`, который выполняется автоматически при
старте контейнера, если такие файлы есть в проекте — ничего не нужно
ставить вручную.

### IDE

Никакого remote-forwarding настраивать не нужно: контейнер монтирует ту
же директорию проекта (bind-mount, не копия), так что RubyMine/VSCode на
хосте открывают `~/code/myproject` как обычно и видят те же файлы на
диске. Изолируется процесс выполнения агента, а не файлы, которые ты
редактируешь. Сеть при этом намеренно не ограничена (`--network=bridge`,
полный NAT наружу) — граница защиты песочницы это файловая система и
секреты хоста, не сеть; подробности и явно принятые ограничения —
`system-plan.md` §9.2, §9.6.

### `--gui`

Нужна активная Wayland-сессия (Hyprland) на хосте — флаг пробрасывает
`WAYLAND_DISPLAY`-сокет и `/dev/dri`, чтобы, например, Chromium внутри
контейнера открыл окно, видимое на твоём десктопе. Без активной
Wayland-сессии команда сразу завершится с понятной ошибкой.

### Известные ограничения

- `--gui` (Wayland/GPU passthrough) и корректность `--userns=keep-id`
  (remap владельца файлов на хосте) реализованы, но пока не подтверждены
  на реальном железе — только статическим анализом и trace'ом аргументов
  в ходе разработки. Перед тем как полагаться на них, стоит один раз
  проверить руками на целевой машине (реальная Hyprland-сессия для
  `--gui`, реальный podman/subuid для `--userns=keep-id`).
- **Ruby через mise подтверждён живьём** (собранный из исходников через
  `ruby-build`, не precompiled-бинарник — этот путь и дальше не тронут,
  см. комментарий в `modules/nixos/packages/agent-sandbox.nix`).
  **Node/Python/Go через mise теперь технически должны работать, но не
  подтверждены запуском** — добавлен `nix-ld` (тот же механизм, что и
  `programs.nix-ld.enable` на хосте, `modules/nixos/nix-ld.nix`):
  символинк на `/lib64/ld-linux-x86-64.so.2` + `NIX_LD`/
  `NIX_LD_LIBRARY_PATH` в entrypoint, набор библиотек скопирован
  напрямую из дефолта апстримного NixOS-модуля
  (`nixos/modules/programs/nix-ld.nix`). Проверено `nix eval` (деривация
  валидна), но не полной сборкой/рантаймом — на машине разработки не
  хватало дискового бюджета под тяжёлую сборку (chromium в closure) по
  правилам CLAUDE.md. Тот же `nix-ld` включён и на хосте
  (`hosts/mimir/`, `hosts/mimir-vm-full/`) — сделано намеренно одним
  механизмом в обоих местах, чтобы mise resolved одинаково что в
  песочнице, что вне неё.
- **Данные агента (логин/токены) переживают перезапуск контейнера, но
  только для того же проекта.** `bin/agent-sandbox` монтирует отдельный
  named volume `agent-creds-$project_hash` (тот же хэш пути проекта, что
  и у `agent-cache-$project_hash`), а entrypoint-скрипт образа
  (`modules/nixos/packages/agent-sandbox.nix`) симлинкует туда
  `~/.claude`, `~/.claude.json` и `~/.config/opencode` при старте.
  Сознательно **не** общий volume на все проекты — иначе песочница
  одного проекта могла бы прочитать сессию/токен агента из другого,
  что ломает весь смысл per-project blast-radius containment (шапка
  `bin/agent-sandbox`). Компромисс: `claude login`/`opencode auth`
  нужно пройти заново на каждый **новый** проект (создаётся новый volume
  при первом запуске), но не при каждом перезапуске одного и того же.
  `ANTHROPIC_API_KEY`, если задан на хосте, тоже прокидывается в
  контейнер (альтернатива OAuth-логину) — опенкодовские
  провайдер-ключи так же можно добавить в `bin/agent-sandbox` по тому же
  паттерну, если понадобится.

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
- `nixos-rebuild dry-build --flake .#test-disko-luks` /
  `nixos-rebuild build-vm --flake .#test-disko-luks` — сборка одноразового
  VM-хоста `hosts/test-disko-luks/` (`device = "/dev/vda"`), который
  использует те же модули. `nixos-rebuild` не стоит в PATH в этой
  песочнице — то, что реально прогонялось здесь:
  `nix build .#nixosConfigurations.test-disko-luks.config.system.build.vm`.
  Этот хост подтверждает только то, что модули эвалятся и замыкание
  собирается — сам layout (LUKS/btrfs/swap) в этой VM не поднимается, его
  целиком перекрывает `virtualisation.useDefaultFilesystems` из
  `qemu-vm.nix`. Функциональная проверка — только `checks.disko-luks-btrfs`
  выше.

### Известные ограничения

- **Настоящий hibernate-and-resume цикл может быть подтверждён только на
  реальном железе.** VM-тест доказал, что сам механизм
  `LUKS → swap → resumeDevice` реально работает — своп активен на
  правильном mapper-устройстве, `resume=` попадает в kernel cmdline. Чего
  он **не** доказывает — что `systemctl hibernate` и последующий resume
  реально проходят целиком.
- **`hosts/mimir/` (реальный хост) существует только как skeleton.**
  `disk-config.nix` + `configuration.nix` составляют переиспользуемые,
  VM-проверенные модули под реальную identity машины (см.
  `docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md`), но
  не зарегистрированы в `flake.nix` и не собираются — реальная установка
  (генерация `hardware-configuration.nix`, регистрация в `flake.nix`,
  `nixos-install`) остаётся отдельным, явно запрашиваемым шагом.
- **Оба LUKS-контейнера при реальной установке должны получить ОДИНАКОВУЮ
  парольную фразу — иначе загрузка спросит пароль дважды.** Подтверждено
  на `hosts/mimir-vm-rehearsal/` (см. ниже) реальной ручной установкой:
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
  `secure-boot.nix` эвалятся вместе без конфликтов опций
  (`hosts/test-secure-boot/`).
- `nix flake check -L` — реальный VM-boot, `checks.<system>.secure-boot-signing`:
  вендоренная копия upstream-теста lanzaboote, эмпирически подтвердившая,
  что Secure Boot реально работает с `boot.initrd.systemd.enable = true`
  (`bootctl status` внутри VM показал "Secure Boot: enabled (user)").

**Подтверждено реальной загрузкой (`hosts/mimir-vm-rehearsal/`, 2026-08-12).**
Комбинация disko+LUKS+btrfs+Secure-Boot установлена и загружена вручную в
QEMU/OVMF VM (реальный disko-раздел на синтетическом диске, не
auto-built VM-артефакт, установка через `nixos-install` по-настоящему, не
через `build-vm`). LUKS спросил пароль один раз, `sbctl enroll-keys` и
`bootctl status` после перезагрузки показали `Secure Boot: enabled`,
`systemctl --failed` пуст.

### Известные ограничения

- **Настоящая генерация ключей и enroll в UEFI происходят только на реальном
  железе.** Этот репозиторий никогда не генерирует и не коммитит ключи
  Secure Boot.
- **Остаётся непроверенным реальное железо `hosts/mimir/`** — другой
  размер диска/раздела, реальные Option ROM вместо `--yes-this-
  might-brick-my-machine` в VM без TPM, реальный `sbctl enroll-keys` в
  прошивке машины (не в OVMF), и hibernate-цикл.

## Полная репетиция десктопа: `hosts/mimir-vm-full`

Самый полный из существующих хостов — тянет всё, что этот репозиторий
реально построил: disko+LUKS+btrfs, Secure Boot, `hyprland.nix`,
`greetd.nix`, `nix-settings.nix`, `desktop-apps.nix`, `dev-databases.nix`,
`podman.nix`, `home-manager.nix`, `notebooklm-tooling.nix` на системном
уровне, плюс реальный
home-manager-пользователь `max` с `hyprland.nix`/`neovim.nix`/`shell.nix`/
`zellij.nix`/`ghostty.nix`/`direnv.nix`/`mise.nix`. Единственное, чего у
него нет по сравнению с гипотетическим `hosts/mimir/` — `secrets.nix`
(теперь не нужен вообще, см. "Секреты" ниже) и реального
`hardware-configuration.nix` (виртуальный диск `/dev/vda`, initrd-модули
virtio прописаны вручную).

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
  глюк, повторится и на реальном `hosts/mimir/`). На этом хосте временно
  застаблен через `nixpkgs.overlays`, реальный фикс — Throne с настоящим
  VLESS-конфигом из Bitwarden (`programs.throne` уже включён в
  `desktop-apps.nix`, конфига пока нет).

`users.users.max.initialPassword = "max"` — репетиционное упрощение, НЕ то,
как должен быть настроен реальный `hosts/mimir/` (нужно реальное решение
про аутентификацию, см. `system-plan.md` §7).

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

Проверка — `hosts/test-desktop-apps/` (одноразовый VM-хост, не
`hosts/mimir/`):
```bash
nix flake check --no-build
nixos-rebuild dry-build --flake .#test-desktop-apps
# или, если nixos-rebuild не в PATH:
nix build .#nixosConfigurations.test-desktop-apps.config.system.build.toplevel --dry-run
```

### Известные ограничения

- **Группы `libvirtd`/`kvm` никому не назначены** — в этом репозитории
  ещё нет реального пользователя (`hosts/mimir/configuration.nix` не
  объявляет `users.users.*`) — шаг реальной установки.
- `jetbrains.ruby-mine` (через дефис, не `jetbrains.rubymine` — атрибут
  переименован апстримом), `nix search` по обоим именам показывает пусто
  независимо от переименования (не учитывает `allowUnfree`) — проверять
  через `NIXPKGS_ALLOW_UNFREE=1 nix eval --impure`.
- **`nixpkgs.config.allowUnfree = true` из `flake.nix` не пропагирует в
  `nixosConfigurations`** — применяется только к отдельному
  `pkgs`-инстансу для `packages.${system}` (agent-sandbox-образ). Каждый
  хост с unfree-пакетами (`hosts/mimir/`, `hosts/test-desktop-apps/`,
  `hosts/mimir-vm-full/`) объявляет `nixpkgs.config.allowUnfree = true;`
  сам.

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
  `modules/nixos/notebooklm-tooling.nix`, подключён в `hosts/mimir/` и
  `hosts/mimir-vm-full/`. Модуль выделен отдельно от `desktop-apps.nix`,
  потому что это не просто пакеты, а пакет + системные
  `environment.variables`, обвязывающие один конкретный воркэраунд:
  Playwright (тянется `notebooklm-py`) по умолчанию скачивает Chromium
  универсальной Linux-сборкой, ждущей FHS-путей вроде `/lib64`, которых на
  NixOS нет — `PLAYWRIGHT_BROWSERS_PATH` указывает на патченный
  `playwright-driver.browsers` из nixpkgs вместо этого,
  `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` не даёт Playwright параллельно
  тянуть несовместимый билд поверх.

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

Проверка — eval-only (`hosts/test-hyprland/` для системного модуля,
`hosts/test-hyprland-config/` для `modules/home/hyprland.nix`) +
`nixos-rebuild dry-build`/`nix build ...toplevel --dry-run`. Функциональная
проверка (что DMS реально стартует, биндинги реально работают) —
`hosts/mimir-vm-full/` (см. выше).

### Известные ограничения

- **Визуальная/поведенческая проверка невозможна из этой песочницы** —
  нет GPU/дисплея, и агент не может "посмотреть глазами" на компоситор в
  принципе (см. `CLAUDE.md`). Это шаг только на реальном железе с живым
  человеком.
- **`hosts/mimir/`'у некому назначать реальную Hyprland-сессию** —
  реального пользователя всё ещё нет.
- **Перевод по хоткею (Crow Translate)** переподключён через тот же
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
хост-специфично, та же граница, что уже есть у `users.users.*`. У
`hosts/mimir/` его по-прежнему нет; у `hosts/mimir-vm-full/` — есть, с
реальным пользователем `max` и полным набором дотфайлов (`shell.nix`,
`zellij.nix`, `ghostty.nix`, `direnv.nix`, `mise.nix`, `neovim.nix`,
`hyprland.nix`), см. раздел про `mimir-vm-full` выше.

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

Проверка — реальная сборка (не только eval), т.к. есть настоящий
activation-контент:
- `hosts/test-shell/` — `shell.nix` + `zellij.nix`
  (`nix build .#nixosConfigurations.test-shell.config.system.build.toplevel`).
- `hosts/test-terminal/` — `ghostty.nix` + `direnv.nix`
  (`nix build .#nixosConfigurations.test-terminal.config.system.build.toplevel`).

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

Проверка — та же глубина, что у `shell.nix`: `hosts/test-neovim/`,
`nix build .#nixosConfigurations.test-neovim.config.system.build.toplevel`.

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

Проверка — `hosts/test-podman-mise/`,
`nix build .#nixosConfigurations.test-podman-mise.config.system.build.toplevel`.

## Перевод по хоткею (Crow Translate)

`crow-translate`, Hyprland-бинд `SUPER+ALT+T` через D-Bus
`translateSelection` (см. `system-plan.md` §5.11). Изначально жил в
старой, Nix-управляемой версии Hyprland-конфига (репо-корневой
`hypr/quick-translate.lua`, `require("quick-translate")`) — переход на
DMS (см. «Hyprland + DankMaterialShell» выше) передал весь
`~/.config/hypr/` под управление DMS и молча унёс это с собой: старый
подход требовал Nix-managed `hyprland.lua`, которого больше нет, а
`crow-translate` в `desktop-apps.nix` тоже никогда не значился. Найдено и
переподключено 2026-08-18 (регрессия, а не решение отказаться) — теперь
через тот же `home.activation`-механизм, что уже дописывает
input-настройки и биндинги скриншотов в `modules/home/hyprland.nix`:
пакет в `home.packages` (плюс `glib` — источник `gdbus`, которым бинд
пользуется, ранее нигде явно не задекларирован), автозапуск
(`hl.on("hyprland.start", ...)`) дописывается в свой BEGIN/END-блок в
`hyprland.lua`, сам бинд — в существующий BINDS-блок
`~/.config/hypr/dms/binds-user.lua`. Репо-корневой `hypr/` каталог
удалён как мёртвый — require()-подход больше не используется.

### Известные ограничения

Не проверено визуально (агент не может "посмотреть глазами" на Hyprland,
см. `CLAUDE.md`) — перед тем как полагаться на это, проверить руками на
реальном десктопе: D-Bus-сервис `crow-translate` реально поднимается при
старте сессии; окно по умолчанию видимое (сворачивание в трей — настройка
внутри приложения, General tab, не CLI-флаг); `SUPER+ALT+T` при выделенном
тексте реально вызывает перевод; нет коллизии с другим биндом; если
нажать хоткей сразу в первые секунды после входа, D-Bus сервис может ещё
не успеть зарегистрироваться (повторное нажатие через пару секунд должно
сработать).

## Секреты

Все секреты (пароли/TOTP, SSH-ключи, GPG-ключ для подписи git-коммитов,
конфиг прокси Throne) — в **Bitwarden**, не в git. sops-nix в этом
репозитории не используется: пробовался под единственный секрет
(GPG-ключ), но решение `system-plan.md` §6/§7 (2026-08-18) перенесло и его
в Bitwarden — держать отдельный шифрующий-в-git механизм ради нуля
секретов, которым реально нужен доступ до сетевого логина, смысла не
имело. Подробности и история решения — `system-plan.md` §6/§7.
