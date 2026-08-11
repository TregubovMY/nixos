# nixos

Переносимая NixOS-конфигурация: disko + LUKS, systemd-boot/Secure Boot,
Hyprland, home-manager, sops-nix. Полное описание архитектуры и решений —
`system-plan.md`. Инструкции для агента, работающего в этом репозитории —
`CLAUDE.md`.

Сейчас в этом флейке реально собираются `agent-sandbox` и тестовый
`test-vm`-хост для `dev-databases` (см. ниже) — коммит `a2114ce` убрал
`configuration.nix`/`disko.nix`/`home.nix` и старый вывод
`nixosConfigurations`, так что `nixos-rebuild`/`nixos-install` для
реальной машины пока не применимы. Остальные слои (disko/LUKS/Hyprland/
home-manager/sops-nix) описаны в `system-plan.md`, но ещё не реализованы
в этом флейке.

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
- **Из языковых рантаймов через mise подтверждён только Ruby** (и то
  собранный из исходников через `ruby-build`, не precompiled-бинарник —
  см. комментарий в `modules/nixos/packages/agent-sandbox.nix` про
  отсутствующий ELF-интерпретатор в этом минимальном Nix-образе).
  Node/Python/Go через mise **не тестировались** и, скорее всего, не
  заработают "из коробки": их precompiled-бинарники ожидают обычный
  FHS-layout (`/lib64/ld-linux...`), которого в этом образе нет, а
  подходящего build-from-source пути (как для Ruby) для них тоже нет —
  никакого shim-интерпретатора образ не предоставляет. Если понадобится
  — потребуется отдельная работа (nix-ld/FHS-обёртка или что-то ещё).
- **Данные агента (логин/токены) не переживают перезапуск контейнера.**
  `bin/agent-sandbox` запускает контейнер с `--rm` и не монтирует
  `~/.claude`, `~/.claude.json` или `~/.config/opencode`, и не
  прокидывает никакой переменной окружения с API-ключом — только
  `~/.cache` и mise-кэш персистентны. На практике это значит, что агент
  переавторизуется заново при каждом запуске `bin/agent-sandbox`.
  Осознанно не исправлено в этом раунде: монтирование общего volume под
  креды — это отдельный компромисс безопасности (том становится
  доступен из контейнера любого проекта), требующий отдельного решения,
  а не слепого фикса.

## Postgres/Redis для локальной разработки

Общий Postgres 16 + Redis 7 для всех локальных проектов (декларативные
podman-контейнеры, `modules/nixos/dev-databases.nix`) — поднимаются вместе
с системой, ничего не нужно ставить/поднимать вручную на уровне проекта.

- Postgres: `127.0.0.1:5432`, пользователь `postgres`, **без пароля**
  (`POSTGRES_HOST_AUTH_METHOD=trust`) — локальная машина, БД доступна
  только с localhost, реального смысла в пароле нет.
- Redis: `127.0.0.1:6379`, без аутентификации, по той же причине.
- Данные — в `/var/lib/dev-postgres` / `/var/lib/dev-redis` на тестовом
  хосте этого плана; на реальной машине пути потребуют пересмотра при
  переносе в `hosts/<host>/`. **`/persist/postgres` / `/persist/redis`,
  упомянутые здесь раньше, больше не актуальны** — `system-plan.md` §4
  был переписан в рамках disk-boot-foundation и не создаёт `/persist`
  вообще (`disko-luks-btrfs.nix` даёт только subvolumes `root`/`home`/
  `nix`); куда именно лягут данные Postgres/Redis на `mimir` — решить при
  реальной установке этого хоста, отдельным шагом.

## Разметка диска и загрузка (disko + LUKS + systemd-boot)

Переиспользуемые модули для будущей реальной машины (пока не сама машина):
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
  `/proc/cmdline` активированной системы. **Это единственная проверка,
  которая реально поднимает LUKS/btrfs/swap layout** — см. ограничение
  ниже про `hosts/test-disko-luks/`.
