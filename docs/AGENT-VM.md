# Агент в VM (agent-vm) и аккаунты Claude — как пользоваться

Агенты с доступом к коду работают в **одной microVM** со своим ядром и своим
Docker: если её взломают, ломается VM, а не хост и не ваша внутренняя сеть.
Устройство и модель угроз — `docs/superpowers/specs/2026-10-30-agent-vm-design.md`,
решения — `docs/REFERENCE.md` «agent-vm».

(До 2026-11-02 была ещё podman-песочница `agent-sandbox` с группами проектов и
одноразовыми контейнерами `--here`; она убрана из master и живёт в ветке
`agent-sandbox`.)

## Идея

Папки проектов лежат в VM по тем же путям, что на хосте (`~/code/my/app` — тот
же `~/code/my/app`), пользователь в VM — вы (`max`, тот же uid и `$HOME`).
Поэтому команда, запущенная в папке проекта, работает в той же папке в VM, а
сессии Claude общие (он хранит их по рабочему каталогу).

```bash
agent-vm up                        # поднять VM, записать git-идентичность, напечатать адреса
cd ~/code/my/app
agent-vm claude                    # claude в VM, в этой же папке   (то же: ai --vm, aiv)
agent-vm claude --account work     # один запуск под другим аккаунтом
agent-vm claude --continue         # продолжить сессию (общая с хостом)
agent-vm account work              # аккаунт по умолчанию в VM; agent-vm account --auto — обратно к правилам по пути
agent-vm shell [команда]           # шелл/команда в VM, в этой папке
agent-vm forward 3000 5432         # 127.0.0.1:порт на хосте -> тот же порт в VM (ssh -L); 5432 — Postgres VM
agent-vm docker-load postgres:16   # перенести образ из podman хоста в Docker VM
agent-vm test                      # проверка сетевой политики ИЗ VM
agent-vm down | status | urls | mounts | reset
```

## Конфиг

В конфиге хоста (`hosts/<хост>/configuration.nix`, пример — `demiurge`), не в
`~/.config`: общие папки virtiofs входят в командную строку qemu и фиксируются
при старте VM.

```nix
agentVm = {
  mounts = [
    { path = "/home/max/code/my"; }                 # чтение+запись
    { path = "/home/max/code/shared-lib"; ro = true; }
  ];
  claudeAccounts = [ "personal" "work" ];           # какие аккаунты видны в VM
};
```
После правки: `nixos-rebuild switch`, затем `agent-vm down && agent-vm up`.
Папка не из `mounts`: `agent-vm claude` предупредит и запустится в домашней
папке VM.

## Что общее с хостом, а что нет

| | в VM |
|---|---|
| Папки проектов | да, по тем же путям; запись в них — **канал на хост** (см. ниже) |
| Сессии Claude, история | да (`claude-accounts/shared`) |
| Skills, agents, commands, plugins, `settings.json`/`CLAUDE.md` аккаунтов | видны, **только чтение** — менять на хосте (см. «Настройки Claude») |
| Аккаунты Claude | только перечисленные в `claudeAccounts` (в них токен входа); правила `~/.config/claude-accounts/rules` — да, только чтение; `claude-use` внутри VM меняет аккаунт только в VM |
| Docker | **нет**: свой демон, образы и тома в VM. Образы хоста: `agent-vm docker-load`. Сокет хоста не пробрасывается никогда |
| git | имя, e-mail, `includeIf`-идентичности; **без ssh, без credential helper, без gpg**. Пушить с хоста или по https-токену на один репозиторий (как — README llm-dev-template, «Push из VM без ssh») |
| Языки (mise) | рантаймы хоста, только чтение (`MISE_SHARED_INSTALL_DIRS`) |
| ssh-ключи, ssh-agent, Bitwarden, `~/.ssh` | нет |
| Сеть | только интернет через фильтрующий прокси; LAN, VPN, `podman0`, метаданные — нет |
| Postgres 16, Redis | **свои, внутри VM, поднимаются сами при старте** (loopback; `PGHOST=127.0.0.1`, `PGUSER=postgres` без пароля, `REDIS_URL=redis://127.0.0.1:6379/0`); данные на своих дисках, переживают `down`/`up`; с хоста — `agent-vm forward 5432 6379`. Отключить: `agentVm.services = false` |
| Права Claude | **шире, чем на хосте**: к правилам хоста добавлены `docker`/`podman` (на хосте спрашивают), `sudo`, полный `systemctl`, `psql`, `redis-cli`, `pg_dump`; `git push`, `reset --hard`, `clean` по-прежнему спрашивают — они бьют по смонтированным папкам; запреты на секреты и массовое удаление те же. Задаётся `/etc/claude-code/managed-settings.json` в госте, правится в `agent-vm.nix` (`vmAllow`) |
| GUI/Playwright с окном | нет (Playwright MCP в VM — только headless) |

