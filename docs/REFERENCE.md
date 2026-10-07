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

## Песочница для AI-агентов (agent-sandbox)

`claude-code`/`opencode` не запускаются напрямую на хосте против реального
проекта — вместо этого используется песочница: короткоживущий rootless
Podman-контейнер, в который смонтирована только директория проекта.
Почему так — `system-plan.md` §9.

### Установка

Ничего отдельно собирать не нужно: `modules/nixos/agent-sandbox.nix`
(подключён в `hosts/mimir`) кладёт корень песочницы в
`/etc/agent-sandbox/rootfs` и ставит команду `agent-sandbox` в PATH.
Обновление — обычный `nixos-rebuild switch`.

**Как устроено (с 2026-10-06):** это не образ podman. Корень песочницы —
крошечный каталог в `/nix/store` (`/etc/passwd`, `/bin/sh`, загрузчик
nix-ld, сертификаты, entrypoint), а все инструменты — одно окружение
`buildEnv` в том же `/nix/store`. podman запускается с `--rootfs <корень>:O`,
`/nix/store` хоста смонтирован только для чтения. Пакеты не копируются в
хранилище podman: раньше образ занимал ~4 ГБ (в основном Chromium и
Playwright), которые и так лежали на хосте. Проверить сборку без
`switch`: `nix build .#agent-sandbox-rootfs -o /tmp/sbx` и
`AGENT_SANDBOX_ROOTFS=/tmp/sbx agent-sandbox …`.

### Использование

```bash
bin/agent-sandbox ~/code/myproject          # интерактивный shell в /workspace
bin/agent-sandbox ~/code/myproject -- claude # сразу запустить claude-code
bin/agent-sandbox --gui ~/code/myproject     # + видимое окно браузера на десктопе
```

### Долгоживущий контейнер на проект (`up`/`attach`/`exec`/`down`)

Для всего, что должно жить дольше одной команды (Web UI dsh,
tmux-сессии) — один именованный
контейнер на проект (`agent-sandbox-<hash пути>`), те же volume'ы, что и
в одноразовом режиме. Зачем и как устроено — `system-plan.md` §9.7.

```bash
bin/agent-sandbox up ~/code/myproject                      # поднять (detached, --init)
bin/agent-sandbox attach ~/code/myproject                  # интерактивный shell внутри
bin/agent-sandbox attach --workdir .worktrees/feature/KEY-1-slug ~/code/myproject -- claude
bin/agent-sandbox exec --no-tty ~/code/myproject -- claude -p "..." --output-format stream-json
bin/agent-sandbox status                                   # все поднятые проекты
bin/agent-sandbox down ~/code/myproject                    # остановить (volume'ы остаются)
```

- `--workdir <путь>` — запуск в подкаталоге проекта (обычно git worktree
  в `.worktrees/<branch>`), относительно корня проекта или абсолютным
  путём внутри него. Путь вне проекта (в т.ч. через `..` или симлинк)
  отклоняется. Работает и в одноразовом режиме.
- `--no-tty` — никогда не выделять TTY (оркестратор, скрипты), даже при
  запуске из терминала. Код возврата команды пробрасывается наружу и в
  одноразовом режиме, и в `exec` (podman сам использует только 125–127).
- `--publish <host-port>:<container-port>` (у `up` и одноразового режима)
  — публикует порт **только на `127.0.0.1`** хоста, не в LAN.
- `--gitlab-token` — передать `GITLAB_TOKEN` в контейнер. По умолчанию
  выключено; только для Project Access Token (один проект, роль
  Developer, срок действия), см. §9.7.
- `--shared-root` (только `up`) — осознанно смонтировать каталог с
  несколькими проектами: изоляция между проектами при этом теряется.
- Переменные окружения хоста в контейнер **не** попадают, кроме явного
  белого списка (`ANTHROPIC_API_KEY`, `DEEPSEEK_API_KEY`, `GITLAB_TOKEN`
  по флагу) — токены Jira/GitLab/облаков, экспортированные в shell
  хоста, агенту недоступны. Проверяется `make test`
  (`tests/agent-sandbox-test.sh`, фейковый podman) и flake-check
  `agent-sandbox-cli`.

### Конфиг проекта (`@name`)

Вместо пути к проекту можно указать `@имя` — настройки берутся из
`~/.config/agent-sandbox/projects/<имя>.conf`:

```ini
# ~/.config/agent-sandbox/projects/shop.conf
dir      = ~/code/shop-api          # основной проект → /workspace (обязателен)
mount    = ~/code/shop-frontend     # ещё папка, чтение+запись, внутри по тому же пути
mount_ro = ~/code/shared-lib        # ещё папка, только чтение
mount    = ~/code/billing           # сколько угодно mount/mount_ro
publish  = 3080:3080                # как --publish: только 127.0.0.1 хоста
env      = RAILS_ENV=development    # обычная переменная (не для секретов)
```

