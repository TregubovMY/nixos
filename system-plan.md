# План переносимой системы: NixOS + Hyprland

## 1. Цель

Одна декларативная конфигурация в git, из которой можно поднять идентичную
систему на любом железе: разметка диска и LUKS — автоматически, десктоп и
пакеты — идентичны, личные данные (пароли, SSH, куки) — подтягиваются
логином в 2-3 внешних сервиса, а не копированием файлов.

## 2. Архитектура

| Слой | Технология | Роль |
|---|---|---|
| Диск/разметка | **disko** | Декларативное описание партиций, LUKS, файловой системы в `.nix` |
| Шифрование | **LUKS2** (внутри disko) | Полное шифрование корня, разблокировка паролем при загрузке |
| Загрузчик | **systemd-boot** | Простой UEFI-бутлоадер, нативная интеграция с NixOS |
| Secure Boot | **lanzaboote** | Свои ключи через `sbctl`, доверенный boot-chain сверх LUKS |
| ОС | **NixOS** (unstable или последний stable) | Декларативная система, атомарные обновления/откаты |
| Пользовательские настройки | **home-manager** | Dotfiles, пользовательские пакеты, привязка к NixOS-модулям |
| Секреты | **sops-nix** (age) | Зашифрованные секреты прямо в git-репозитории |
| DE/Compositor | **Hyprland** (Wayland) | Тайлинговый WM |
| Виртуализация для тестов | **QEMU/KVM + `nixos-rebuild build-vm`** | Проверка конфигурации перед накаткой на реальное железо |

**Важный нюанс про unfree-пакеты, найденный при реализации §5.4-§5.10
(desktop-packages, 2026-08-10):** `flake.nix`'s `pkgs = import nixpkgs {
config.allowUnfree = true; ... }` — это отдельный, самостоятельный
`pkgs`-инстанс, используемый только для `packages.${system}`
(agent-sandbox-образ). Он **не** пропагирует `allowUnfree` ни в один
`nixpkgs.lib.nixosSystem { ... }`/`nixosConfigurations` вызов — у каждого
такого вызова своя, независимая nixpkgs-эвалюация. `CLAUDE.md`
("Unfree-пакеты... уже должно быть включено в `flake.nix`/
`configuration.nix`, не дублировать в каждом модуле") на момент
2026-08-10 описывал желаемое состояние, а не фактическое: до
`hosts/test-desktop-apps/` ни один хост-конфиг в этом репозитории не
объявлял `nixpkgs.config.allowUnfree = true;` сам — просто не было unfree
пакетов в списке до этого раунда. Вывод: **каждый `nixosConfigurations.*`
(включая будущий `hosts/mimir/`) должен объявлять
`nixpkgs.config.allowUnfree = true;` в своём собственном
`configuration.nix`** — см. пример в
`hosts/test-desktop-apps/configuration.nix`. Дублирование по хостам —
осознанный компромисс, а не забытый рефакторинг: единого корневого
`nixosSystem`-враппера, через который проходили бы все хосты, в этом
флейке пока нет.

## 3. Структура репозитория

```
flake.nix                     # входная точка, все inputs (nixpkgs, home-manager, disko, sops-nix, hyprland)
flake.lock                    # зафиксированные версии — гарантия воспроизводимости
.sops.yaml                    # публичный: какие ключи что шифруют
hosts/
  laptop/
    disk-config.nix           # схема disko для этой машины (можно параметризовать)
    hardware-configuration.nix
    configuration.nix         # хост-специфичные настройки (имя, сеть, доп. железо)
secrets/
  secrets.yaml                # зашифровано sops, безопасно коммитить
modules/
  nixos/
    boot.nix                  # systemd-boot / lanzaboote
    luks.nix
    hyprland.nix
    virtualisation.nix
    networking.nix
    users.nix
    packages/
      agent-sandbox.nix       # Nix-образ podman для песочницы AI-агентов (mise, claude-code, opencode, chromium) — см. п.9
  home/
    hyprland/                 # конфиги Hyprland, hyprlock, hypridle, hyprpaper
    waybar-or-quickshell/
    tmux.nix
    neovim.nix
    apps.nix                  # весь список GUI-софта
    shell.nix                 # zsh/bash, алиасы, git config
Makefile                      # test-vm, test-disko, dry-build, deploy
bin/
  agent-sandbox                # обёртка над podman run для песочницы AI-агентов (см. п.9)