- `nixos-rebuild dry-build --flake .#test-disko-luks` /
  `nixos-rebuild build-vm --flake .#test-disko-luks` — сборка одноразового
  VM-хоста `hosts/test-disko-luks/` (`device = "/dev/vda"`), который
  использует те же модули. `nixos-rebuild` не стоит в PATH в этой
  песочнице — то, что реально прогонялось здесь:
  `nix build .#nixosConfigurations.test-disko-luks.config.system.build.vm`.
  **Важно:** этот хост подтверждает только то, что модули эвалятся и
  замыкание собирается — сам layout (LUKS/btrfs/swap) в этой VM не
  поднимается, его целиком перекрывает `virtualisation.useDefaultFilesystems`
  из `qemu-vm.nix` (см. ограничение ниже). Функциональная проверка —
  только `checks.disko-luks-btrfs` выше.

### Известные ограничения

- **Настоящий hibernate-and-resume цикл может быть подтверждён только на
  реальном железе.** VM-тест (`checks.disko-luks-btrfs`) доказал, что сам
  механизм `LUKS → swap → resumeDevice` реально работает — своп активен на
  правильном mapper-устройстве, `resume=` попадает в kernel cmdline. Чего
  он **не** доказывает — что `systemctl hibernate` и последующий resume
  реально проходят целиком; это можно достоверно проверить только на
  настоящей машине.
- **`hosts/mimir/` (реальный хост) существует только как skeleton.**
  `disk-config.nix` + `configuration.nix` составляют переиспользуемые,
  VM-проверенные модули под реальную identity машины (см.
  `docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md`), но
  не зарегистрированы в `flake.nix` и не собираются — реальная установка
  (генерация `hardware-configuration.nix`, регистрация в `flake.nix`,
  `nixos-install`) остаётся отдельным, явно запрашиваемым шагом в будущем
  (см. design doc, "Real Install Boundary").
- **Оба LUKS-контейнера при реальной установке должны получить ОДИНАКОВУЮ
  парольную фразу — это ожидаемое поведение initrd, НЕ проверенное
  VM-тестом.** По механизму NixOS-initrd-разблокировки, при совпадающей
  парольной фразе у обоих контейнеров загрузка должна спрашивать пароль
  один раз (автоповтор уже введённого пароля на следующих
  `boot.initrd.luks.devices`); при разных паролях — дважды. Но
  `checks.disko-luks-btrfs` даёт обоим LUKS-контейнерам
  `settings.keyFile` (см. `modules/nixos/disko-luks-btrfs-test.nix`), так
  что интерактивный ввод пароля там вообще не участвует — этот тест ничего не
  говорит про auto-retry-поведение. Это именованный, непроверенный пробел,
  который нужно подтвердить на реальной установке, а не доказанный факт.

## Secure Boot (lanzaboote)

`modules/nixos/secure-boot.nix` — отдельный модуль, не надстройка над
`boot.nix`: lanzaboote заменяет `systemd-boot` (`boot.loader.systemd-boot.enable
= lib.mkForce false`), а не добавляется поверх него — этого требует
собственная документация lanzaboote. Хосты с Secure Boot импортируют
`secure-boot.nix` **вместо** `boot.nix`, не вместе с ним — а значит
`secure-boot.nix` сам обязан нести и остальные настройки `boot.nix`
(`boot.initrd.systemd.enable = true`, нужный `disko-luks-btrfs.nix` для
LUKS-промпта), а не полагаться на то, что они унаследуются от него: он
включает `boot.lanzaboote.enable = true` с `pkiBundle = "/var/lib/sbctl"`
(текущий рекомендованный путь), явно повторяет `boot.initrd.systemd.enable
= true` и `boot.loader.efi.canTouchEfiVariables = true`, и добавляет
`pkgs.sbctl` в `environment.systemPackages` для реального
`sbctl create-keys`/`enroll-keys`. Хосты, которым Secure Boot не нужен,
продолжают импортировать обычный `boot.nix` без изменений. Почему выбран
именно этот вариант и какие альтернативы отвергнуты — `system-plan.md` §4
и design doc
(`docs/superpowers/specs/2026-08-10-secure-boot-design.md`).

