# TODO

Открытые задачи. Что сделано и почему — в `README.md` и `system-plan.md`;
здесь только то, что ещё не сделано или не проверено.

## Установка на mimir

- [x] Прогон в VM (`docs/INSTALL.md`) — пройден 2026-10-06.
- [ ] Поставить: `bin/install-host mimir /dev/<диск>` с NixOS ISO
      (`docs/INSTALL.md`). В VM прошёл его предшественник `bin/mimir-install`;
      `install-host` (имя машины, swap = RAM + 2G) отличается только этим и
      ещё не запускался.
- [ ] Закоммитить `hosts/mimir/facter.json` после установки.
- [ ] Secure Boot: Setup Mode в прошивке → `sudo sbctl enroll-keys --microsoft`
      → включить Secure Boot → `bootctl status`.
- [ ] Throne: маршрутизация по README «Прокси и рабочий VPN» (по умолчанию
      direct, список доменов → proxy, rnds.pro и рабочие подсети → direct);
      импорт рабочего `.ovpn` в NetworkManager.
- [ ] Throne: импортировать VLESS-конфиг из Bitwarden, затем
      `desktopApps.rubymine.enable = true` и `nixos-rebuild switch`.
- [ ] Если `nixos-install` упадёт на скачивании Android Studio (тоже не из
      кэша, а с серверов Google) — выключить её так же, как RubyMine.
- [ ] Проверить hibernate (swap в LUKS, `resumeDevice`).

## Одна песочница (kandev, dsh, Claude) — проверить на mimir

Проверено в VM (README, «Одна песочница»): kandev и dsh web в одном
контейнере через `autostart`, `socat` для dsh, доп. папки, `gh`.

- [ ] Конфиги `work`/`study`/`personal` (`~/.config/agent-sandbox/projects/`,
      пример в README) со своими портами.
- [ ] Первый запуск каждого: `claude login`, `npm i -g @deepseek-ai/dsh@0.2.0-rc.2`,
      в kandev профиль Claude Code → **CLI passthrough**.
- [ ] mise хоста в песочнице: `mise use -g node@22` на хосте → в песочнице
      `node -v` без скачивания; Ruby, собранный mise на хосте, запускается
      в песочнице.

## dsh в agent-sandbox

- [ ] Закрепить dsh на `0.2.0-rc.2` (плагины ниже рассчитаны на эту
      версию; `dsh-file-review` на 0.2.1 уже не работает).
- [x] `~/.dsh` (профиль, плагины, сессии) сохраняется — в постоянном
      домашнем volume проекта (`agent-home-*`), отдельно для каждого проекта.
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

## agent-sandbox: конфиг проекта (`@name`) — проверить на mimir

Сделано (README, «Конфиг проекта»), проверено тестами с фейковым podman.

- [ ] Пересобрать образ (`AGENT_EXTRA_TRUSTED` в entrypoint) и проверить
      `mise.toml` в дополнительной папке.
- [ ] Постоянный `agent-home-*` на `/home/agent` с вложенными общими
      volume'ами: после `down`/`up` на месте `~/.gitconfig`, история,
      `~/.dsh`; общие mise/npm по-прежнему общие.

## llm-dev-template (`~/code/my/llm-dev-template`)

Переделан под kandev/dsh (ADR 0002 шаблона): forge и board-lab удалены,
процесс — `template/.kandev/workflow.yml` (импорт в kandev 0.97.0 проверен),
`init.sh`, `scripts/checks`, `scripts/scrub`.

- [ ] Прогнать одну настоящую задачу через все шаги workflow на mimir.

## Отложено

- Sidecar-контейнеры для секретов — ветка `feature/agent-sidecars`; влить,
  когда агенту понадобятся настоящие ключи (подпись запросов и т.п.).
- LocalSend: входящий приём требует открыть порт 53317 в firewall — не
  сделано по просьбе не трогать firewall.
