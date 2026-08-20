---
type: meta
tags: meta
---
# Что настроить на новой NixOS-машине, чтобы вольт и весь тулинг заработали

Написано 2026-08-20, по итогам того, что реально ставилось на текущей (Ubuntu) машине в этой сессии. Не готовый flake, а чек-лист + фрагменты конфига — подставь под свой способ (обычный `configuration.nix`, flakes, home-manager — что у тебя используется).

## 1. Что НЕ требует отдельной настройки
Все community-плагины Obsidian (QuickAdd, Templater, Dataview, Yanki, Homepage, obsidian-git и т.д.) физически лежат в `.obsidian/plugins/` **внутри вольта** — они приедут сами вместе с `git clone`/`git pull` вольта. Отдельно их ставить/настраивать на новой машине не нужно — только сам Obsidian и его первый запуск с этим вольтом.

## 2. Базовые пакеты
```nix
environment.systemPackages = with pkgs; [
  obsidian     # сам Obsidian, есть в nixpkgs
  git
  anki         # для повторения карточек через Yanki (см. Vault guide, пункт 4)
];
```
На NixOS Obsidian (Electron) иногда требует `--unsupported-gpu` при проблемах с рендером на некоторых видеокартах — если после установки чёрный экран, добавь флаг в ярлык запуска.

## 3. Git + синк вольта (GitHub, тот же репозиторий)
```bash
ssh-keygen -t ed25519 -C "obsidian-<hostname>"
cat ~/.ssh/id_ed25519.pub   # добавить в GitHub → Settings → SSH keys
git config --global user.name  "<как на текущей машине>"
git config --global user.email "temprnds@gmail.com"
git clone git@github.com:TregubovMY/Obsidian-Athena.git ~/Obsidian/Obsidian-Athena
```
Дальше просто открой эту папку как вольт в Obsidian — `obsidian-git` внутри неё уже настроен (автокоммит каждые 10 мин, автопуш каждые 30).

## 4. yt-dlp + notebooklm-py — тут NixOS отличается от обычного pip
На текущей (Ubuntu) машине я поставил их через `pip3 install --user`. **На NixOS так делать не стоит** — pip плохо уживается с неизменяемым `/nix/store`, пакет может не подхватиться или потеряться при обновлении профиля.

**yt-dlp** — есть прямо в nixpkgs, просто пакет:
```nix
environment.systemPackages = with pkgs; [ yt-dlp ];
```

**notebooklm-py** — в nixpkgs его нет (это чисто PyPI-пакет), поэтому нужен `pipx`/`uv` — они изолируют venv и на NixOS работают нормально, в отличие от голого `pip install --user`:
```nix
environment.systemPackages = with pkgs; [ uv ];
```
```bash
uv tool install "notebooklm-py[browser]"
```

**Плейwright/Chromium — главный подвох NixOS.** `notebooklm-py` тянет Playwright, а тот скачивает свой Chromium универсальной сборкой под обычный Linux (ждёт стандартные пути вроде `/lib64`, которых на NixOS нет) — просто так скачанный бинарник не запустится. В nixpkgs под это есть готовый пакет с патченными библиотеками:
```nix
environment.systemPackages = with pkgs; [ playwright-driver.browsers ];
environment.variables = {
  PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
  PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1"; # не давать Playwright тянуть несовместимый билд поверх
};
```
После этого `notebooklm login` и `notebooklm skill install` — как на текущей машине (см. `Vault guide.md`, пункт 6). Вход в гугл-аккаунт при первом запуске всё равно нужен руками, это не автоматизируется.

## 5. Чего тут нет и не должно быть
- **ReadEra / Moon+ Reader** — Android-приложения, к NixOS-десктопу не относятся (читаешь на телефоне).
- **Syncthing** — не используем, синк вольта идёт через git (см. п.3).
- **AnkiConnect** — это аддон *внутри* Anki (код `2055492159` через Tools → Add-ons → Get Add-ons), не системный пакет, ставится один раз после установки Anki из п.2.