## Доски и терминал в браузере

- `http://127.0.0.1:38429` — kandev, `http://127.0.0.1:3080` — `dsh web`,
  `http://127.0.0.1:7681` — терминал (ttyd). Один kandev на все проекты;
  аккаунт задачи выбирается по правилам пути (`~/code/work` → work), потому что
  kandev — служба, до неё `agent-vm account` не доходит. Открывать в отдельном
  профиле браузера: контент из VM недоверенный.
- **dsh** ставится сам при старте VM (`npm -g` в `~/.npm-global` VM, версия
  `0.2.0-rc.2`), `dsh web` слушает 3081 и открыт на 3080 через socat (на
  не-loopback он сам отказывается). Плагины списка `core` ставятся сами
  (`dsh-setup`, повтор каждые 30 с, затем метка `~/.npm-global/.dsh-plugins-core`).
  Остальные списки — вручную: `agent-vm shell dsh-setup extra` (`claude-sdk`
  задаёт вопрос).

### Worktree'ы kandev на хосте

kandev кладёт worktree'ы задач в `<KANDEV_HOME_DIR>/tasks`, отдельной настройки
для этого нет (в исходниках: «relocate via KANDEV_HOME_DIR, not a separate
knob»), а перенос всего `KANDEV_HOME_DIR` утащил бы на хост БД и `master.key`.
Поэтому `agentVm.kandevTasksDir` (у `demiurge` — `/home/max/code/work/rnds/.worktrees`,
внутри rw-монтирования; иначе `nixos-rebuild` откажется) — в VM эта папка
bind-монтируется на `~/.kandev/tasks`, а на хосте `~/.kandev/tasks` — симлинк на
неё же. Симлинк в VM kandev 0.97 не принимает («safety anchor must be a real
directory»). Git записывает пути `~/.kandev/tasks/...`, и на хосте они
разрешаются через симлинк, поэтому worktree не `prunable`, ветка берётся
обычным `git switch`, IDE видит файлы (в том числе незакоммиченные).

Нюанс: пока worktree открыт в kandev, одну ветку не править с хоста параллельно
с агентом (`git switch --ignore-other-worktrees` обходит запрет, но две копии
одной ветки разъедутся).

## Риски

**Главный риск монтирований.** VM защищает систему и внутреннюю сеть, но не
файлы смонтированных папок и не то, что потом запускается из них на хосте:
подложенный `.git/hooks/pre-commit`, `.envrc`, `mise.toml`, скрипт в
`package.json`, задача IDE. Перед запуском чего-либо из проекта, в который
агент писал, смотрите `git diff` **и** `git status --ignored`, хуки; для
чужого кода — `ro = true`.

**Настройки Claude: меняются только на хосте** (ревью 2026-11-02). Дерево
`~/.local/share/claude-accounts` смонтировано в VM (иначе нет общих сессий и
логинов), но всё, что хостовый `claude` **загружает** как настройки, инструкции
или код, в VM только на чтение: `settings.json` и `CLAUDE.md` каждого аккаунта,
`shared/{skills,agents,commands,plugins}`. Плагины, навыки, `/model` по
умолчанию — менять на хосте. Свои настройки у VM — отдельный файл в git (блок
`managed-settings.json` в `modules/nixos/agent-vm.nix`). Остаются записываемыми:
логины (`.credentials.json` — обновление токена должно сохраняться),
`.claude.json` (собственное состояние claude-code) и сессии (`shared/projects`,
`history.jsonl`; подделанный транскрипт может направить `claude --continue` —
для чужого кода не продолжать сессии VM на хосте). Root в VM может снять
ro-монтирование, поэтому на хосте есть страховка: `modules/nixos/claude-managed.nix`
(только наши хуки и MCP) и `claude-use sync`, который вычищает из
`settings.json` ключи, запускающие команды.

- Всё, что лежит в VM (токены аккаунтов из `claudeAccounts`), при взломе
  считается украденным: заводите отдельный аккаунт/токен с лимитами.
- **Сеть**: всё наружу — через `HTTP(S)_PROXY` (docker, git, npm, curl
  настроены); сырой TCP/UDP не работает. Порты контейнеров из VM —
  `agent-vm forward`.
- `nixos-rebuild switch` работающую VM не перезапускает.

## Как запустить claude: `ai`, `aiv`

| Команда | Что делает |
|---|---|
| `ai [аргументы claude]` | на хосте, в этой папке |
| `aiv` (= `ai --vm`) | в VM, в этой папке (папка должна быть в `agentVm.mounts`) |
| `ai --account work …` | разово под другим аккаунтом (хост и VM) |