Проверка — двумя раздельными чеками, не одним совмещённым (подробности и
причина раздельности — design doc, "Two Checks, Not One Combined Test"):
- `nix flake check --no-build` — быстрая eval-only проверка, что
  `disko-luks-btrfs.nix` и `secure-boot.nix` эвалятся вместе без конфликтов
  опций (`nixosConfigurations.test-secure-boot`, `hosts/test-secure-boot/`).
  Ничего не доказывает про Secure Boot или про реальный дисковый layout —
  только что модули совместимы на уровне опций.
- `nix flake check -L` — реальный VM-boot, `checks.<system>.secure-boot-signing`:
  вендоренная копия собственного upstream-теста lanzaboote
  (`modules/nixos/secure-boot-test/`), эмпирически подтвердившая, что Secure
  Boot реально работает с тем же выбором `boot.initrd.systemd.enable = true`,
  что уже сделан в `boot.nix` под LUKS-промпт (`bootctl status` внутри VM
  показал "Secure Boot: enabled (user)"). Строится через совершенно другой
  механизм — systemd-repart-образ, а не disko — и не трогает
  `disko-luks-btrfs.nix`, `secure-boot.nix` или `hosts/test-secure-boot/`.

### Известные ограничения

- **Настоящая генерация ключей и enroll в UEFI происходят только на реальном
  железе, во время реальной установки.** Этот репозиторий никогда не
  генерирует и не коммитит ключи Secure Boot — разовый `sbctl create-keys` +
  enroll в UEFI setup требует физического доступа к машине.
- **Два чека выше раздельны, и прохождение обоих не доказывает, что Secure
  Boot и настоящий disko/LUKS/btrfs-layout работают вместе в одной
  загрузке.** Эта комбинация никогда не тестировалась целиком — это
  именованный, принятый пробел (design doc, раздел "Risk profile"), а не
  подразумеваемое покрытие только потому, что оба чека проходят по
  отдельности.
- **`hosts/mimir/configuration.nix` уже импортирует `secure-boot.nix`**
  (см. `docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md`),
  но хост не зарегистрирован в `flake.nix` и не собирается — реальное
  включение на физической машине, наравне с реальным enroll ключей,
  остаётся будущим, явно запрашиваемым шагом.

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
(`programs.throne`) и виртуализация (`virtualisation.libvirtd` +
`programs.virt-manager`).

Пакеты объявлены на уровне `environment.systemPackages`, **не** через
home-manager — сознательная последовательность шагов, а не постоянная
архитектура: home-manager в этом флейке ещё не подключён (отдельная,
более поздняя задача), а список пакетов уже нужен сейчас. Когда
home-manager появится, часть этого списка (то, что по смыслу
пользовательское, а не системное) стоит пересмотреть и, возможно,
перенести — см. `system-plan.md` §3 про целевую структуру.

Проверка — `hosts/test-desktop-apps/` (одноразовый VM-хост, не
`hosts/mimir/`), тем же паттерном, что и остальные throwaway-хосты в этом
репозитории:
```bash
nix flake check --no-build
nixos-rebuild dry-build --flake .#test-desktop-apps
```
(или `nix build .#nixosConfigurations.test-desktop-apps.config.system.build.toplevel`,
если `nixos-rebuild` не в PATH — см. CLAUDE.md, "Цикл разработки").

### Известные ограничения

- **Группы `libvirtd`/`kvm` никому не назначены** — в этом репозитории
  ещё нет реального пользователя (`hosts/mimir/configuration.nix` не
  объявляет `users.users.*` — см. skeleton design doc), назначать группы
  некому. Это шаг реальной установки, не этого модуля.
