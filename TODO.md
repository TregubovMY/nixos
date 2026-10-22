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

- [ ] Конфиги `work`/`my` (`~/.config/agent-sandbox/projects/`, пример в
      `docs/AGENT-SANDBOX.md`) со своими портами.
- [ ] Первый запуск каждого: `dsh-setup` (rc.2), в kandev профиль Claude Code →
      **CLI passthrough**. Логин Claude общий с хостом (`claude-use`).
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
      логин Claude (общий с хостом) и модель dsh (DeepSeek по API-ключу).
- [ ] Опционально: `dsh-setup claude-sdk` (серая зона, на подписке) —
      сравнить с `conductor`.
- [ ] `dsh-setup extra`: при желании; `dsh-maze` не ставится (его peer-диапазон
      `<0.2.0` исключает rc.2).
- [ ] Следить за статьёй Anthropic о плане Agent SDK: отдельный пул для
      `claude -p`/SDK приостановлен, но может вернуться.

## agent-sandbox: группы проектов и аккаунты Claude (2026-10-19) — проверить живьём

Переписано (песочница = группа проектов по хостовым путям, без `/workspace`,
`up`/`attach`/`exec` слиты в `agent-sandbox [@имя] [-- cmd]`, аккаунты Claude
через `claude-use`). Проверено тестами с фейковым podman и сборкой rootfs;
живьём с podman — нет.

- [ ] `nixos-rebuild switch`, затем по `docs/AGENT-SANDBOX.md`: конфиги `work`
      и `my` (`rw = ~/code/my`, `~/code/learn`, `~/code/sfedu`; старый
      `person.conf` удалить), правила `~/.config/claude-accounts/rules`.
- [ ] Закрыть все `claude`, `claude-use --import personal --yes`,
      `claude-use --add work`, `CLAUDE_ACCOUNT=work claude` → `/login`.
- [ ] `agent-sandbox up` → `pwd` внутри совпадает с хостовым;
      `agent-sandbox --no-tty -- false; echo $?` → 1; `down`.
- [ ] **Сессии общие**: начать беседу на хосте, в песочнице `claude --continue`
      видит её (и наоборот).
- [ ] **Переключение**: `claude-use work` → беседа под личным аккаунтом →
      `claude-use personal` → `claude --continue` продолжает ту же беседу.
      Если `--continue` под другим аккаунтом не подхватывает сессию —
      пересмотреть раскладку `claude-accounts` (`system-plan.md` §9.8).
- [ ] `mise.toml` в папках группы (`AGENT_MOUNTS`), `~/.gitconfig`/история на
      месте после `down`/`up`.
- [ ] Следующее усиление по результатам обзора: allowlist сети для песочниц;
      `runsc` (gVisor) как runtime podman — проверить, собирается ли ruby.
- [ ] Править Nix-конфиг агентом: отдельная песочница для `~/code/nixos` с
      read-only наложением на файлы самой песочницы (`bin/agent-sandbox`,
      `modules/nixos/*agent-sandbox*`) — пока репозиторий правится на хосте.

## llm-dev-template (`~/code/my/llm-dev-template`)

Переделан под kandev/dsh (ADR 0002 шаблона): forge и board-lab удалены,
процесс — `template/.kandev/workflow.yml` (импорт в kandev 0.97.0 проверен),
`init.sh`, `scripts/checks`, `scripts/scrub`.

- [ ] Прогнать одну настоящую задачу через все шаги workflow на mimir.
- [ ] Заново импортировать `.kandev/workflow.yml` в kandev: добавлен шаг «Архив»
      (позиции шагов сдвинулись), ключ тикета стал необязательным.
      Правки не закоммичены в репозитории шаблона.
- [ ] Бэкап локальных спек в `--team` (`openspec/` не в git проекта): отдельный
      приватный git поверх `openspec/` или ничего (ADR 0003 шаблона).

## Отложено

- Sidecar-контейнеры для секретов — ветка `feature/agent-sidecars`; влить,
  когда агенту понадобятся настоящие ключи (подпись запросов и т.п.).
- Удалённый доступ (`modules/nixos/remote-access.nix`, 2026-10-20) — не
  проверено на железе после `switch`: правила firewall (`iptables -S
  nixos-fw`), `remote-screen` с другого компьютера по Remmina, приём файла
  LocalSend, бан fail2ban. Локально проверено: `remote-screen` поднимается,
  не предлагает вход без пароля (VeNCrypt/RSA-AES), убирает за собой.

## kandev: worktree'ы в проект (2026-10-20, сделано 2026-10-22)

- [x] Ключ `worktrees =` в конфиге песочницы (симлинк `~/.kandev/tasks`, миграция старых
      worktree'ов). Своей настройки базы worktree'ов у kandev нет — см. `docs/AGENT-SANDBOX.md`,
      «Worktree kandev с хоста».
- [ ] Включить в `work-rnds.conf` (`worktrees = ~/code/work/rnds/.worktrees`) и проверить на
      живой задаче kandev: создание, удаление задачи (cleanupOnRemove), повторный запуск.

## agent-sandbox: контейнеры у агента и готовые аналоги (2026-10-21)

- [ ] Проверить вложенный rootless podman в песочнице: `/tmp/nested-podman-check.sh`
      (варианты A/B/C: текущие флаги → `/dev/fuse` + `seccomp=unconfined` →
      + `label=disable`). Если без `--privileged`/`SYS_ADMIN` не взлетает —
      оставить `ask` для `docker`/`podman` везде (`claude-accounts.nix`);
      если взлетает — `allow` внутри песочницы (различать по env песочницы
      в `claude-use sync`), на хосте `ask`. Сокет хоста в песочницу не
      пробрасывать никогда (root-эквивалент).
- [x] (сделано 2026-10-21, итог — `docs/REFERENCE.md` «Аналоги `agent-sandbox`»: заменять нечем; идеи ниже вынесены в отдельные пункты) Посмотреть, есть ли готовые решения, которые могут заменить мою
      реализацию `agent-sandbox`: terok, ExitBox, mino, hort (podman);
      ai-jail, aibox, jailed-agents (bubblewrap, Nix); каталог
      github.com/fishman/awesome-agent-sandbox. Сравнить по: rootfs из
      `/nix/store` без образов, профили аккаунтов, проброс git-идентичности
      и прокси, GUI, вложенные контейнеры, сеть (default-deny), хранилище
      секретов. Уже известно: ни terok, ни ExitBox вложенные контейнеры не
      документируют (ExitBox даже запрещает: `--cap-drop=ALL`,
      `no-new-privileges`). Взять идеи: egress-allowlist (ExitBox: Squid;
      terok: nftables) и vault для ключей на хосте.
- [ ] agent-sandbox: опциональный egress-allowlist (`network = allowlist`
      в конфиге группы; `terok-shield` или Squid-sidecar), по умолчанию
      сеть открыта. Идея из исследования аналогов.
- [ ] agent-sandbox: режим `--lockdown` (ro-проект + `--network=none`)
      для чтения чужого кода.
