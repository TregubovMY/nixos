# Трекер времени: ActivityWatch (aw-server-rust) + awatcher, автозапуск с сессией.
#
# Почему этот модуль появился (2026-11-02): `awatcher` стоял в
# modules/nixos/desktop-apps.nix с 2026-08-13, но ничего его не запускало, а
# сам он только ОТПРАВЛЯЕТ события на сервер ActivityWatch (в этой версии,
# 0.4.0, встроенного сервера нет — проверено: `awatcher --help` знает лишь
# --host/--port/--no-server). Без сервера на 127.0.0.1:5600 трекер "не
# наблюдался": ни процесса, ни веб-интерфейса.
#
# - aw-server (пакет aw-server-rust): хранит данные в ~/.local/share/activitywatch,
#   веб-интерфейс http://localhost:5600 (отчёты по приложениям/окнам, AFK).
# - awatcher, а не aw-watcher-window-wayland: см. комментарий в desktop-apps.nix
#   (лучше поддерживается, Hyprland через wlr foreign-toplevel + ext-idle-notify).
# Оба сервиса привязаны к graphical-session.target (нужен Wayland-сокет).
{ pkgs, ... }:
{
  systemd.user.services.aw-server = {
    Unit = {
      Description = "ActivityWatch server (localhost:5600)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.aw-server-rust}/bin/aw-server";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.awatcher = {
    Unit = {
      Description = "ActivityWatch window/AFK watcher (Wayland)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" "aw-server.service" ];
      Wants = [ "aw-server.service" ];
    };
    Service = {
      ExecStart = "${pkgs.awatcher}/bin/awatcher";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