- **Список пакетов системный (`environment.systemPackages`), не
  home-manager** — см. выше, сознательная временная последовательность,
  не финальная архитектура.
- Две вещи, обнаруженные при реализации, расходятся с тем, что раньше
  было написано в `system-plan.md` (сейчас уже исправлено там, но если
  кто-то смотрит старую версию файла через git-историю — не доверять ей):
  - IDE-пакет называется `jetbrains.ruby-mine` (через дефис), не
    `jetbrains.rubymine` — атрибут переименован апстримом. `nix search`
    по обоим именам показывает пусто независимо от переименования, потому
    что `nix search` не учитывает `nixpkgs.config.allowUnfree = true`
    (см. `system-plan.md` §5.4 за деталями и командой для реальной
    проверки) — не принимать пустой результат `nix search` за
    доказательство, что unfree-пакета нет в nixpkgs.
  - Throne (прокси-клиент, преемник архивированного nekoray) — обычный
    пакет nixpkgs со своим модулем `programs.throne`, а не
    самодельная AppImage/бинарник-derivation, как изначально
    предполагал план (см. `system-plan.md` §5.8).
- **`nixpkgs.config.allowUnfree = true` из `flake.nix` не пропагирует в
  `nixosConfigurations`** — он применяется только к отдельному
  `pkgs`-инстансу для `packages.${system}` (agent-sandbox-образ). Список
  пакетов в `desktop-apps.nix` включает unfree-пакеты (RubyMine, Chrome,
  VSCode, Postman), поэтому `hosts/test-desktop-apps/configuration.nix`
  объявляет `nixpkgs.config.allowUnfree = true;` сам — `hosts/mimir/configuration.nix`
  уже делает то же самое в своём skeleton (см.
  `docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md`),
  иначе dry-build/сборка упадёт, когда хост будет зарегистрирован.
  Подробности — `system-plan.md` §2.

## Секреты (sops-nix)

`modules/nixos/secrets.nix` — минимальная обвязка sops-nix ровно под один
секрет: GPG-ключ для подписи git-коммитов. `sops.age.sshKeyPaths` берёт
age-ключ расшифровки из собственного SSH-хост-ключа машины (`ssh-to-age`,
`/etc/ssh/ssh_host_ed25519_key`) — до появления реального хоста это
рабочий, но пока незадействованный путь: `secrets/secrets.yaml` и
`.sops.yaml` в этом репозитории не существуют, шифровать пока не для кого.
Почему роль sops-nix сузилась (SSH-ключи и конфиг прокси переехали в
Bitwarden) и что решено оставить — `system-plan.md` §6/§7.

Проверка:
- `nix flake check --no-build` — быстрая eval-only проверка, что
  `secrets.nix` эвалится на реальном host-closure без конфликтов опций
  (`hosts/test-secrets/`, одноразовый хост только для этой цели).
- `nix flake check -L` — реальный VM-тест, `checks.<system>.secrets-decryption`
  (`modules/nixos/secrets-test/`): вендоренная, адаптированная копия
  апстримного теста sops-nix `age-ssh-keys` (ed25519 SSH-хост-ключ →
  `ssh-to-age` → age identity → реальная расшифровка sops-файла при
  активации системы) — подтверждает тот же механизм
  (`sops.age.sshKeyPaths`), что настроен в реальном модуле. Детали, в том
  числе почему это именно `age-ssh-keys`, а не `ssh-keys` — `system-plan.md`
  §6.

### Известные ограничения

- **`secrets/secrets.yaml`/`.sops.yaml` пока без реального содержимого** —
  у этого репозитория ещё нет ни одного настоящего получателя (`mimir` не
  установлен физически, реального SSH-хост-ключа для `ssh-to-age` пока
  нет, хотя `hosts/mimir/configuration.nix` уже импортирует `secrets.nix`
  — см. skeleton design doc).
