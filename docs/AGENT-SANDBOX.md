# Песочница агентов — как пользоваться

Практическое шпаргалка-руководство: что набрать, в каком порядке. Почему
песочница устроена именно так — `system-plan.md` §9; история решений и
полный список нюансов — `docs/REFERENCE.md`, разделы «Песочница для
AI-агентов» и «DeepSeek Harness (`dsh`) в agent-sandbox».

Ничего отдельно ставить не нужно — `agent-sandbox` уже в PATH после
`nixos-rebuild switch` (модуль `modules/nixos/agent-sandbox.nix`).

## Быстрый старт

Разовая задача, без конфига:

```bash
agent-sandbox ~/code/myproject                # интерактивный shell в /workspace
agent-sandbox ~/code/myproject -- claude      # сразу запустить claude-code
agent-sandbox --gui ~/code/myproject          # + видимое окно (Chromium и т.п.) на десктопе
```

Контейнер одноразовый (`--rm`) — выход из shell его убивает. Что при этом
переживает перезапуск, а что нет — см. «Что сохраняется» ниже.

## Постоянный проект: свой конфиг (`@имя`)

Один раз завести файл `~/.config/agent-sandbox/projects/<имя>.conf`:

```ini
# ~/.config/agent-sandbox/projects/work.conf
dir      = ~/code/work/rnds       # основной проект → /workspace
mount_ro = ~/code/work/shared-lib # ещё папка, только чтение (mount — на запись)
publish  = 3080:3080              # порт наружу, только на 127.0.0.1 хоста
env      = RAILS_ENV=development  # обычная переменная (не секрет — секреты сюда не класть)
```

Дальше работать через `@имя`, не через путь:

```bash
agent-sandbox up @work                 # поднять (detached, живёт пока не down)
agent-sandbox attach @work -- claude   # зайти внутрь, сразу claude-code
agent-sandbox attach @work             # зайти внутрь, просто shell
agent-sandbox status                   # все поднятые песочницы
agent-sandbox down @work               # остановить (volume'ы с данными остаются)
```

Конфиг держать **вне** всех смонтированных на запись папок (скрипт сам
откажется работать иначе) — иначе агент теоретически мог бы дописать себе
доступ к другим директориям.

## Поднять kandev + dsh в конфиге

Оба — обычные `autostart`-команды в том же конфиге, стартуют в фоне внутри
контейнера при `up` (ключ `autostart`, повторяемый; лог —
`~/.local-state/autostart.log` внутри песочницы):

```ini
# ~/.config/agent-sandbox/projects/work.conf
dir       = ~/code/work/rnds

publish   = 38429:38429
autostart = kandev start --backend-port 38429

publish   = 3080:3080
autostart = dsh web --no-open --port 3081 --trusted-host 127.0.0.1:3080
autostart = socat TCP-LISTEN:3080,fork,reuseaddr TCP:127.0.0.1:3081
```

Зачем тут `socat`: `dsh web` сам отказывается слушать `0.0.0.0`
("would expose remote code execution to the network") и слушает только
`127.0.0.1:3081` **внутри** контейнера — а `publish` пробрасывает наружу
только порт самого контейнера, не его loopback. `socat` внутри контейнера
принимает на `3080` (который уже `publish`-нут наружу) и форвардит на
`127.0.0.1:3081`, где реально висит dsh. kandev так не делает — слушает
сразу на нужном порту, поэтому у него `socat` не нужен.

```bash
agent-sandbox up @work
```

**Куда заходить** (с хоста, в браузере):
- kandev — http://127.0.0.1:38429
- dsh web — http://127.0.0.1:3080 (не 3081 — это внутренний порт контейнера)

**Разовая настройка после первого `up`** (см. «Первый раз» ниже для
`claude login`/`gh auth login`):

```bash
agent-sandbox attach @work
dsh-setup            # ставит dsh + core-плагины (один раз на проект)
```