CLAUDE.md                     # инструкции для агента
README.md                     # в т.ч. как подключать IDE к проекту, запущенному в песочнице
```

Всё, кроме `secrets/secrets.yaml`, можно свободно отдавать другому человеку —
без расшифровки секреты бесполезны, а без своего `secrets.yaml` система
просто соберётся без частей, зависящих от секретов (SSH-ключ и т.п.).

**Статус реализации этой структуры:** `boot.nix`/`disko-luks-btrfs.nix`/
`secure-boot.nix`/`secrets.nix`/`desktop-apps.nix` реализованы (см. §4-§6,
README); home-manager подключён как инфраструктура без дотфайлов (см.
README, раздел «home-manager»); `hosts/mimir/` существует как skeleton
(см. §4). `modules/home/*`, `hyprland.nix`, `Makefile` — всё ещё
аспирационная часть этой структуры, не построены.

## 4. Разметка диска и загрузка

Реализовано и эмпирически проверено (VM-тестом, не только eval'ом):
`modules/nixos/disko-luks-btrfs.nix` (параметризованный disko-модуль,
`{ device, swapSize ? "34G" }`) + `modules/nixos/boot.nix`
(systemd-boot + systemd-initrd). `hosts/mimir/` (реальная целевая машина)
существует как skeleton (`disk-config.nix` + `configuration.nix`, см.
`docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md`) — не
зарегистрирован в `flake.nix` и не собирается без реального
`hardware-configuration.nix`; проверка идёт через одноразовый VM-хост
`hosts/test-disko-luks/`
(`device = "/dev/vda"`) и `checks.<system>.disko-luks-btrfs` в
`flake.nix` (disko-тест на настоящем виртуальном диске через
`disko.lib.testLib.makeDiskoTest`). Полная архитектура и её обоснование —
`docs/superpowers/specs/2026-08-08-disk-boot-foundation-design.md`.

- GPT → ESP (1024M, `vfat`, `/boot`, не зашифрован — иначе прошивке
  UEFI нечем будет прочитать загрузчик до LUKS-разблокировки) →
  **два LUKS2-контейнера**, не один:
  - `cryptroot` — весь оставшийся диск, внутри `btrfs` с subvolumes
    `/root` → `/`, `/home` → `/home`, `/nix` → `/nix`
    (`compress=zstd`, `noatime`).
  - `cryptswap` — отдельный раздел фиксированного размера (`swapSize`,
    на реальной машине ожидается ~34G под объём RAM), внутри —
    `content.type = "swap"` с disko-флагом `resumeDevice = true`.
- **Почему swap не subvolume-своп-файл внутри `cryptroot`, а отдельный
  LUKS-контейнер:** resume-из-hibernate через btrfs-swapfile при
  включённом `boot.initrd.systemd.enable` имеет задокументированную
  историю поломок (nixpkgs issue #213122); отдельный, не-btrfs своп-раздел
  с классическим `resume=` — проверенный временем механизм, прямо
  рекомендованный NixOS wiki для hibernate. Не `randomEncryption` для
  свопа — со случайным ключом hibernate в принципе невозможен: ключ не
  переживает перезагрузку, так что записанный образ гибернации нечем
  расшифровать при следующей загрузке (disko issue #604, NixOS wiki).
- **Второй LUKS-контейнер не должен означать второй пароль при загрузке —
  но это ожидаемое поведение, не проверенное VM-тестом.** По механизму
  initrd-разблокировки NixOS, автоповтор уже введённого пароля на
  следующих `boot.initrd.luks.devices` должен означать, что при
  **одинаковой** парольной фразе у обоих контейнеров загрузка спрашивает
  пароль один раз. Но `checks.disko-luks-btrfs` (см. выше) даёт обоим
  контейнерам `settings.keyFile` — интерактивный ввод пароля там вообще
  не задействован, так что auto-retry-поведение тестом не покрыто. Это
  именованный пробел, который нужно подтвердить на реальной установке
  (см. `README.md`, "Известные ограничения"), а не проверенный факт. При
  реальной установке важно не перепутать и задать оба пароля одинаковыми
  (иначе, по этой же логике, загрузка должна будет спрашивать пароль
  дважды).
- **`/persist` не часть этого дизайна.** `disko-luks-btrfs.nix` создаёт
  только subvolumes `root`/`home`/`nix` под `cryptroot` — никакого
  отдельного `/persist`-subvolume здесь нет и не планировалось в рамках
  disk-boot-foundation. Если он понадобится (например, для
  Postgres/Redis-данных на `mimir`, см. §5.12/README) — решается отдельно
  при реальной установке `mimir`, не в этом раунде.
- `resumeDevice = true` — собственный флаг disko, декларативно
  выставляющий `boot.resumeDevice` на расшифрованное mapper-устройство
  свопа (не на сырой зашифрованный раздел) — то самое звено
  `luks → swap → resumeDevice`, которое в committed-примерах disko и
  публичных конфигах нигде не встречалось вместе и потому было
  наибольшим риском в этом дизайне; VM-тест (`checks.disko-luks-btrfs`)
  подтвердил, что своп реально активен именно на mapper-устройстве и
  `resume=` присутствует в `/proc/cmdline` активированной системы.
- `btrfs` даёт снапшоты и удобный откат всей системы целиком, не только
  Nix-конфига.
- `systemd-boot` — минимум мороки, всё работает "из коробки" на UEFI;
  `boot.initrd.systemd.enable` нужен и для рабочего LUKS-промпта под
  systemd-boot, и (по данным design doc) как initrd, способный
  автоопределять resume-устройство через EFI-переменные на свежих
  версиях NixOS. Отдельного `luks.nix` нет — disko сам регистрирует оба
  LUKS-устройства (`boot.initrd.luks.devices`) из описания в
  `disko-luks-btrfs.nix`.
- `lanzaboote` — Secure Boot со своими ключами поверх LUKS, отдельным
  модулем `modules/nixos/secure-boot.nix`, который хосты с Secure Boot
  импортируют **вместо** `boot.nix`, не вместе с ним: `boot.loader.systemd-boot.enable
  = lib.mkForce false` (lanzaboote заменяет systemd-boot, а не
  надстраивается над ним — этого требует его собственная документация) +
  `boot.lanzaboote.enable = true` с `pkiBundle = "/var/lib/sbctl"`
  (текущий рекомендованный путь, не устаревший `/etc/secureboot`).
  Раз модуль полностью заменяет `boot.nix` на этих хостах, он обязан сам
  повторить и остальные настройки `boot.nix`, а не полагаться на их
  наследование — явно включает `boot.initrd.systemd.enable = true` (нужен
  `disko-luks-btrfs.nix` для LUKS-промпта) и `boot.loader.efi.canTouchEfiVariables
  = true`, плюс `pkgs.sbctl` в `environment.systemPackages` для реального
  enroll'а. (До финального ревью этого плана `secure-boot.nix` полагался
  на то, что `boot.initrd.systemd.enable` окажется `true` через дефолт
  nixpkgs — совпадение, а не гарантия; исправлено.) Единственный
  нетривиальный шаг за пределами Nix — разовый `sbctl create-keys` и
  enroll ключей в UEFI setup при установке (нужен физический доступ к
  машине; этот репозиторий никогда не генерирует и не коммитит ключи);
  дальше загрузка проверяется прозрачно, без дополнительных действий при
  каждом обновлении системы. **Проверено двумя раздельными чеками, не одним
  совмещённым:** чек 1 (`checks.<system>.secure-boot-signing`,
  `nix flake check -L`) — вендоренная копия собственного upstream-теста
  lanzaboote, реальный VM-boot с `bootctl status`, подтвердивший "Secure
  Boot: enabled (user)" именно с тем `boot.initrd.systemd.enable = true`,
  который уже выбран в `boot.nix` под LUKS-промпт; строится через
  systemd-repart-образ, полностью в обход disko. Чек 2
  (`nixosConfigurations.test-secure-boot`, `hosts/test-secure-boot/`,
  `nix flake check --no-build`) — одноразовый хост, эвалящий
  `disko-luks-btrfs.nix` и `secure-boot.nix` вместе, доказывающий только
  отсутствие конфликтов опций между ними, без реальной сборки. **Ни один
  из двух чеков не доказывает, что цепочка подписи Secure Boot и настоящий
  disko/LUKS/btrfs-layout реально работают вместе в одной загрузке** —
  эта комбинация никогда не тестировалась целиком; это именованный,
  принятый пробел (design doc, "Risk profile"), а не подразумеваемое
  покрытие только потому, что оба чека проходят.

## 5. Полный список пакетов по категориям

### 5.1 Базовая система
```
git, curl, wget, htop/btop, ripgrep, fd, fzf, jq, tree, unzip, gnupg, age,
sops, sbctl (Secure Boot), networkmanager, pipewire + wireplumber,
bluez + blueman
```
`blueman` — сознательный выбор, не заменён на более новый
GTK4/libadwaita `overskride`: тот моложе, менее обкатан и есть репорты
зависаний/CPU-нагрузки в связке с типичным Hyprland-shell-тулингом
(end-4/dots-hyprland#922). Blueman покрывает весь функционал BlueZ
(pairing edge cases, file transfer), DE-agnostic, нормально живёт
иконкой в waybar — по принципу "не усложнять" (см. `CLAUDE.md`).

### 5.1.1 Удалённый стол (в обе стороны)

**Реализовано** в `modules/nixos/desktop-apps.nix` (пакеты `wayvnc` +
`remmina`, 2026-08-10) — не только план, headless-VNC-паттерн ниже пока не
проверен на реальном железе (см. README.md, "Известные ограничения" в
секции про desktop-apps).
```
wayvnc     # сервер: подключение К mimir удалённо
remmina    # клиент: подключение С mimir к другим машинам
```
`wayvnc` — стандартный wlroots-нативный VNC-сервер для Hyprland (не
X11-legacy). Важный нюанс: стриминг живого физического вывода
сессии ненадёжен (баги "серый/пустой экран", any1/wayvnc#326) —
рабочий паттерн — headless-виртуальный output:
```bash
hyprctl output create headless VNC-1
hyprctl keyword monitor "VNC-1,1920x1080@60,auto,1"
wayvnc -o VNC-1 0.0.0.0 5900
```
`remmina` — multi-protocol (RDP/VNC/SPICE/SSH/X2Go) клиент, обычное
GTK-приложение, с Wayland работает без нареканий.

### 5.1.2 Телефон ↔ ПК

**Реализовано** в `modules/nixos/desktop-apps.nix` (`programs.kdeconnect.enable
= true;`, 2026-08-10).
```
kdePackages.kdeconnect-kde   # НЕ "kdeconnect" — этот атрибут больше не
                              # резолвится в текущей раскладке kdePackages
```
Уведомления/буфер обмена/передача файлов по Wi-Fi без проводов, работает
вне Plasma (нужен только D-Bus session, включён в NixOS по умолчанию).
`programs.kdeconnect.enable = true` — отдельный NixOS-модуль, сам
открывает нужные TCP/UDP-порты 1714–1764 в firewall (проще, чем руками
через `networking.firewall`). В Hyprland-конфиге нужен
`exec-once = kdeconnectd` (или индикатор) для автозапуска демона;
трей-иконка подхватывается waybar при запущенном демоне.

### 5.2 Hyprland-стек (десктоп)
```
hyprland, xdg-desktop-portal-hyprland,
waybar,
fuzzel,
mako,
hyprlock, hypridle,
grim, slurp, wf-recorder,
hyprpaper,
cliphist, wl-clipboard,
polkit-agent (hyprpolkitagent или polkit-gnome),
qt5/qt6ct + kvantum (для консистентного вида Qt-приложений типа RubyMine/Postman)
```

### 5.3 Терминал / dev-инструменты
```
tmux, tpm, tmux-resurrect, tmux-continuum, vim-tmux-navigator (плагины)
neovim (LazyVim/kickstart.nvim как база)
  ruby-lsp, rubocop, treesitter (ruby/erb/yaml), vim-rails, rspec.nvim/vim-test,
  nvim-dap
kitty — терминальный эмулятор
zsh + starship (промпт) + плагины (автодополнение, подсветка синтаксиса,
  поиск по истории) — конкретный набор/менеджер плагинов подобрать при
  реализации по правилу "искать готовые решения" из CLAUDE.md
direnv + nix-direnv (авто-окружения на проект)
podman (контейнеры для сервисов проекта — см. 5.12 про PostgreSQL/Redis)
mise (менеджер версий ruby/node/etc — версии берутся из .tool-versions
      каждого проекта, не хардкодятся в системном конфиге; тот же
      инструмент используется и внутри песочницы агентов, см. п.9.3)
```

### 5.4 IDE / редакторы

**Реализовано** в `modules/nixos/desktop-apps.nix` (2026-08-10).
```
jetbrains.ruby-mine     # unfree, требует allowUnfree = true
vscode                  # unfree (лицензия MS, телеметрия) — выбран вместо vscodium
```
`jetbrains.ruby-mine`, **не** `jetbrains.rubymine` — атрибут переименован
апстримом (дефис, по аналогии с `jetbrains.rust-rover`), старое имя не
резолвится вообще, даже как алиас/`throw`. Готча при проверке: `nix
search nixpkgs jetbrains.rubymine`/`jetbrains.ruby-mine` показывает пусто
для **обоих** имён, потому что `nix search` не учитывает
`nixpkgs.config.allowUnfree = true` (эта опция применяется только к
реальному `pkgs`-инстансу, а не к собственной hermetic-эвалюации `nix
search`) — пустой результат `nix search` по unfree-пакету ничего не
доказывает про его наличие в nixpkgs, не принимать это за подтверждение,
что пакет исчез. Проверять так:
`NIXPKGS_ALLOW_UNFREE=1 nix eval --impure --expr '(import <nixpkgs> {}).jetbrains.ruby-mine.version'`
(или аналогично через `nix-instantiate --eval`).

### 5.5 AI coding agents
```
claude-code   # пакет уже есть в nixpkgs (см. numtide/llm-agents.nix как альтернативный источник свежих версий)
opencode      # тоже в nixpkgs (pkgs.opencode), open-source, мульти-провайдерный агент
```
Оба — CLI-инструменты. На хосте ставятся как обычные пакеты для разовых
интерактивных задач (ключи/токены — через sops-nix, см. п.7, не хардкодить
в конфиге). Для запуска агента **над конкретным проектом** — не напрямую на
хосте, а через песочницу, см. п.9.

### 5.6 Коммуникация / браузер
```
telegram-desktop
google-chrome           # unfree
firefox                 # + Firefox Sync аккаунт для кук/паролей/закладок
```

### 5.7 API / сеть
```
postman                 # unfree, в nixpkgs есть
```

### 5.8 Прокси-клиент
`nekoray` **архивирован разработчиком в марте 2025**, дальше не развивается.
Выбран **Throne** (`throneproj/Throne`) — прямой продолжатель nekoray, тот
же UI/логика, тот же движок sing-box.

**Реализовано** в `modules/nixos/desktop-apps.nix` (2026-08-10) — и проще,
чем изначально предполагалось в этом плане. На момент реализации Throne
оказался обычным пакетом в nixpkgs (собирается из исходников, не
AppImage/бинарник с GitHub Releases), со своим собственным NixOS-модулем
`programs.throne`, который уже решает неприятные части сам: заворачивает
sing-box-based ядро в нужные capabilities через `setcap` (не требует
полного setuid-root) и настраивает polkit для TUN-mode DNS, чтобы не
переспрашивать пароль на каждое включение. Ничего из
"AppImage/autoPatchelfHook/nix-ld своя derivation", описанного здесь
раньше, делать не пришлось — держать в голове как устаревшую версию
плана, если попадётся в истории git. Используется:
```nix
programs.throne = {
  enable = true;
  tunMode.enable = true;
};
```
Конфиг (сервер/ключ VLESS-Reality и т.п.) — секрет, хранится в Bitwarden,
не в sops-nix (см. §6, §7 — переехало из git-репозитория в облако вместе
с SSH-ключами).

### 5.9 Виртуализация
```
virtualisation.libvirtd.enable = true;
programs.virt-manager.enable = true;
qemu, OVMF (UEFI-прошивка для гостевых VM), spice-vdagent (буфер обмена
хост↔гостевая VM)
```
Пользователя добавить в группы `libvirtd`, `kvm`.

### 5.10 Медиа
```
mpv                     # плюс mpv-конфиг под удобные хоткеи (yt-dlp интеграция)
yt-dlp                  # для mpv, чтобы играть ссылки с YouTube напрямую
pavucontrol             # GUI-микшер громкости
playerctl               # медиаклавиши через Waybar/Hyprland-бинды
```

### 5.11 Утилита перевода по хоткею (Crow Translate)

Готовое, поддерживаемое приложение вместо самописного скрипта —
[Crow Translate](https://github.com/crow-translate/crow-translate)
(`crow-translate` в nixpkgs, несколько бэкендов: Google/Yandex/Bing/
LibreTranslate, есть TTS). Решение сменилось с исходного варианта
(плавающий терминал + свой скрипт на `translate-shell`) на это — меньше
своего кода для поддержки, и перевод текущего выделения текста работает
сразу, без copy-paste в терминал.

```
crow-translate   # готовый переводчик, есть в nixpkgs
```

**Хоткей.** Wayland не даёт регистрировать глобальные хоткеи напрямую —
поэтому переводом управляет сам Hyprland-бинд, а не хоткей внутри
приложения (в отличие от X11-версий подобных утилит). Приложение
запускается в фоне при старте сессии, чтобы его D-Bus-сервис был готов к
моменту первого нажатия хоткея. Конфиг написан сразу в Lua
(`hyprland.lua`), а не в классическом hyprlang `.conf` — начиная с
Hyprland 0.55 (вышел 2026-05-09) hyprlang официально deprecated в пользу
Lua-конфига и будет полностью убран через 1-2 релиза; поскольку в этом
репозитории ещё нет ни одного Hyprland-конфига (модуль не собран, см.
§3/§5.2), синхронизироваться не с чем, и есть смысл сразу писать в
формате, который не устареет:

```lua
local mainMod = "SUPER"

hl.on("hyprland.start", function()
  hl.exec_cmd("crow-translate")
end)

hl.bind(
  mainMod .. " + T",
  hl.dsp.exec_cmd(
    "gdbus call --session --dest io.crow_translate.CrowTranslate "
      .. "--object-path /io/crow_translate/CrowTranslate/MainWindow "
      .. "--method io.crow_translate.CrowTranslate.MainWindow.translateSelection"
  )
)
```

По хоткею переводится текущее выделение текста (`translateSelection` —
официальный D-Bus-метод приложения, задокументированный именно как
интеграционная точка для компоузеров без глобальных хоткеев). Компромисс
по сравнению с исходной задумкой: показывается попап с текущим переводом,
а не скролбэк-история всех переводов в одном окне — принято осознанно
ради меньшего количества своего кода.

### 5.12 PostgreSQL и Redis (декларативные контейнеры)

Не системные сервисы и не ручной `docker-compose` на уровне проекта, а
декларативные контейнеры через встроенную NixOS-опцию поверх podman —
одинаковый паттерн для обоих:

```nix
virtualisation.oci-containers.containers = {
  postgres = {
    # Полное имя (docker.io/library/...), не короткое "postgres:16": NixOS-
    # сборка podman не задаёт unqualified-search registries в
    # /etc/containers/registries.conf (в отличие от Docker, у которого
    # Docker Hub — дефолт), так что короткое имя падает при старте
    # контейнера с "short-name ... did not resolve to an alias" — найдено
    # реальной build-vm верификацией (docs/superpowers/plans/
    # 2026-08-04-postgres-redis.md, Task 3).
    image = "docker.io/library/postgres:16";
    # Без пароля (POSTGRES_HOST_AUTH_METHOD=trust, официальный no-auth
    # режим образа) — БД доступна только с localhost на однопользовательской
    # машине, у кого есть шелл — у того и так есть доступ к диску целиком,
    # так что пароль на loopback-подключение не даёт реальной защиты, только
    # лишний sops/age bootstrap. Решение явное, не забытый TODO.
    environment = { POSTGRES_HOST_AUTH_METHOD = "trust"; };
    ports = [ "127.0.0.1:5432:5432" ];
    volumes = [ "/persist/postgres:/var/lib/postgresql/data" ];
  };
  redis = {
    # Fully-qualified for the same reason as postgres above.
    image = "docker.io/library/redis:7";
    ports = [ "127.0.0.1:6379:6379" ];
    volumes = [ "/persist/redis:/data" ];
    cmd = [ "redis-server" "--save" "60" "1" ]; # персистентность на диск, не только in-memory
  };
};
```

Конфиг живёт в `.nix`-модуле как всё остальное, поднимается вместе с
системой (или по требованию, если не добавлять `wantedBy` в юнит) — не
нужно ничего ставить/поднимать вручную на уровне каждого Rails-проекта.
Оба сервиса общие для всех проектов на машине (один Postgres/Redis, разные
БД/namespaces внутри) — так же, как это обычно организовано при локальной
разработке нескольких Rails-приложений на одной машине.

## 6. Секреты (sops-nix) — роль сузилась в пользу Bitwarden

**Обновление:** SSH-ключи и конфиг прокси (Throne, VLESS-Reality) переехали
в Bitwarden (см. §7) — не sops-nix. Причина: то, что и так живёт в облаке
(Bitwarden уже используется под пароли/TOTP), не нужно параллельно
шифровать ещё и в git через sops — меньше механизмов для одной и той же
задачи. Bitwarden сейчас — коммерческий сервис, но с явным намерением
перейти на opensource-альтернативу позже (Vaultwarden — self-hosted,
API-совместим с Bitwarden-клиентами, миграция минимальна).

sops-nix пока не убран из плана целиком — остаётся под GPG-ключ (см. §7)
и как задел под секреты, которые в принципе не могут жить в облачном
менеджере паролей (например то, что нужно машине **до** сетевого
логина/разблокировки — сам sops-nix для таких случаев и существовал
изначально). Если и GPG-ключ в итоге тоже переедет в Bitwarden — sops-nix
в этом плане может оказаться не нужен вообще; пересмотреть при реализации
модуля секретов, не раньше.

**Реализовано** (`modules/nixos/secrets.nix`): минимальная обвязка
sops-nix ровно под один секрет — GPG-ключ.

```nix
sops.defaultSopsFile = ../../secrets/secrets.yaml;
sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
sops.secrets."gpg_key" = { };
# результат доступен по пути config.sops.secrets."gpg_key".path
```

- `secrets/secrets.yaml` — зашифрован age-ключом, привязанным к SSH-хост-ключу
  машины (`ssh-to-age`, через `sops.age.sshKeyPaths`).
- `.sops.yaml` в корне — публичный, описывает **кем** шифруется каждый файл
  (по machine/host), сам по себе секретов не содержит.
- Для другого человека: у него будет **свой** `secrets.yaml` под **своим**
  age-ключом — система расшифровки полностью параллельна, конфликтов нет.
- Если секрета нет — соответствующий модуль просто не активируется,
  остальная система собирается нормально.
- `config.sops.secrets."gpg_key".path` пока без потребителя — подключение
  к git commit signing понадобится home-manager/user-слой, которого в этом
  флейке ещё нет; отдельная будущая задача.

Проверка — двумя раздельными чеками, тот же паттерн, что у disko/Secure
Boot (§4):
- `nix flake check --no-build` — быстрая eval-only проверка, что
  `secrets.nix` эвалится на реальном host-closure без конфликтов опций
  (`nixosConfigurations.test-secrets`, `hosts/test-secrets/` — одноразовый
  хост только для этой цели, не `hosts/mimir/`).
- `nix flake check -L` — реальный VM-тест, `checks.<system>.secrets-decryption`
  (`modules/nixos/secrets-test/`): вендоренная, адаптированная копия
  апстримного теста sops-nix `age-ssh-keys` (ed25519 SSH-хост-ключ →
  `ssh-to-age` → age identity → реальная расшифровка sops-файла во время
  активации системы). **Важно, откуда взялся именно `age-ssh-keys`, а не
  `ssh-keys`:** исходный план (см. design doc) указывал на апстримный тест
  `ssh-keys` как на пример настоящей `ssh-to-age`-конверсии — при проверке
  руками перед вендорингом выяснилось, что это неверно: `ssh-to-age`
  поддерживает только ed25519-ключи, а `ssh-keys` использует RSA-хост-ключ,
  который sops-nix расшифровывает через `sops.gnupg.sshKeyPaths`
  (ssh-to-pgp) — совсем другой механизм, не тот, что использует
  `sops.age.sshKeyPaths` в реальном `secrets.nix` этого репозитория.
  Провендорить `ssh-keys` значило бы получить тест, который зелёный, но
  доказывает не тот механизм. Вместо этого провендорен `age-ssh-keys`
  (ed25519) — он действительно проходит через `ssh-to-age` и подтверждает
  тот же путь расшифровки, что настроен в реальном модуле.

### Известные ограничения

- **`secrets/secrets.yaml`/`.sops.yaml` в этом репозитории пока вообще не
  существуют.** Этот раунд работы не создаёт реального получателя — для
  `ssh-to-age` нужен реальный SSH-хост-ключ реальной машины, а `mimir` ещё
  не установлен физически (хотя `hosts/mimir/configuration.nix` уже
  импортирует `secrets.nix` как skeleton — см.
  `docs/superpowers/specs/2026-08-11-mimir-host-skeleton-design.md`).
  Создавать `secrets/secrets.yaml`, зашифрованный "в никуда" (без единого
  настоящего получателя), было бы пустым жестом — оба файла остаются
  реально-install-time шагом.
- **Вендоренный тест доказывает механизм на фиксированном тестовом ключе,
  не на ключе реальной машины.** `age-ssh-keys` использует чужой, заранее
  известный, опубликованный SSH-ключ как стенд-ин — тот же механизм
  (`ssh-to-age` из ed25519 host key), но не то же самое, что "проверено на
  `mimir`". Реальный ключ `mimir` появится только после установки.
- **Реальная установка** — по аналогии с disko/Secure Boot, это отдельный,
  явно запрашиваемый шаг: установить `mimir` по-настоящему → получить его
  реальный SSH-хост-ключ → сконвертировать в age через `ssh-to-age` →
  добавить как получателя в `.sops.yaml` → `sops secrets/secrets.yaml`,
  чтобы вписать туда настоящий GPG-ключ → закоммитить → передеплоить.

## 7. Пароли и личные данные (вне git, отдельные сервисы)

| Категория | Инструмент |
|---|---|
| Пароли, TOTP, лицензии, secure notes | **Bitwarden** (бесплатный тариф достаточен; план — перейти на opensource, см. §6) |
| Куки, история, закладки, сохранённые пароли сайтов | **Firefox Sync** |
| SSH-ключи | **Bitwarden** (было: sops-nix — переехало, см. §6) |
| Конфиг прокси (Throne, п.5.8) | сервер/ключ VLESS-Reality — **Bitwarden** (было: sops-nix — переехало, см. §6) |
| GPG-ключ | пока sops-секрет (для подписи git-коммитов) — кандидат на переезд в Bitwarden вместе с остальным, не решено |
| Wi-Fi пароли | NetworkManager-профили, можно экспортировать в Bitwarden как backup |
| Сессия Telegram | **не синхронизируется** между машинами и не хранится в git/sops — логин заново по QR/телефону на каждой новой машине. Утечка репозитория/age-ключа не даёт доступа к аккаунту |

## 8. Порядок разворачивания на новой машине

```bash
# 1. Загрузиться с NixOS install ISO (или Hyprland-минимал ISO)
# 2. Клонировать репозиторий
git clone <repo> && cd <repo>

# 3. Разметить диск (LUKS + btrfs) декларативно
nix run github:nix-community/disko -- --mode disko ./hosts/laptop/disk-config.nix

# 4. Установить систему
nixos-install --flake .#laptop

# 5. Перезагрузка, ввод пароля LUKS
reboot

# 6. Первый вход — логин в Bitwarden + Firefox Sync (2-3 минуты)
```

## 9. Безопасный запуск AI-агентов (sandboxing)

### 9.1 Зачем

`claude-code`/`opencode` (п.5.5), запущенные напрямую на хосте, имеют полный
доступ к файловой системе, сети и секретам пользователя. Риск — не столько
злой умысел, сколько ошибка/prompt injection: агент по ошибке трогает файлы
не в рамках проекта, читает SSH-ключи/токены других сервисов, выполняет
деструктивную команду. Цель — не дать агенту выйти за пределы текущего
проекта, а не защититься от направленной атаки уровня kernel exploit
(для такой угрозы потребовалась бы аппаратная VM-изоляция — избыточно
для этого сценария).

### 9.2 Архитектура: rootless Podman, один процесс = один контейнер

- Каждый запуск агента — короткоживущий rootless-контейнер
  (`podman run --rm`), а не постоянная VM: изоляция на уровне ядра
  (user/mount/network namespaces) достаточна против случайного повреждения
  системы и утечки за пределы проекта, при этом старт < 1 сек и накладные
  расходы — десятки МБ, а не гигабайты ОЗУ на диск-образ.
- В контейнер монтируется **только директория проекта**
  (`-v <project-dir>:/workspace`), не `$HOME` целиком — секреты хоста,
  SSH-ключи, `secrets.yaml` в расшифрованном виде и другие проекты никогда
  не попадают внутрь.
- `--userns=keep-id` — файлы, изменённые агентом в `/workspace`, на хосте
  остаются с правами обычного пользователя, а не root контейнера.
- Сеть — дефолтная (`--network=bridge`, полный NAT наружу), без
  allowlist-прокси: агенту нужен произвольный интернет (доступ к API,
  пакетным реестрам, документации), и намеренно не ограничиваем его —
  осознанный трейд-офф ради простоты. Граница защиты — файловая система и
  системные секреты хоста, не сеть.
- Несколько проектов/агентов одновременно — просто несколько параллельных
  вызовов обёртки с разными `<project-dir>`; коллизий портов/состояния
  между ними нет, поломка одного контейнера не задевает другой. Если
  агенты запускаются последовательно (один проект за раз), архитектура
  не меняется — просто пересоздаётся контейнер под текущий проект.

### 9.3 Образ (`modules/nixos/packages/agent-sandbox.nix`)

Собирается декларативно через `pkgs.dockerTools.buildLayeredImage` (не
`buildImage` — послойная сборка даёт более полезное кэширование: смена
одного часто обновляемого пакета вроде `claude-code` не пересобирает/не
перезаливает слой с самым тяжёлым зависимым — chromium). Содержит:

```
mise                      # менеджер версий языков — НЕ хардкодим ruby/node в образе
git, curl, ripgrep и т.п. # базовые CLI
claude-code, opencode     # сами агенты
chromium (+ Wayland/Mesa) # для GUI-браузера, см. 9.5
```

Версии ruby/node/etc агент получает через `mise install`, читая
`.tool-versions`/`mise.toml` **из самого проекта** при первом запуске —
образ остаётся общим для всех проектов, не пересобирается под каждый стек.

### 9.4 Обёртка (`bin/agent-sandbox <project-dir> [--gui]`)

```bash
podman run --rm -it \
  --userns=keep-id \
  -v <project-dir>:/workspace \
  -v agent-mise:/home/agent/.local/share/mise \        # общий кэш версий рантаймов между проектами
  -v agent-cache-<project-hash>:/home/agent/.cache \    # индекс/история сессии агента, per-project
  --network=bridge \
  [--device /dev/dri -v "$XDG_RUNTIME_DIR/wayland-0":... -e WAYLAND_DISPLAY]  # только с --gui
  agent-sandbox:latest
```

Персистентные volumes переживают пересоздание контейнера: `agent-mise` —
общий (не тянуть по новой версии ruby на каждый запуск), `agent-cache-*` —
свой на проект (индекс кодовой базы, история сессии claude-code/opencode).

### 9.5 IDE и GUI-браузер

- **IDE не требует remote-forwarding.** Раз в контейнер монтируется та же
  директория проекта (bind-mount, не копия), RubyMine/VSCode на хосте
  открывают `<project-dir>` как обычно и работают с теми же файлами на
  диске — изолируется процесс выполнения агента, а не файлы для
  редактирования. Задокументировать это в README как основной способ
  работы.
- **Headless-браузер** (Playwright/Puppeteer для тестов/дебага) работает
  внутри контейнера без доп. настройки — результат агент прикладывает как
  скриншоты/логи.
- **Видимое окно браузера** на десктопе — флаг `--gui`: проброс Wayland-
  сокета (`$XDG_RUNTIME_DIR/wayland-0`) и `/dev/dri` для GPU. Настраивается
  один раз в обёртке, дальше прозрачно для пользователя.
- Если зависимости проекта должны выполняться именно в контейнерном
  окружении (не просто редактирование файлов) — опционально можно
  использовать VSCode Dev Containers / JetBrains Gateway; в базовый план
  это не входит, описать как opt-in в README.

### 9.6 Явно принятые ограничения

- Изоляция на уровне namespaces, не аппаратная VM — не защищает от
  теоретического kernel-level побега из контейнера.
- Сеть не ограничена — не защищает от эксфильтрации данных проекта через
  интернет, если агент к этому приведён (prompt injection и т.п.).
  Осознанно принято ради простоты и функциональности (агенту нужен
  реальный доступ в сеть для дебага/браузера).
- Общий volume `agent-mise` (см. §9.4) — канал распространения между
  проектами: он один на все контейнеры (в отличие от `agent-cache-*`,
  который per-project), поэтому скомпрометированный/сломанный агент в
  проекте A может подменить установленный туда рантайм или shim (например,
  бинарник `ruby`), и он затем выполнится в контейнере проекта B при
  следующем запуске. Частично противоречит заявленной цели "blast-radius
  containment между проектами", но осознанно принято по той же логике,
  что и открытая сеть выше — модель угроз здесь "непреднамеренные ошибки
  агента", не целенаправленная атака, и переустанавливать рантайм на
  каждый проект ради этого не стоит. Если модель угроз изменится — сделать
  `agent-mise` per-project (ценой потери кэша между проектами).
- Защищает конкретно от: порчи/утечки файлов и секретов **вне** текущего
  проекта, случайных деструктивных команд, затрагивающих систему хоста.