- **Вендоренный тест доказывает механизм на фиксированном тестовом ключе,
  не на ключе реальной машины** — тот же самый механизм (`ssh-to-age` из
  ed25519 host key), но "проверено через стенд-ин ключ", а не "проверено
  на `mimir`".
- **`config.sops.secrets."gpg_key".path` пока без потребителя** —
  home-manager-инфраструктура теперь есть (`modules/nixos/home-manager.nix`),
  но подключение к git commit signing понадобится реальный
  `home-manager.users.<имя>` на реальном хосте, которого всё ещё нет;
  отдельная будущая задача.

## home-manager

`modules/nixos/home-manager.nix` — включает home-manager как
NixOS-module-интегрированную инфраструктуру (`home-manager.useGlobalPkgs
= true`, `home-manager.useUserPackages = true`), без содержимого
дотфайлов (`modules/home/*`: tmux, neovim, shell, waybar, Hyprland-конфиг
— отдельная будущая задача, ждёт самого Hyprland). Требует
`home-manager.nixosModules.home-manager`, импортированный на уровне
флейка вместе с этим модулем — тот же паттерн, что уже используют
`disko.nixosModules.disko`/`lanzaboote.nixosModules.lanzaboote`.

`home-manager.users.<имя>` — не часть этого модуля: имя пользователя
хост-специфично, та же граница, что уже есть у `users.users.*` в этом
репозитории. `hosts/mimir/configuration.nix` пока не объявляет ни того,
ни другого (см. `docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md`)
— это шаг реальной установки.

Проверка:
- `nix flake check --no-build` — eval-only проверка композиции модулей
  (`hosts/test-home-manager/`, одноразовый хост с тестовым пользователем
  `testuser`, только для этой цели).
- `nix build .#nixosConfigurations.test-home-manager.config.system.build.toplevel`
  — реальная (не dry-run) сборка: подтверждает, что деривации
  activation-скрипта home-manager и профиля пользователя действительно
  собираются, а не только эвалятся. Без VM-теста — без реальных
  дотфайлов нечего проверять поведенчески, см. design doc "Testing".

### Известные ограничения

- **Дотфайлы (`modules/home/*`) не существуют** — этот раунд даёт только
  инфраструктуру; tmux/neovim/shell/waybar/Hyprland-конфиг остаются
  отдельной будущей задачей, зависящей от самого Hyprland-модуля
  (`system-plan.md` §5.2, ещё не построен).
- **`hosts/mimir/`'у некому назначать `home-manager.users.*`** — реального
  пользователя всё ещё нет, та же причина, по которой у него нет
  `users.users.*` (см. skeleton design doc).

## Hyprland

`modules/nixos/hyprland.nix` — `programs.hyprland.enable = true;` (уже
включает `xdg.portal.enable`, `portalPackage` →
`xdg-desktop-portal-hyprland`, `xwayland.enable` — подтверждено `nix
eval` на реальных дефолтах опций, не предположение) плюс остальной пакетный
список из `system-plan.md` §5.2: waybar, fuzzel, mako, hyprlock/hypridle,
grim/slurp/wf-recorder, hyprpaper, cliphist, wl-clipboard,
`hyprpolkitagent` (выбран вместо `polkit-gnome` — родной для Hyprland,
активно поддерживается), qt5ct/qt6ct + kvantum для Qt5 и Qt6 (четыре
отдельных пакета на нетривиальных путях, не два, как можно подумать по
`system-plan.md` §5.2). `playerctl` не дублируется — уже есть в
`desktop-apps.nix` (§5.10).

Проверка — та же глубина, что у `desktop-apps.nix` (`programs.hyprland.enable`
структурно то же самое, что уже проверенные `programs.throne.enable`/
`programs.kdeconnect.enable`):
- `nix flake check --no-build` — eval-only проверка композиции
  (`hosts/test-hyprland/`, одноразовый хост только для этой цели).
