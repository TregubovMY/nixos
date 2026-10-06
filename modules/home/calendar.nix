# DankCalendar: Google (and Microsoft/CalDAV) calendars with event
# reminders as desktop notifications, shown inside the DMS panel too (DMS's
# "dankcal" calendar backend connects to its socket). Requested 2026-10-06
# ("уведомления из гугл календаря"). Package and module come from the
# dank-calendar flake input -- see flake.nix for why not nixpkgs yet.
#
# Chosen over the khal+vdirsyncer route DMS also supports: vdirsyncer's
# Google sync needs your own Google Cloud OAuth client, and khal has no
# reminder notifications at all. DankCalendar ships an upstream OAuth client
# (README, "OAuth credentials"), so `dcal account add google` just opens the
# browser, and it notifies on its own.
#
# One-time, after first login: `dcal account add google` (or the account
# page in its UI). Tokens go to the system keyring -- gnome-keyring,
# unlocked at login, see modules/nixos/greetd.nix.
#
# `settings` (ui-settings.json) deliberately left unset: the module would
# make that file a read-only Nix symlink, and the app's own settings page
# writes it. Reminder defaults are the app's.
{ ... }:
{
  programs.dank-calendar = {
    enable = true;
    # dcal as a systemd user service bound to the graphical session: the
    # daemon must run for syncing and reminders, not only while its window
    # is open. Started --hidden (tray only).
    systemd.enable = true;
  };
}