Плагины `dsh-setup` подхватывает только уже запущенный `dsh web` **при
следующем старте** — сама команда это печатает в конце
("Restart dsh web... to load the plugins"), так что после первого
`dsh-setup` перезапустить песочницу:

```bash
agent-sandbox down @work
agent-sandbox up @work
```

Для kandev отдельно, один раз в его собственном UI: Settings → Claude Code
profile → **CLI passthrough** — без этого kandev не сможет реально вызвать
claude-code.

## Первый раз в каждой новой песочнице

Логины живут в отдельном per-project volume, так что это разово на
проект, не на каждый `up`/`attach`:

```bash
agent-sandbox attach @work
claude login       # или: ANTHROPIC_API_KEY на хосте — подхватится сам
gh auth login       # если нужен gh (PR/issues)
```

`dsh-setup`/kandev-профиль — см. «Поднять kandev + dsh в конфиге» выше,
там же почему после первого `dsh-setup` нужен `down`+`up`.

## Шпаргалка команд

| Команда | Что делает |
|---|---|
| `agent-sandbox <путь>\|@имя [-- cmd]` | разово: shell или команда, контейнер удаляется при выходе |
| `agent-sandbox up <путь>\|@имя` | поднять именованный контейнер в фоне |
| `agent-sandbox attach <путь>\|@имя [-- cmd]` | зайти в уже поднятый |
| `agent-sandbox exec --no-tty <путь>\|@имя -- cmd` | выполнить и выйти, без TTY (скрипты/оркестраторы) |
| `agent-sandbox status` | какие именованные песочницы подняты |
| `agent-sandbox down <путь>\|@имя` | остановить (данные не теряются) |
| `--workdir <путь>` | старт в подкаталоге проекта (обычно git worktree в `.worktrees/<branch>`) |
| `--publish host:container` | +порт наружу, только на `127.0.0.1` |
| `--gitlab-token` | пробросить `GITLAB_TOKEN` (только Project Access Token, см. REFERENCE) |
| `--gui` | видимое окно на десктопе — нужна живая Hyprland-сессия |

## Что сохраняется между `down`/`up`, что нет

- **Сохраняется** (per-project home volume): история shell, `~/.gitconfig`,
  логины Claude/OpenCode (`claude login`), dsh и его плагины/сессии,
  настройки инструментов.
- **Сохраняется, общее на все проекты**: языки/раннтаймы через mise,
  `npm install -g`, `uv tool install`, бинарники в `~/.local/bin`.
- **Не сохраняется**: сам контейнер (пересоздаётся каждый `up`/разовый
  запуск) и всё, что записано вне `~` и вне смонтированных папок проекта
  (например `/tmp`).

## Установка версий языков

Ничего делать не нужно — если в проекте есть `.tool-versions`/`mise.toml`,
нужная версия ruby/node/etc ставится автоматически при старте контейнера
(`mise install`). Ручная установка libraries/бинарников вне mise — через
`npm install -g`/`uv tool install`/бинарник в `~/.local/bin`, переживает
перезапуски того же проекта.

## IDE на хосте

Ничего пробрасывать не нужно: песочница монтирует ту же папку проекта
(bind-mount, не копия) — RubyMine/VSCode на хосте видят те же файлы на
диске, что и агент внутри контейнера. Изолируется выполнение агента, не
файлы, которые вы редактируете.

## Известные нюансы (кратко; полный список — REFERENCE.md)

- `--gui` требует реальной Wayland-сессии (Hyprland) на хосте — без неё
  падает с понятной ошибкой.
- Ruby через mise подтверждён живьём (собирается из исходников). Node/
  Python/Go через mise технически должны работать (nix-ld), но ещё не
  обкатаны полным рантайм-прогоном — если что-то не находит интерпретатор,
  это первое место искать.
- Прокси в конфиге нет специально: Throne в TUN-режиме на хосте и так
  заворачивает весь трафик контейнеров.