- `nixos-rebuild dry-build --flake .#test-hyprland` (или `nix build
  .#nixosConfigurations.test-hyprland.config.system.build.toplevel
  --dry-run`, если `nixos-rebuild` не в PATH) — подтверждает, что все
  пакетные атрибуты реально резолвятся и собрались бы.

### Известные ограничения

- **Никакого реального Hyprland-конфига** — кейбинды, виджеты waybar,
  тема, `exec-once`-автозапуск (включая будущую привязку
  `hypr/quick-translate.lua` и автозапуск `kdeconnectd`) — всё это ждёт
  home-manager-дотфайлов (`modules/home/*`, инфраструктура уже есть, см.
  раздел «home-manager», содержимого пока нет) — отдельная будущая
  задача.
- **Визуальная/поведенческая проверка невозможна из этой песочницы** —
  нет GPU/дисплея, и агент не может "посмотреть глазами" на композитор в
  принципе (см. `CLAUDE.md`) — это шаг только на реальном железе с живым
  человеком.
- **`hosts/mimir/`'у некому назначать реальную Hyprland-сессию** —
  реального пользователя всё ещё нет, та же причина, по которой у него
  нет `users.users.*`/`home-manager.users.*` (см. skeleton и
  home-manager design docs).

## Shell и Zellij (modules/home/*)

Первое реальное содержимое `modules/home/*` (home-manager-дотфайлы, не
только инфраструктура) — `modules/home/shell.nix` и
`modules/home/zellij.nix`.

`shell.nix`: zsh (`programs.zsh.autosuggestion`/`syntaxHighlighting`/
`historySubstringSearch` — нативные опции home-manager, отдельный
менеджер плагинов не нужен) + алиасы (`..`, `...`, `gs`/`gc`/`gp`/`gl`/`gd`)
+ eza вместо `ls` (`ll`/`la`/`lt`/`lla` генерируются автоматически через
`programs.eza.enableZshIntegration`) + starship (промпт, zsh-интеграция
включается автоматически) + git (`programs.git.settings` — текущее,
не-obsolete имя опции; алиасы `co`/`br`/`st`, `init.defaultBranch = "main"`,
`pull.rebase = true`). Без `user.name`/`user.email` — это реальная
персональная информация, тот же шаг реальной установки, что и SSH/GPG-
ключи, `users.users.*`.

`zellij.nix`: `programs.zellij.enable = true;` вместо `tmux`
(`system-plan.md` §3/§5.3 изначально называли `tmux` — заменено по
явной просьбе на более новый и популярный инструмент; нативные WASM-плагины
Zellij закрывают то, для чего `tmux` нужны были `tpm`/`tmux-resurrect`/
`tmux-continuum`). `enableZshIntegration = false` — осознанно, чтобы не
подключаться автоматически к существующей сессии в каждом новом шелле.

Проверка — та же глубина, что у home-manager-инфраструктуры (реальная
активация, не только eval):
- `nix flake check --no-build` — eval-only проверка композиции
  (`hosts/test-shell/`, одноразовый хост с тестовым пользователем
  `testuser`).
- `nix build .#nixosConfigurations.test-shell.config.system.build.toplevel`
  — реальная сборка (не dry-run): подтверждает, что весь конфиг реально
  собирается, включая activation-скрипт с настоящими дотфайлами.

### Известные ограничения

- **neovim, kitty, direnv/nix-direnv, podman, mise** (`system-plan.md`
  §5.3) — не в этом раунде. neovim — отдельная, заметно большая задача
  (LazyVim/kickstart.nvim + Ruby-стек); остальные — настоящие пробелы, не
  забыты.
- **Никакой визуальной/интерактивной проверки** — агент не может
  запустить настоящий login-shell и посмотреть, как выглядит промпт или
  работают алиасы интерактивно; это шаг на реальном хосте.