Аргументы после наших опций уходят в `claude` как есть: `ai --continue`,
`aiv --resume`. Наши опции — только длинные и только в начале. Беседу, начатую
`ai` в папке, продолжит `aiv` там же (`--continue`/`--resume`), и наоборот.

## Аккаунты Claude

Хост и VM используют общий каталог `~/.local/share/claude-accounts/`:

```
shared/      то, что принадлежит вам: сессии (projects/), history, skills, plugins…
personal/    логин личного аккаунта + .claude.json   (остальное — симлинки в shared/)
work/        логин рабочего аккаунта + .claude.json
```

Сессия, начатая под одним аккаунтом, продолжается под другим — ради этого
`projects/` общий. Какой аккаунт активен (первое совпадение):

1. `CLAUDE_ACCOUNT=work claude …` — разово;
2. `claude-use <аккаунт>` — переключатель «до отмены», действует на хосте **и** в VM;
3. `agent-vm account <аккаунт>` — по умолчанию в VM;
4. правила хоста `~/.config/claude-accounts/rules`:
   ```
   default = personal
   ~/code/work = work
   ```

Лимиты рабочего кончились:

```bash
claude-use personal          # теперь везде личный
claude --continue            # та же беседа
claude-use --auto            # вернуться к правилам (когда лимит сбросился)
claude-use                   # кто сейчас активен и почему
```

В kandev (служба в VM) аккаунт выбирается при **каждом** запуске агента, так что
после `claude-use personal` достаточно перезапустить/продолжить упавшую сессию —
беседа та же (транскрипты общие).

### Общие настройки для всех аккаунтов

Один блок в `modules/nixos/packages/claude-accounts.nix` (`baseSettings`) —
перед каждым запуском `claude` обёртка вливает его в `settings.json` текущего
аккаунта (`claude-use sync`, на хосте; в VM файл только для чтения). Ключи блока
**перебивают** ручные правки, остальные ключи аккаунта остаются. Сейчас: без
`Co-Authored-By`/подписи в PR и без ссылки на сессию (`attribution`), модель
`claude-sonnet-5-5`, режим разрешений `auto`, экономия токенов (автосжатие на
400K; без синхронизации скиллов и коннекторов claude.ai, без Artifact, редкие
скиллы выключены). Поменять — править блок и `nixos-rebuild switch`. Уже
запущенный `claude` настройки не перечитывает — перезапустить.

### Браузер для агента (Playwright MCP)

`claude-use sync` прописывает MCP-сервер `playwright` в `.claude.json` каждого
аккаунта (`baseMcp` в `claude-accounts.nix`); остальные серверы не трогаются, но
на хосте запускаются только разрешённые (`claude-managed.nix`). Браузер —
Chromium из nixpkgs. На хосте в сессии Hyprland окно видно;
`PLAYWRIGHT_MCP_HEADLESS=1` оставляет headless. В VM — только headless.

### Claude Code через npm (самообновление)

Nix-пакет `claude-code` неизменяем. Активация home-manager (`claudeCodeNpm` в
`modules/home/mise.nix`) ставит Claude Code в `~/.npm-global`, если его там нет;
дальше он обновляется сам (канал `latest`). Обёртка `claude` запускает
`~/.npm-global/bin/claude`, если он есть, иначе nix-бинарь — выбор аккаунта
работает в обоих случаях. В VM — свой `~/.npm-global`, туда Claude Code ставит
сервис `claude-npm-install` при старте VM (до 2026-11-02 его не было, и VM
отставала на Nix-версии). Откат:
`npm install -g @anthropic-ai/claude-code@<версия>`.

### Первая настройка (один раз)

Закройте все запущенные `claude`, затем:

```bash
claude-use --import personal --yes   # переносит ~/.claude и ~/.claude.json в новую раскладку
claude-use --add work
CLAUDE_ACCOUNT=work claude           # внутри: /login под рабочим аккаунтом
```

### Добавить аккаунт

```bash
claude-use --add <имя>              # имя: [a-z0-9_-]; создаёт каталог аккаунта и симлинки на общее
CLAUDE_ACCOUNT=<имя> claude         # внутри: /login под нужной подпиской (один раз)
```

Дальше: выбрать вручную (`claude-use <имя>`) или назначить папке (строка
`~/code/путь = <имя>` в `~/.config/claude-accounts/rules`). Чтобы аккаунт был
виден в VM — добавить в `agentVm.claudeAccounts`.

### Нюансы

- `settings.json` и `CLAUDE.md` копируются при `--add`, дальше у каждого
  аккаунта свои. Разрешения «always allow» выдаются по аккаунтам.
- `.claude.json` у каждого аккаунта свой (идентичность, «доверенные папки»): в
  новом аккаунте claude один раз спросит доверие к папке.
