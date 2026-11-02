# Журнал просьб и косяков

Отвечает на вопрос «что я просил/на что жаловался и где это сделано?» — чтобы при
переезде на другую машину или систему ничего не потерять. Не заменяет `TODO.md`
(там только невыполненное) и `docs/REFERENCE.md` (там «почему сделано так»).

**Как вести.** Новая просьба или баг = строка в таблице: дата, суть, статус, где в
репозитории. Статусы: `сделано` (проверено вживую), `не проверено` (написано, но не
запускалось на железе), `ограничение` (так не лечится, см. ссылку), `открыто`.
Следующая сессия начинается с фильтра по `не проверено`.

**Старое, до этого файла.** Почти каждая правка в `modules/` помечена комментарием с датой
«запрошено live / reported live / found live YYYY-MM-DD» — достаточно
`rg -i "запрошено live|reported live|found live|asked live"`, чтобы получить
полный список с контекстом (больше всего в `modules/home/hyprland.nix`).

| Дата | Просьба / косяк | Статус | Где |
|---|---|---|---|
| 2026-10-20 | Поиск по командам в zsh сломался | не проверено | `modules/home/shell.nix` (стрелки в двух формах, `programs.fzf`); `docs/DAILY-WORKFLOW.md` «Поиск по командам» |
| 2026-10-20 | Ctrl+Shift+V (и C, T, W, N) в Ghostty не работают на русской раскладке | не проверено | `modules/home/ghostty.nix` (`physical:`) |
| 2026-10-20 | Горячие клавиши и `q` в консольных программах на русской раскладке | ограничение (кроме neovim: `langmap`) | `docs/DAILY-WORKFLOW.md` «Русская раскладка» |
| 2026-10-20 | Vimium так, чтобы работал на русской раскладке | сделано в расширении (не в Nix) | `docs/DAILY-WORKFLOW.md` «Vimium» |
| 2026-10-20 | Win+Alt+L не гасит экран / неотличим от Win+L | не проверено | `modules/home/hyprland.nix` (задержка 1 с, причина — `Lock.qml` DMS) |
| 2026-10-20 | Колесо мыши крутит окно в фокусе, а не под курсором | не проверено | `modules/home/hyprland.nix` (`follow_mouse = 2`) |
| 2026-10-20 | Доступ к машине: SSH, удалённый экран, LocalSend, пароль на всё | не проверено на железе | `modules/nixos/remote-access.nix`; `docs/DAILY-WORKFLOW.md` «Удалённый доступ» |
| 2026-10-20 | Общие настройки Claude (без подписи, Sonnet 5.5, auto mode) | сделано | `modules/nixos/packages/claude-accounts.nix` |
| 2026-10-20 | Сессии Claude общие хост/песочница; `ai`/`aih`/`ais`; любая папка в песочнице | сделано | `bin/ai`, `bin/agent-sandbox --here` |
| 2026-10-20 | Worktree kandev видеть с хоста | сделано 2026-10-22 (`worktrees =` в конфиге; осталось включить в `work-rnds.conf` и проверить на живой задаче) | ветка `agent-sandbox`: `docs/AGENT-SANDBOX.md` «Worktree kandev с хоста» |
| 2026-10-20 | SSH для git внутри песочницы | открыто | — |
| 2026-10-21 | Контейнеры у агента: в песочнице можно, на хосте по запросу; поискать готовые аналоги песочницы | аналоги исследованы (заменять нечем), вложенный podman — открыто | `docs/REFERENCE.md` «Аналоги agent-sandbox», `TODO.md` |
| 2026-10-22 | Вход на хосте «слетел»: npm-самообновление положило claude в node mise, он перекрыл обёртку → читался старый `~/.claude` | сделано (`NPM_CONFIG_PREFIX=~/.npm-global` на хосте; нужен перелогин сессии) | `modules/home/mise.nix` |
| 2026-10-22 | `ais` в проекте с pin node 24.3.0 показывал онбординг/логин: самообновление положило claude в node проекта, `mise exec` поставил его впереди обёртки | сделано (копии удалены; обёртка возвращается в начало PATH после `mise exec`; `ai`/алиас `claude` зовут обёртку по абсолютному пути; нужны switch и `agent-sandbox down && up`) | `modules/nixos/packages/agent-sandbox.nix`, `bin/ai`, `modules/home/shell.nix` |
| 2026-10-22 | Песочница сразу поднимает postgres и redis (расширяемо, данные переживают перезапуск) | сделано (`service =` в конфиге, таблица сервисов в `agent-services.nix`; нужны switch и `agent-sandbox down && up`) | ветка `agent-sandbox`: `docs/AGENT-SANDBOX.md` «Postgres и Redis в песочнице» |
| 2026-10-22 | `ais`/`agent-sandbox --here`: `ENOENT mkdir /tmp/claude-1000` при двух `--here`-песочницах сразу | сделано (`/tmp` теперь свой на контейнер, а не общий `tmp-adhoc`, который второй `up` стирал; уже запущенные `here-*` нужно перезапустить: `down --here`) | `bin/agent-sandbox` |
| 2026-10-26 | Нужен пакет для zip; zip не открывается в графическом файловом менеджере | сделано (`zip` в base.nix; `file-roller` + дефолтные обработчики архивов в desktop-apps.nix; нужен switch; `nix flake check` не гонялся — в песочнице нет nix) | `modules/nixos/base.nix`, `modules/nixos/desktop-apps.nix` |
| 2026-10-26 | LibreOffice «зависает» при открытии docx (окно «не отвечает») | причина найдена: libcups ждёт ~30 с соединения с `::1:631` (CUPS на системе не установлен), а IPv6-loopback дропается (`ping -6 ::1` 100% loss; `127.0.0.1:631` отказывает мгновенно). Обход: `SAL_DISABLE_CUPS=1` или `CUPS_SERVER=127.0.0.1` (1 с вместо 31 с). Корень (кто дропает ::1 — firewall или Throne TUN) — открыто; шрифты (Liberation/DejaVu/Noto) добавлены попутно, к зависанию отношения не имеют | `modules/nixos/desktop-apps.nix` |
| 2026-10-30 | Дать агенту Docker/контейнеры и не переживать за взлом: работа не на хосте, без ssh и внутренней сети, только наружу; удобно открывать claude/kandev в браузере | код сделан, на живой машине не запускалось: `agent-vm` (microVM + прокси-only выход, фильтр на втором sing-box); нужен `switch`, затем `agent-vm up && agent-vm test` | `docs/superpowers/specs/2026-10-30-agent-vm-design.md`, `docs/AGENT-VM.md` «agent-vm» |
| 2026-10-30 | agent-vm: одна VM вместо групп, конфиг монтирований, переключение аккаунта, `claude` из папки проекта, общие сессии; что общее (docker, git без ssh) | код сделан, на живой машине не запускалось (`agentVm.mounts`/`claudeAccounts`, `agent-vm claude/account`, `ai --vm`); нужен switch → `agent-vm up && agent-vm test` | `docs/AGENT-VM.md` «agent-vm», `modules/nixos/agent-vm.nix` |
| 2026-10-30 | В agent-vm сразу поднимать Postgres и Redis | код сделан, на живой машине не запускалось (`agentVm.services`, по умолчанию включено; `agent-vm test` проверяет оба) | `docs/AGENT-VM.md` «agent-vm», `modules/nixos/agent-vm.nix` |
| 2026-10-30 | Работать только в VM без песочницы: один kandev и dsh, worktree'ы kandev на хосте; права Claude в VM шире | код сделан, на живой машине не запускалось (`kandevTasksDir`, службы `dsh-web`/`dsh-install`, `/etc/claude-code/managed-settings.json`); нужен switch + `agent-vm down && up` | `docs/AGENT-VM.md` «agent-vm», `modules/nixos/agent-vm.nix` |
| 2026-10-30 | Расширить разрешения Claude на хосте: подтверждения только тратят время | сделано (в `allow` локальный git, docker/podman, nix build/check, сборка/тесты, чтение gh; спрашивают только `git push`/`reset --hard`/`clean`; `deny` не тронут; нужен `switch`, действует при следующем запуске `claude`) | `modules/nixos/packages/claude-accounts.nix`, `docs/REFERENCE.md` «Права Claude на хосте шире» |
| 2026-11-02 | Убрать живые обои и отдельную логику двух блокировок | сделано (удалены `linux-wallpaperengine`, `lockscreen-videos`, бинд Win+Alt+L с задержкой; остался один `Win+L`); нужен `switch` | `modules/home/hyprland.nix`, `docs/REFERENCE.md` «Живые обои — убраны» |
| 2026-11-02 | Трекер времени «не наблюдается» | причина: `awatcher` стоял, но не запускался и не было сервера ActivityWatch; добавлены user-сервисы `aw-server`+`awatcher`; нужен `switch`, затем http://localhost:5600 | `modules/home/time-tracker.nix` |
| 2026-11-02 | Ревью всей репы Opus-субагентом и исправления по порядку | исправлено C1, C2, H1, H3, H4, M3–M5 и часть мелочей; остаток в `TODO.md` «Ревью Opus»; нужен `switch` и живая проверка | `docs/REFERENCE.md` «Ревью репозитория Opus» |
| 2026-11-02 | Убрать agent-sandbox (в отдельную ветку), оставить одну VM; убрать одноразовые песочницы | сделано: код, тесты, доки песочницы — в ветке `agent-sandbox`; `ai` = хост, `aiv` = VM; docs/AGENT-SANDBOX.md → docs/AGENT-VM.md | `docs/AGENT-VM.md`, ветка `agent-sandbox` |
| 2026-11-02 | Настройки Claude в песочнице/VM только для чтения (меняю только на хосте), у песочницы свой файл; docker/podman в песочнице разрешены как раньше | сделано (ro-bind settings.json/CLAUDE.md в VM; файл настроек песочницы и docker/podman — в ветке `agent-sandbox`) | `modules/nixos/agent-vm.nix`, `docs/AGENT-VM.md` «Риски» |
| 2026-11-02 | KDE Connect только из LAN | сделано (`remoteAccess.lanOnly` сужает 1714–1764 до частных сетей); нужен `switch` | `modules/nixos/remote-access.nix` |