- **`hosts/mimir/`'у некому назначать реальные дотфайлы** — реального
  пользователя всё ещё нет, та же причина, по которой у него нет
  `users.users.*`/`home-manager.users.*`.

## Neovim (modules/home/neovim.nix, база LazyVim)

`modules/home/neovim.nix` — базовый LazyVim, без Ruby-специфичных
инструментов (LSP/rubocop/treesitter/rails/rspec/dap — отдельный будущий
раунд). Стартовый конфиг провендорен из `LazyVim/starter` (получен
свежим при реализации, не предположен) в `modules/home/neovim/` —
`init.lua`, `lua/config/{lazy,options,keymaps,autocmds}.lua`,
`lua/plugins/init.lua` (`return {}`, реальный, а не отключённый
`example.lua` апстрима — сюда позже лягут Ruby-специфичные plugin-спеки).

Генуинно impure в рантайме: `lua/config/lazy.lua` сам клонирует
`lazy.nvim` через `git clone` при первом запуске, а тот клонирует все
плагины LazyVim по умолчанию — принятый компромисс выбора LazyVim
(запрошено явно) вместо полностью декларативной альтернативы вроде
nixvim.

`home.packages` (не `programs.neovim.extraPackages`, который не попадает
в реальный `$PATH` для сабшеллов): `ripgrep`/`fd` (telescope),
`gcc` (nvim-treesitter компилирует парсеры в рантайме), `lazygit`
(дефолтный кеймап LazyVim `<leader>gg`), `git`.

**Mason** — намеренно не решено в этом раунде: LazyVim тащит `mason.nvim`
как часть ядра независимо от language-экстра, но без Ruby-экстра ничего
принудительно не скачивает. Решение (отключать Mason и ставить
LSP/инструменты через Nix, стандартный NixOS-паттерн, или оставить как
есть) — за Ruby-раундом, где это первый раз реально важно.

Проверка — та же глубина, что у `shell.nix`:
- `nix flake check --no-build` — eval-only (`hosts/test-neovim/`).
- `nix build .#nixosConfigurations.test-neovim.config.system.build.toplevel`
  — реальная сборка: подтверждает пакеты + symlink конфига через
  home-manager activation.

### Известные ограничения

- **Первый запуск `lazy.nvim`/установка плагинов не проверены** —
  генуинно impure, сетевой, требует реального интерактивного запуска
  `nvim`; та же категория "не проверяемо из этой песочницы", что и
  визуальная проверка Hyprland.
- **Ruby-стек не в этом раунде** — LSP/rubocop/treesitter/rails/rspec/dap
  ждут отдельного будущего раунда.
- **kitty, direnv/nix-direnv, podman, mise** (`system-plan.md` §5.3) —
  всё ещё не реализовано.

## kitty + direnv (modules/home/*)

`modules/home/kitty.nix` — `programs.kitty.enable = true;`, без
кастомизации темы/шрифта (та же граница "не выдумывать чужие
предпочтения", что у `zellij.nix`/`shell.nix` — дефолты апстрима,
реальные настройки — живое решение того, кто реально пользуется
терминалом).

`modules/home/direnv.nix` — `programs.direnv.enable` +
`programs.direnv.nix-direnv.enable` (авто-окружения на проект,
`system-plan.md` §5.3) + zsh-интеграция.

Проверка — та же глубина, что у `shell.nix`/`neovim.nix`:
`nix flake check --no-build` (`hosts/test-terminal/`) + реальная сборка
(`nix build .#nixosConfigurations.test-terminal.config.system.build.toplevel`).

## podman + mise (modules/nixos/podman.nix, modules/home/mise.nix)

`modules/nixos/podman.nix` — `virtualisation.podman.enable = true;` для
интерактивного использования podman под проекты (`system-plan.md` §5.3),
отдельно от `dev-databases.nix`'ного `virtualisation.oci-containers`.

