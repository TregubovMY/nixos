# Тулинг для notebooklm-py + связанного Obsidian-вольта, см.
# `docs/superpowers/user/NixOS setup.md` (написан 2026-08-20 по итогам
# реальной установки на текущей, не-NixOS машине) — пункты 3-4. Отдельный
# модуль, а не часть desktop-apps.nix: это не просто список пакетов, а
# пакет + системные env-переменные, обвязывающие конкретный воркэраунд
# (Playwright/Chromium), и логически один связанный кусок функциональности
# (yt-dlp сам по себе уже в desktop-apps.nix и сюда не входит).
#
# notebooklm-py в nixpkgs нет (чистый PyPI-пакет) — ставится вручную через
# `uv tool install "notebooklm-py[browser]"` (uv изолирует venv так же, как
# pipx, и не ломается об неизменяемый /nix/store в отличие от голого
# `pip install --user`). uv здесь — только системная зависимость для этого
# шага, сама установка notebooklm-py не декларативна и делается руками при
# реальной установке (см. README).
#
# Playwright, которого тянет notebooklm-py, по умолчанию скачивает свой
# Chromium универсальной Linux-сборкой (ждёт FHS-пути вроде /lib64,
# которых на NixOS нет) — такой бинарник просто не запустится. nixpkgs
# решает это готовым патченным пакетом `playwright-driver.browsers`;
# PLAYWRIGHT_BROWSERS_PATH указывает Playwright на него, а
# PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 не даёт Playwright параллельно тянуть
# несовместимый билд поверх при `uv tool install`/первом запуске.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    uv
    playwright-driver.browsers
  ];

  environment.variables = {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  };
}
