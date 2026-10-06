# TODO

Открытые задачи. Что сделано и почему — в `README.md` и `system-plan.md`;
здесь только то, что ещё не сделано или не проверено.

## Установка на mimir

- [ ] Поставить: `bin/mimir-install /dev/<диск>` с NixOS ISO (README,
      «Установка на реальную машину»). Скрипт ещё ни разу не запускался —
      ни в VM, ни на железе (на машине разработки не хватило места и
      nix-daemon не ходит через прокси).
- [ ] Закоммитить `hosts/mimir/facter.json` после установки.
- [ ] Secure Boot: Setup Mode в прошивке → `sudo sbctl enroll-keys --microsoft`
      → включить Secure Boot → `bootctl status`.
- [ ] Throne: импортировать VLESS-конфиг из Bitwarden, затем
      `desktopApps.rubymine.enable = true` и `nixos-rebuild switch`.
- [ ] Если `nixos-install` упадёт на скачивании Android Studio (тоже не из
      кэша, а с серверов Google) — выключить её так же, как RubyMine.
- [ ] Проверить hibernate (swap в LUKS, `resumeDevice`).

## kandev (`bin/kandev-sandbox`) — проверить на mimir

Проверено только с docker вместо podman (README, «Доска агентов kandev»).

- [ ] `--userns=keep-id:uid=1000,gid=1000` на настоящем rootless podman:
      файлы, созданные агентом, принадлежат `max`.
- [ ] `/nix/store` только для чтения + mise хоста: Ruby, собранный mise
      на NixOS, запускается внутри Debian-контейнера kandev.
- [ ] Первый запуск по чек-листу README: `claude login`,
      `npm i -g @fission-ai/openspec`, профиль Claude Code → **CLI passthrough**.

## dsh в agent-sandbox

- [ ] Закрепить dsh на `0.2.0-rc.2` (плагины ниже рассчитаны на эту
      версию; `dsh-file-review` на 0.2.1 уже не работает).
- [ ] `DSH_HOME` — на per-project volume (`agent-creds-<hash>`), как логины
      Claude: сессии одного проекта не видны из другого.
- [ ] `openspec` в образ из nixpkgs (1.7.0 есть).
- [ ] Команда для Web UI: `agent-sandbox up --publish 3080:3080 <dir>` +
      `dsh web --host 0.0.0.0` внутри (порт на хосте — только 127.0.0.1).
- [ ] Файл со списком плагинов + установка одной командой
      (`dsh plugin --profile web add …`). Выбрать стартовый набор:

  | Задача | npm | Что даёт |
  |---|---|---|
  | Канбан | `@shengsheng/dsh-taskboard` | статусы до `in_review`, `done` ставит только человек |
  | Ревью | `dsh-file-review` | комментарии к строкам диффа → агенту пачкой |
  | | `dsh-better-sidebar` | файлы/git/терминал; file-review встраивается сюда |
  | OpenSpec | `dsh-openspec` | skills OpenSpec + CLI |
  | Токены | `dsh-context` | состав контекста, токены по запросам |
  | | `dsh-cost-meter` | стоимость, бюджеты |
  | Трейс | `dsh-maze` | таймлайн выполнения, сравнение сессий |
  | Мультиагенты | `@nanmicoder/dsh-agent-teams` | план → исполнение → ревью |
  | Авто-ревью | `dsh-auto-review` | вторая модель проверяет запросы на подтверждение |

  Не ставить: `dsh-plugin-subscriptions` и `dsh-subagent-claude-code` с
  подпиской — OAuth подписки Claude вне самого Claude Code запрещён
  условиями Anthropic (`system-plan.md` §9.7). Claude в dsh — только по
  API-ключу.

## agent-sandbox: конфиг на проект

Исходный запрос: конфигурационный файл для каждого проекта — несколько
папок, прокси, задел на расширение.

- [ ] Конфиг вне монтируемых папок (`~/.config/agent-sandbox/projects/<name>.toml`),
      иначе агент сможет дописать себе доступ к другим папкам.
- [ ] Поля: основная папка, доп. папки (rw/ro), прокси, env, порты.
- [ ] Volume'ы `agent-cache-*`/`agent-creds-*` — по имени профиля, а не по
      хэшу пути.

## llm-dev-template (`~/code/my/llm-dev-template`)

- [ ] Удалить `forge/` и `board-lab/`.
- [ ] Процесс как workflow kandev в YAML (`.kandev/workflow.yml`): спека →
      ревью спеки → реализация → проверки + ИИ-ревью → ревью кода → отчёт.
- [ ] `init.sh` вместо `forge init`: копия `template/`, `openspec init
      --language ru`, `lefthook install`.
- [ ] ADR 0002: переход с Multica/forge на kandev + dsh.

## Отложено

- Sidecar-контейнеры для секретов — ветка `feature/agent-sidecars`; влить,
  когда агенту понадобятся настоящие ключи (подпись запросов и т.п.).
- LocalSend: входящий приём требует открыть порт 53317 в firewall — не
  сделано по просьбе не трогать firewall.
