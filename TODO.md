# TODO

Только открытое. Сделанное — в `docs/REQUESTS.md` (журнал), почему так — в
`docs/REFERENCE.md` и `system-plan.md`. Рабочая машина `demiurge` установлена и
работает (Throne, RubyMine, agent-vm с kandev и терминалом); пункты про неё,
которые уже работают, отсюда убраны 2026-11-02.

## После ближайшего `nixos-rebuild switch` на demiurge (правки 2026-11-02)

- [ ] Трекер времени: `systemctl --user status aw-server awatcher` активны,
      http://localhost:5600 показывает окна.
- [ ] Лок: `Win+L`, затем с другого TTY `systemctl --user kill -s KILL dms` →
      экран остаётся заблокированным, DMS снова показывает пароль.
- [ ] Claude на хосте: `/status` видит managed settings, playwright MCP работает.
- [ ] agent-vm (`agent-vm down && agent-vm up && agent-vm test`):
      в VM `sudo touch f && sudo chmod 4755 f` и `sudo mknod d b 259 0` в
      смонтированной папке → на хосте `f` принадлежит max без setuid-root,
      `mknod` отказывает; `settings.json` аккаунта в VM не пишется, логин и
      `claude --continue` работают.
- [ ] `dsh web` в VM не отвечает (`agent-vm status`: `dsh ... -> 000` при
      работающих kandev и ttyd, 2026-11-02) — `agent-vm shell journalctl -u dsh-web -u dsh-install`.
- [ ] KDE Connect с телефона в домашней сети по-прежнему находит машину.
- [ ] Выход из сессии и вход обратно после правки `hyprland.nix` (UWSM, отдельный коммит).

## agent-vm

- [ ] Запуск claude в папке, которой нет в `agentVm.mounts` — выбрать
      вариант (предложения — в разговоре 2026-11-02; после выбора — в `docs/AGENT-VM.md`).
- [ ] Смонтировать `.git/hooks` проектов только для чтения поверх rw-шары
      (самый вероятный канал из VM на хост).
- [ ] Тест `bin/agent-vm` с фейковым ssh в flake check `scripts`.
- [ ] По желанию: allowlist доменов в фильтре (sing-box `domain_suffix` + `final = reject`).
- [ ] По желанию: GUI/Playwright с окном в госте.
- [ ] Домен, доступный только через прокси Throne (нужен sniff на его inbound) — проверить из VM.

## Безопасность (остаток ревью 2026-11-02)

- [ ] Контейнеры podman хоста видят loopback хоста (`--map-host-loopback`:
      Postgres без пароля, Redis, порты agent-vm, aw-server). Оставлено
      сознательно — этим пользуются compose-проекты (БД хоста).

## Установка на mimir (ноутбук, ещё не установлен)

- [ ] `bin/install-host mimir /dev/<диск>` с NixOS ISO (`docs/INSTALL.md`);
      `install-host` ещё не запускался (в VM прошёл его предшественник).
      Сначала прогнать в VM: проверить, что `~/.config`/`~/.local` после
      первой загрузки принадлежат max (исправление tmpfiles agent-vm).
- [ ] Закоммитить `hosts/mimir/facter.json`.
- [ ] Secure Boot: Setup Mode → `sudo sbctl enroll-keys --microsoft` →
      включить → `bootctl status` (на demiurge Secure Boot выключен).
- [ ] Throne + VLESS из Bitwarden, затем `desktopApps.rubymine.enable = true`
      в `hosts/mimir/configuration.nix`.
- [ ] Проверить hibernate (swap в LUKS, `resumeDevice`).

## llm-dev-template (`~/code/my/llm-dev-template`)

- [ ] Прогнать одну настоящую задачу через все шаги workflow (kandev в VM).
- [ ] Заново импортировать `.kandev/workflow.yml` в kandev (шаг «Архив»);
      правки не закоммичены в репозитории шаблона.
- [ ] Бэкап локальных спек `--team` (`openspec/` не в git проекта): отдельный
      приватный git или ничего (ADR 0003 шаблона).

## Отложено

- Удалённый доступ (`remote-access.nix`): на железе не проверены
  `remote-screen` с другого компьютера по Remmina, приём файла LocalSend, бан
  fail2ban (sshd и fail2ban на demiurge работают).
- Anthropic: отдельный пул для `claude -p`/SDK приостановлен, может вернуться.