**Попутная находка:** `dev-databases.nix` объявлял
`virtualisation.oci-containers.backend = "podman";`, но нигде не включал
`virtualisation.podman.enable` — подтверждено через `nix eval`, что без
этого podman не устанавливается и не включается вообще. Значит бэкенд
`dev-databases.nix` никогда реально не работал. Исправлено — `podman.nix`
и `dev-databases.nix` оба явно ставят `virtualisation.podman.enable =
true;` (безопасно: NixOS не конфликтует на одинаковых значениях от
разных модулей).

`modules/home/mise.nix` — `programs.mise.enable` + zsh-интеграция; версии
языков берутся из `.tool-versions` каждого проекта, тот же инструмент,
что использует agent-sandbox внутри (§9.3).

Проверка — та же глубина: `nix flake check --no-build` +
`nix build .#nixosConfigurations.test-podman-mise.config.system.build.toplevel`
(`hosts/test-podman-mise/`).

## Перевод по хоткею (Crow Translate)

Вместо самописного скрипта — готовое, поддерживаемое приложение
[Crow Translate](https://github.com/crow-translate/crow-translate)
(`crow-translate` в nixpkgs). `mainMod+T` переводит текущее выделение
текста через D-Bus-вызов `translateSelection` — Wayland не даёт
регистрировать глобальные хоткеи напрямую, поэтому переводом управляет
сам Hyprland-бинд, а не хоткей внутри приложения. Детали и почему выбрано
именно это решение (а не самописный скрипт) — system-plan.md §5.11.

Подключение: `require("quick-translate")` из основного `hyprland.lua`
(файл должен быть виден на Lua config path Hyprland — например, скопирован
или засимлинкован в `~/.config/hypr/`). Конфиг написан в Lua, а не в
классическом hyprlang `.conf` — начиная с Hyprland 0.55 (вышел
2026-05-09) `.conf`-формат deprecated и будет убран через 1-2 релиза, а
в этом репозитории ещё нет ни одного Hyprland-конфига, с которым нужно
было бы оставаться согласованным, так что смысла писать в устаревающем
формате не было. Приложение должно быть в списке пакетов (`crow-translate`
из nixpkgs) — добавляется туда, когда появится реальный список пакетов
хоста (см. system-plan.md §3). Хоткей дополнительно зависит от `gdbus`
(из пакета `glib`) — на десктопе почти наверняка уже подтягивается
транзитивно, но явно нигде не задекларирован, пока нет реального списка
пакетов хоста.

### Известные ограничения

Hyprland-конфиг (`hypr/quick-translate.lua`) **не проверялся визуально**
— у агента нет возможности "посмотреть глазами" на Hyprland (см.
CLAUDE.md). Перед тем как полагаться на это в реальной работе, нужно
вручную проверить на настоящем десктопе:
- `crow-translate` действительно запускается при старте Hyprland
  и его D-Bus-сервис отвечает;
- запуск при старте сессии **не гарантированно свёрнут в трей** —
  "старт в трей" это настройка внутри самого приложения (General tab),
  не CLI-флаг, так что при первом входе стоит ожидать видимое окно, пока
  эта настройка не включена вручную;
- если нажать хоткей сразу в первые секунды после входа в сессию, D-Bus
  сервис `crow-translate` может ещё не успеть зарегистрироваться — тогда
  вызов молча ничего не сделает; повторное нажатие через пару секунд
  должно сработать;
- `mainMod+T` при выделенном тексте (в любом приложении) реально
  вызывает перевод и показывает окно с результатом;
- нет конфликта хоткея `mainMod+T` с чем-то ещё уже забинженным;
- `require("quick-translate")` из основного `hyprland.lua` реально находит
  и загружает файл (зависит от того, куда именно скопирован/засимлинкован
  этот репозиторий на реальной машине).

В отличие от исходной задумки (терминал со скролбэком всех переводов),
Crow Translate показывает попап с текущим переводом, а не историю —
это осознанный компромисс (см. коммит "Pivot away from custom
quick-translate.sh to Crow Translate").