```bash
bin/agent-sandbox up @shop
bin/agent-sandbox attach @shop -- claude
bin/agent-sandbox down @shop
```

- Конфиг лежит **вне** проекта намеренно: папка проекта смонтирована на
  запись, и агент мог бы дописать себе в конфиг доступ к другим папкам.
  Скрипт отказывается работать с конфигом, лежащим внутри любой
  монтируемой на запись папки; `~` целиком и `/` монтировать тоже
  отказывается.
- Файл читается построчно как данные (не `source`): неизвестный ключ или
  строка без `=` — ошибка, а не молчаливый пропуск.
- Volume'ы с логинами и кэшем (`agent-creds-cfg-<имя>`,
  `agent-cache-cfg-<имя>`) и контейнер (`agent-sandbox-cfg-<имя>`)
  называются по имени конфига, а не по хэшу пути: перенос папки не
  требует заново `claude login`. Но и переход с `agent-sandbox <путь>` на
  `@имя` — это новые volume'ы (один раз залогиниться заново).
- `mise.toml` в дополнительных папках доверяется так же, как в
  `/workspace` (`AGENT_EXTRA_TRUSTED` → entrypoint) — это требует
  пересобранного образа.
- **Что сохраняется между `down`/`up` и перезагрузками** — весь домашний
  каталог песочницы (`agent-home-<проект>`: история shell, `~/.gitconfig`,
  `~/.dsh` с плагинами и сессиями dsh, настройки инструментов), логины
  Claude/OpenCode (`agent-creds-*`), кэш, плюс общие на все проекты mise,
  npm -g, uv, `~/.local/bin`. Сам контейнер одноразовый (`--rm`), теряется
  только то, что записано вне `~` и вне папок проекта (например, в `/tmp`).
- Прокси в конфиге нет намеренно: Throne в TUN-режиме и так заворачивает
  весь трафик машины, включая контейнеры.
- Флаги командной строки (`--publish`, `--gitlab-token`, `--gui`)
  работают вместе с конфигом.

### LSP для агентов

В образе есть `gopls` и `typescript-language-server` (+ `typescript`) —
серверы для встроенного LSP-инструмента Claude Code (официальные плагины
`gopls-lsp`/`typescript-lsp` из `claude-plugins-official`, включаются в
`.claude/settings.json` проекта) и для LSP-интеграции OpenCode. `ruby-lsp`
намеренно не в образе — добавляется в Gemfile проекта (development), чтобы
совпадать с Ruby проекта из mise; плагин `ruby-lsp` Claude Code найдёт его
через `bundle exec`/PATH.

### Ручные установки (переживают перезапуск, общие на все проекты)

```bash
bin/agent-sandbox attach ~/code/myproject
# openspec и lefthook уже в образе (nixpkgs), ставить не нужно
npm install -g @deepseek-ai/dsh        # DeepSeek Harness, см. ниже
# одиночные бинарники из GitHub releases — в ~/.local/bin
# (домашний каталог песочницы, в PATH).
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
  (`hosts/mimir/`) — сделано намеренно одним
  механизмом в обоих местах, чтобы mise resolved одинаково что в
  песочнице, что вне неё.
- **`up`/`attach`/`exec`/`--publish`/`--init` проверены только тестами
  обёртки** (фейковый podman, `tests/agent-sandbox-test.sh`) и
  статически — в среде разработки нет podman. Перед тем как полагаться на
  них, один раз прогнать руками: `up` → `status` → `attach` → `exec
  --no-tty … -- false; echo $?` (ожидается 1) → `down`. Отдельно
  проверить, что `--init` работает с установленным podman (нужен
  catatonit; на NixOS идёт вместе с `virtualisation.podman`).
- **Проверено в VM mimir (2026-10-06)** на корне из `/nix/store`:
  одноразовый запуск и `up`/`exec`/`down`; пользователь `agent` с uid
  хоста, файлы в проекте — ваши; все инструменты на месте (git, claude,
  opencode, mise, node, uv, openspec, lefthook, gitleaks, gopls,
  typescript-language-server, gcc, chromium, rg, tmux, jq); `/nix/store`
  только для чтения; mise сам ставит Node по `.tool-versions`; домашний
  каталог переживает `down`/`up`. Не проверены `--gui` и `uv tool install
  notebooklm-py`.
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
  паттерну, если понадобится. По тому же паттерну прокидывается и
  `DEEPSEEK_API_KEY` для DeepSeek Harness, см. секцию ниже.

## DeepSeek Harness (`dsh`) в agent-sandbox

Как и notebooklm-py ниже — не в nixpkgs (npm-пакет `@deepseek-ai/dsh`,
выложен 2026-08-13, апстрим сам предупреждает о breaking changes в
developer preview), поэтому не задекларирован Nix-деривацией, а ставится
руками внутри песочницы, персистентно между перезапусками того же
контейнера через общий volume `agent-npm-global`
(`modules/nixos/packages/agent-sandbox.nix`).

**Декларативно (уже в образе):** `nodejs` — только рантайм для `npm`,
самого `dsh` в образе нет.

**Остаётся ручным шагом:**
```bash
bin/agent-sandbox ~/code/myproject
npm install -g @deepseek-ai/dsh   # один раз на машину — переживает
                                   # перезапуск контейнера (agent-npm-global),
                                   # но НЕ переживает `podman volume rm`/сброс
