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

Сделано и проверено в VM (2026-10-06): `dsh-setup` (dsh `0.2.0-rc.2` +
плагины из закреплённых списков `modules/nixos/packages/dsh-plugins/`),
все пять плагинов `core` грузятся в интерфейс dsh; веб-интерфейс через
`socat`; навык `conductor` в шаблоне (закреплён, `doctor` и `--dry-run`
проверены в песочнице); `opencode web` в песочнице.

- [ ] Пройти руками: канбан (`dsh-taskboard`), ревью по строкам
      (`dsh-file-review` → отправка агенту), токены (`dsh-cost-meter`).
- [ ] `conductor` вживую: «попроси Claude Code объяснить файл» → в песочнице
      запускается именно `claude -p`, запись заблокирована. Нужны
      `claude login` в песочнице и модель dsh (DeepSeek по API-ключу).
- [ ] Опционально: `dsh-setup claude-sdk` (серая зона, на подписке) —
      сравнить с `conductor`.
- [ ] `dsh-setup extra`: при желании; `dsh-maze` не ставится (его peer-диапазон
      `<0.2.0` исключает rc.2).
- [ ] Следить за статьёй Anthropic о плане Agent SDK: отдельный пул для
      `claude -p`/SDK приостановлен, но может вернуться.

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