dsh                                # headless/CLI-режим — работает как есть
```

- Нужен `DEEPSEEK_API_KEY` — прокинь его на хосте перед запуском
  (`export DEEPSEEK_API_KEY=...`), `bin/agent-sandbox` передаёт его в
  контейнер тем же способом, что и `ANTHROPIC_API_KEY` (см. «Известные
  ограничения» выше).
- `dsh web` (web UI) — через долгоживущий контейнер с опубликованным
  на loopback портом. Внутри контейнера dsh должен слушать не
  `127.0.0.1`, а все интерфейсы контейнера, и доверять адресу, по которому
  его откроет браузер на хосте (флаги `--host`/`--trusted-host` из
  `packages/bundle/web-app/src/startup.ts` dsh 0.1.5):
  ```bash
  bin/agent-sandbox up --publish 3080:3080 ~/code/myproject
  bin/agent-sandbox attach ~/code/myproject -- \
    dsh web --host 0.0.0.0 --port 3080 --no-open --trusted-host 127.0.0.1:3080
  # браузер на хосте: http://127.0.0.1:3080
  ```
  Не проверено живьём (в среде разработки нет podman). Для агентного
  цикла без UI по-прежнему подходит headless-профиль (`dsh` без `web`).

## Одна песочница: агенты и доски (kandev, dsh)

Все агенты и доски живут в **одной песочнице на конфиг** (`agent-sandbox
up @имя`): Claude Code, OpenCode, kandev, dsh — просто программы в одном
контейнере, с общим домашним каталогом (логины Claude/GitHub — одни на
всех), общими проектами и инструментами. Сменить доску — значит запустить
в той же песочнице другую программу. Отдельного контейнера для kandev
больше нет (был `bin/kandev-sandbox` с официальным образом, удалён
2026-10-06); kandev — пакет в инструментах песочницы
(`modules/nixos/packages/kandev.nix`, 0.97.0).

Удобно держать по конфигу на сферу — например работа, учёба, свои
проекты: у каждой свой домашний каталог и логины, проекты одной не видны
из другой, порты разные, чтобы все могли работать одновременно.

```ini
# ~/.config/agent-sandbox/projects/work.conf
dir       = ~/code/work/main
mount     = ~/code/work/other
publish   = 38429:38429                                   # kandev
autostart = kandev start --backend-port 38429
publish   = 3080:3080                                     # dsh web
autostart = dsh web --no-open --port 3081 --trusted-host 127.0.0.1:3080
autostart = socat TCP-LISTEN:3080,fork,reuseaddr TCP:127.0.0.1:3081
```
`study.conf` и `personal.conf` — то же со своими папками и портами
(например 38430/3090 и 38431/3100; во второй и третьей строке `autostart`
порты меняются так же).

```bash
agent-sandbox up @work            # контейнер + всё из autostart в фоне
# kandev: http://127.0.0.1:38429
agent-sandbox exec @work -- grep -o 'http://[^ ]*token=[^ ]*' /home/agent/.local-state/autostart.log
#   ссылка dsh с токеном: заменить порт 3081 на 3080 и открыть
agent-sandbox attach @work -- claude   # или просто терминал внутри
agent-sandbox down @work
```

- **`autostart`** — любые команды, `up` запускает их в фоне в том же
  контейнере; вывод — `~/.local-state/autostart.log` внутри песочницы.
- **dsh web через `socat`**: dsh (0.2.0-rc.2) отказывается слушать не
  loopback («would expose remote code execution to the network»), а проброс
  порта podman в loopback контейнера не попадает — dsh слушает
  `127.0.0.1:3081`, `socat` выставляет его на 3080. Порт на хосте по-прежнему
  только `127.0.0.1`.
- **kandev** пишет при старте предупреждение «reachable on non-loopback
  interfaces WITHOUT authentication» — внутри контейнера он слушает все
  интерфейсы (иначе проброс не дойдёт), но на хосте порт опубликован только
  на `127.0.0.1`.

**Первый запуск конфига** (`agent-sandbox attach @work`, внутри):
1. `claude login` — один раз на конфиг, им пользуются и терминал, и kandev,
   и dsh.
2. `dsh-setup` — ставит dsh `0.2.0-rc.2` (общий volume на все конфиги,
   один раз) и плагины из закреплённого списка `core` (канбан, ревью по
   строкам, токены); `dsh-setup extra` и `dsh-setup claude-sdk` — по
   желанию (второй — серая зона, спросит подтверждение). Профиль `~/.dsh`
   лежит в домашнем каталоге **этого** конфига, поэтому запускать внутри
   нужной песочницы: `agent-sandbox exec @work -- dsh-setup`, потом
   `down`/`up`. Списки — `modules/nixos/packages/dsh-plugins/`.
3. `gh auth login` — если нужны PR из kandev.
4. В kandev: **Settings → Agents** → профиль Claude Code → **CLI
   passthrough**, не дефолтный `claude-acp` (Agent SDK; подписку через него
   использовать нельзя, `system-plan.md` §9.7).

**Пакеты не дублируются:** языки mise хоста видны в песочнице только для
чтения (`MISE_SHARED_INSTALL_DIRS`), зависимости проектов лежат в самих
проектах (`node_modules`, `.venv`, гемы — `vendor/bundle` через
`BUNDLE_PATH` и на хосте, и в песочнице).

**`opencode web`** (по желанию, для пробы) запускается так же (порт **не 4096**:
это порт `opencode serve` по умолчанию, и при одновременном старте с kandev
`opencode web` на нём падал с «ServeError» — на 4200 в VM работают все три
доски разом):
`publish = 4200:4200` и `autostart = opencode web --hostname 0.0.0.0 --port 4200`
— напрямую, без `socat` (в отличие от dsh он умеет не-loopback). Он пишет
«OPENCODE_SERVER_PASSWORD is not set; server is unsecured»: порт на хосте
опубликован только на `127.0.0.1`, но при желании пароль задаётся этой
переменной. В логе будет безвредная ошибка про `xdg-open` — он пытается
открыть браузер, а его в песочнице нет.

Проверено в VM mimir (2026-10-06): kandev через `autostart` (HTTP 200 на
`127.0.0.1:38429`) и dsh web через `socat` (по ссылке с токеном пускает)
одновременно в одной песочнице; доп. папка из `mount` видна; `gh`,
`socat`, `BUNDLE_PATH` на месте. Подключение mise хоста проверено тестами
обёртки (в VM на хосте mise ещё ничего не ставил).

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

## Живые обои (Wallpaper Engine) и видео на экране блокировки

Wallpaper Engine куплен в Steam, но Steam-клиент не ставится: файлы
скачиваются один раз **SteamCMD** (официальный консольный Steam Valve, без
интерфейса и фоновых процессов), отрисовывает `linux-wallpaperengine`
(в системе, `modules/home/hyprland.nix`).

```bash
NIXPKGS_ALLOW_UNFREE=1 nix shell --impure nixpkgs#steamcmd
# сама программа -- нужна её папка assets (только в Windows-сборке):
steamcmd +@sSteamCmdForcePlatformType windows \
  +force_install_dir ~/.local/share/wallpaper-engine \
  +login <логин_steam> +app_update 431960 validate +quit
# обои: ID из ссылки мастерской (…/filedetails/?id=1234567890):
steamcmd +login <логин_steam> +workshop_download_item 431960 1234567890 +quit
#   → ~/.local/share/Steam/steamapps/workshop/content/431960/<id>/
```

- **Рабочий стол** — плагин DMS «Linux Wallpaper Engine» (ставится и
  настраивается вручную): путь к `assets` —
  `~/.local/share/wallpaper-engine/assets`, к обоям — папка мастерской выше.
  Работают обои типов scene и video; web/application — частично или нет.
  Живые обои постоянно грузят видеокарту — на батарее ставить на паузу.
- **Экран блокировки** — `lockscreen-videos`: собирает видео-обои
  Wallpaper Engine (тип video — обычные mp4) жёсткими ссылками в
  `~/Videos/Lockscreen` (места не занимает; DMS ищет видео через
  `find -type f`, символические ссылки он пропускает) и включает в DMS
  видео на экране блокировки из этой папки — каждый раз случайное.
  Свои видео можно просто положить туда же и запустить команду снова.
  Проверено в VM на временном каталоге (2026-10-06): берёт только тип
  video, жёсткая ссылка, настройки DMS обновлены, `find` DMS видео находит.

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
