# Real Hyprland desktop config -- now built on DankMaterialShell (DMS), a
# Quickshell-based desktop shell, per explicit user request after
# hand-styled waybar/mako/hyprlock iterations were repeatedly flagged as
# "выглядит плохо/пусто". DMS replaces waybar, mako, hyprlock, hypridle,
# fuzzel, and the polkit agent as one integrated system (confirmed
# against DankMaterialShell's own README: "It replaces waybar, swaylock,
# swayidle, mako, fuzzel, polkit, and everything else you'd normally
# stitch together") -- see docs/superpowers/plans/tingly-doodling-phoenix.md
# for the fuller discussion (why not end-4/dots-hyprland directly: that
# repo is an Arch/AUR-specific installer with configs for apps we don't
# use, not portable to NixOS; DMS ships real nixosModules/homeModules
# under distro/nix/, fetched and read in full before wiring this in).
#
# IMPORTANT — deliberately NOT using home-manager's own
# wayland.windowManager.hyprland module at all, even just for its
# systemd.enable session-target wiring. Checked live: that module claims
# xdg.configFile."hypr/hyprland.conf"/".lua" as a home-manager-managed
# (read-only, Nix-store-symlinked) file the moment `enable = true` is
# set, REGARDLESS of whether settings/extraConfig are populated -- its
# own `config` block sets xdg.configFile unconditionally under
# `mkIf cfg.enable`. DMS's own `dms setup` CLI (interactive, run once
# after first login) needs to WRITE ~/.config/hypr/hyprland.lua and
# ~/.config/hypr/dms/*.lua (colors/outputs/layout/cursor/binds/
# binds-user/windowrules) itself and keep them DMS-managed from then on
# (confirmed via DMS's own docs/Hyprland_Lua_Migration.md, fetched and
# read in full) -- a Nix-owned symlink there would block that outright.
# So this repo leaves ~/.config/hypr/ entirely unmanaged by Nix/home-
# manager, fully owned by DMS. Same "genuinely impure, accepted"
# category as LazyVim's lazy.nvim bootstrap in modules/home/neovim.nix,
# one step further (not even a Nix-vendored starting point -- DMS
# bootstraps the whole directory from nothing via `dms setup`).
#
# Correction, found live: `dms setup` itself asks "Use systemd for
# session management?" and defaults to/recommends Yes -- when answered
# Yes (as it was here), the config it deploys expects a real `dms.service`
# systemd user unit to exist and starts DMS through it, not via a plain
# exec-once. Originally left programs.dank-material-shell.systemd.enable
# off on the theory that DMS would launch itself directly with no
# systemd involved -- wrong for the systemd-managed path `dms setup`
# actually offers and this session used. Symptom was a real blank
# Hyprland session (bare cursor, DMS never appeared) because Hyprland's
# generated config tried to start a systemd unit that didn't exist.
# Enabled below to match.
#
# Second correction, found live after the above fix still produced a
# blank session on the NEXT boot: enabling programs.dank-material-shell's
# own systemd service isn't enough by itself. `dms setup`'s generated
# ~/.config/hypr/hyprland.lua execs
# `systemctl --user start hyprland-session.target` on startup (confirmed
# by grepping the actual deployed file) -- the exact target
# wayland.windowManager.hyprland's own systemd.enable used to create
# (back when this module still used that module, before the
# xdg.configFile conflict above). Removing that module also removed the
# target definition, but DMS's own generated config still assumes it
# exists -- `systemctl --user start` on a target with no unit file just
# fails silently, so dms.service (WantedBy = graphical-session.target,
# the default) never gets pulled in. Fix: recreate ONLY the target unit
# itself here (not the whole conflicting module) -- BindsTo
# graphical-session.target, same shape
# wayland.windowManager.hyprland's own module used internally, so
# DMS's exec-once line has something real to start.
{ config, lib, pkgs, ... }:
{
  # quickshell itself comes from home-manager's own programs.quickshell
  # module (confirmed present at this repo's pinned home-manager rev) --
  # programs.dank-material-shell's own home.nix sets
  # programs.quickshell.enable = true automatically, so it isn't
  # separately enabled here.
  programs.dank-material-shell = {
    enable = true;
    systemd.enable = true;
  };

  systemd.user.targets.hyprland-session = {
    Unit = {
      Description = "Hyprland compositor session";
      BindsTo = [ "graphical-session.target" ];
      Wants = [ "graphical-session-pre.target" ];
      After = [ "graphical-session-pre.target" ];
    };
  };

  # Requested live: a real cursor theme instead of the default GTK
  # fallback ("уродски"), and (2026-10-06) applied automatically instead
  # of via DMS Settings → Cursor. Two halves:
  # - home.pointerCursor with only dotIcons (its default): writes
  #   ~/.icons/default/index.theme inheriting Bibata, the XCursor
  #   fallback every toolkit and XWayland app reads, plus XCURSOR_* in the
  #   session vars. gtk.enable stays OFF on purpose: it would make
  #   ~/.config/gtk-3.0/settings.ini a read-only Nix symlink, and DMS
  #   writes that file itself (quickshell/Services/IconThemeService.qml).
  #   hyprcursor/sway/x11 parts need modules this repo doesn't use.
  # - Hyprland's own cursor: the NIXOS-MANAGED CURSOR block appended to
  #   hyprland.lua below, mirroring what DMS's cursor settings would
  #   write to dms/cursor.lua (hl.env + `hyprctl setcursor`, DMS
  #   quickshell/Services/HyprlandService.qml). Appended after DMS's own
  #   includes, so it wins over a theme picked in DMS Settings.
  # Bibata ships XCursor themes (no hyprcursor format); Hyprland falls
  # back to XCursor when HYPRCURSOR_THEME isn't a hyprcursor theme.
  home.pointerCursor = {
    # Explicit: home-manager deprecated enabling cursor config merely by
    # setting home.pointerCursor (evaluation warning seen in the VM).
    enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
    size = 24;
    gtk.enable = false;
  };
  # grimblast (hyprwm/contrib, packaged in nixpkgs) -- DMS's own
  # screenshot IPC target (`dms ipc call niri screenshot*`) is niri-only
  # per DMS's own IPC docs, doesn't work under Hyprland. grimblast is
  # the Hyprland-wiki-recommended tool for this instead (Screenshots &
  # Recording page), so no custom derivation needed, just wire up binds
  # below the same way as the rest of this file's activation script.
  #
  # Hotkey translation (system-plan.md §5.11) -- now Dialect, see
  # translate-selection below; history of the Crow Translate version:
  # crow-translate: regression found live while rewriting README (2026-08-18)
  # -- system-plan.md §5.11's hotkey-translate feature (repo root
  # `hypr/quick-translate.lua`, `require("quick-translate")`) was written
  # against the pre-DMS, hand-managed ~/.config/hypr/hyprland.lua and
  # silently stopped being wired up anywhere once the 099ef17 DMS switch
  # made that whole directory DMS-owned -- the package itself was also
  # never in desktop-apps.nix's actual package list, only assumed there in
  # the original plan. Re-wired below via this file's existing
  # activation-script pattern instead of the old require()-a-repo-file
  # approach (that approach needed the repo checked out at a known path on
  # the target machine and a manual symlink step -- the activation script
  # already solves "get Lua into DMS's files" more simply, so folding this
  # into it is less machinery, not more). `hypr/quick-translate.lua`
  # removed as dead: nothing references it anymore.
  # glib -- provides `gdbus`, which the Crow Translate bind below shells
  # out to. Almost certainly already pulled in transitively by the
  # Qt6/quickshell stack DMS needs, but wasn't declared anywhere in this
  # repo before -- declaring it explicitly instead of relying on that.
  # swappy: annotation editor for screenshots (arrows/text/blur/shapes),
  # wired via grimblast's own `edit` action + GRIMBLAST_EDITOR below,
  # rather than a separate hand-rolled `grim -g "$(slurp)" | swappy -f -`
  # pipeline -- grimblast (already installed for the copysave binds
  # above) already implements that exact pattern internally and just
  # needs to be told which editor to launch (default is gimp, confirmed
  # by reading hyprwm/contrib's grimblast script directly: `edit()` calls
  # `$GRIMBLAST_EDITOR "$file"` on the captured region).
  # screenrec: screen recording, requested live (2026-10-06) next to the
  # screenshot binds. wf-recorder is Hyprland wiki's recommended recorder
  # for wlroots-style compositors ("Screenshots & Recording" page) and was
  # already installed (modules/nixos/hyprland.nix) but bound to nothing.
  # One toggle script instead of a GUI app: the same key starts and stops
  # (SIGINT makes wf-recorder finalize the file), notifications go through
  # DMS's notification daemon. No audio on purpose (silent screencasts for
  # tickets/bug reports); add `--audio` to the wf-recorder line if needed.
  # Dialect's translation service: Google (its web endpoint,
  # translate.google.com batchexecute). Checked from the VM, 2026-10-06:
  # that endpoint answers; Dialect 2.6.1's Yandex provider fails with
  # "Failed parsing HTML from yandex.com" (Yandex changed its page, the
  # scraper is out of date); Lingva's default instance returns 500.
  # (translate.googleapis.com, which Crow used, answers 429 -- a different
  # endpoint.) Set via dconf (key from Dialect's gschema:
  # /app/drey/Dialect/translators/active), re-applied on every activation.
  dconf.settings."app/drey/Dialect/translators".active = "google";

  home.packages = [
    pkgs.bibata-cursors
    pkgs.grimblast
    pkgs.dialect
    pkgs.glib
    pkgs.swappy
    # translate-selection: opens Dialect's window with the selected text
    # already in it and translated (asked for 2026-10-06: "окно переводчика
    # с вставленным текстом", not a notification). Dialect (GNOME, in
    # nixpkgs) takes --text/--dest on its command line and hands them to an
    # already running window. Text comes from the primary selection (falls
    # back to the clipboard) via wl-paste, not Dialect's own --selection,
    # which reads the selection through GTK and gets nothing on Wayland
    # unless Dialect itself has focus. Cyrillic -> English, else -> Russian.
    # Replaced Crow Translate 4.x: it lost its D-Bus API and opens its
    # window only empty; its CLI mode also printed Qt warnings into the
    # result (seen live in the VM).
    (pkgs.writeShellApplication {
      name = "translate-selection";
      runtimeInputs = with pkgs; [ wl-clipboard dialect gnugrep ];
      text = ''
        text="$(wl-paste --primary --no-newline 2>/dev/null || true)"
        [ -n "$text" ] || text="$(wl-paste --no-newline 2>/dev/null || true)"
        [ -n "$text" ] || exec dialect
        if printf '%s' "$text" | grep -q '[А-Яа-яЁё]'; then dest=en; else dest=ru; fi
        exec dialect --text "$text" --dest "$dest"
      '';
    })
    # Wallpaper Engine scenes/videos on the desktop (renderer only; the DMS
    # plugin "Linux Wallpaper Engine" drives it, set up by hand). The
    # wallpapers and Wallpaper Engine's `assets` come from Steam via
    # steamcmd, no Steam client installed (docs/REFERENCE.md, «Живые обои»).
    pkgs.linux-wallpaperengine
    # lockscreen-videos: video on the lock screen. DMS plays a random video
    # from a folder when lockScreenVideoPath is a directory (DMS
    # quickshell/Modules/Lock/VideoScreensaver.qml). This collects
    # Wallpaper Engine wallpapers of type "video" (plain mp4s, project.json
    # `type`/`file`) into ~/Videos/Lockscreen as HARD links -- no extra
    # space, and DMS's `find -type f` skips symlinks -- then points DMS at
    # the folder and turns the lock video on (DMS watches settings.json, no
    # restart). Any own videos dropped into the folder count too.
    (pkgs.writeShellApplication {
      name = "lockscreen-videos";
      runtimeInputs = with pkgs; [ jq findutils coreutils ];
      text = ''
        dir="$HOME/Videos/Lockscreen"
        we="''${1:-$HOME/.local/share/Steam/steamapps/workshop/content/431960}"
        settings="''${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/settings.json"
        mkdir -p "$dir"
        if [ -d "$we" ]; then
          for proj in "$we"/*/project.json; do
            [ -f "$proj" ] || continue
            [ "$(jq -r '(.type // "") | ascii_downcase' "$proj")" = video ] || continue
            file="$(jq -r '.file // empty' "$proj")"
            src="$(dirname "$proj")/$file"
            [ -n "$file" ] && [ -f "$src" ] || continue
            dst="$dir/we-$(basename "$(dirname "$proj")")-$(basename "$file")"
            ln -f "$src" "$dst" 2>/dev/null || cp -f "$src" "$dst"
          done
        fi
        count="$(find "$dir" -maxdepth 1 -type f \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' -o -iname '*.mov' \) | wc -l)"
        echo "lockscreen-videos: $count video(s) in $dir"
        if [ "$count" -eq 0 ]; then
          echo "Put videos there or download Wallpaper Engine video wallpapers (steamcmd), then run again." >&2
          exit 1
        fi
        if [ ! -f "$settings" ]; then
          echo "No $settings yet -- log into the desktop once (DMS creates it), then run again." >&2
          exit 1
        fi
        tmp="$(mktemp "$settings.XXXXXX")"
        jq --arg d "$dir" '.lockScreenVideoEnabled = true | .lockScreenVideoPath = $d' "$settings" > "$tmp"
        mv -f "$tmp" "$settings"
        echo "lockscreen-videos: DMS lock screen now plays a random video from $dir"
      '';
    })
    (pkgs.writeShellApplication {
      name = "screenrec";
      runtimeInputs = with pkgs; [ wf-recorder slurp libnotify procps coreutils ];
      text = ''
        dir="''${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"
        mkdir -p "$dir"
        if pgrep -x wf-recorder >/dev/null; then
          pkill -INT -x wf-recorder
          notify-send -a "Запись экрана" "Запись сохранена" "$dir"
          exit 0
        fi
        args=()
        if [ "''${1:-area}" = area ]; then
          geom="$(slurp)" || exit 0   # Esc in slurp = cancel, not an error
          args=(-g "$geom")
        fi
        file="$dir/rec-$(date +%F_%H-%M-%S).mp4"
        notify-send -a "Запись экрана" "Идёт запись" "Нажмите то же сочетание, чтобы остановить"
        exec wf-recorder "''${args[@]}" -f "$file"
      '';
    })
  ];

  # Requested live: ru+en layout with CapsLock as the switcher (real
  # xkb option, verified against xkeyboard-config's own base.xml.in,
  # not guessed) + binds that work in both layouts, plus a keybind for
  # DMS's own built-in keybinds cheatsheet (`dms ipc call hypr
  # toggleBinds` -- no separate app needed, see docs/IPC.md), all
  # applied automatically on every `nixos-rebuild switch` instead of by
  # hand.
  #
  # Still can't avoid ~/.config/hypr/ being DMS-owned (see this file's
  # own header comment on why wayland.windowManager.hyprland isn't used
  # at all) -- so this is a home.activation script, not xdg.configFile:
  # it APPENDS to the real files `dms setup` already deployed. Only
  # runs once hyprland.lua/dms/binds-user.lua actually exist -- `dms
  # setup` itself still has to run once by hand first (same
  # one-time-bootstrap category as `sbctl create-keys`/lazy.nvim's
  # first plugin install elsewhere in this repo), this just removes
  # every step *after* that.
  #
  # Correction, found live while chasing a "CapsLock does nothing"
  # report: a plain "if marker absent, append" guard is idempotent
  # against DUPLICATION but not against UPDATES -- once the block was
  # appended once (e.g. with the old grp:caps_switch value), the marker
  # is permanently present, so a later edit to this Nix file would
  # silently stop reaching the deployed file on subsequent
  # `nixos-rebuild switch` runs, defeating the entire point of managing
  # this from Nix. Fixed by using BEGIN/END sentinels and unconditionally
  # deleting any previously-appended block before re-appending the
  # current one -- convergent on every activation, same as any other
  # Nix-managed setting, not just on first write.
  # One-time `dms setup`, done by activation instead of by hand. Without it
  # the first login landed in Hyprland's autogenerated config, whose SUPER+Q
  # starts kitty (not installed; ghostty is), so there was no way to open a
  # terminal and run `dms setup` without a TTY detour (found live in the
  # mimir VM rehearsal, 2026-10-06).
  #
  # `dms setup` has no non-interactive flags, but reads every answer with a
  # plain line read from stdin, in this order (DMS core/cmd/dms/
  # commands_setup.go at the rev pinned in flake.nix, 7974887):
  #   compositor 2 = Hyprland, terminal 1 = Ghostty, systemd 1 = Yes
  #   (what the hyprland.lua it writes expects, see the "Correction" note
  #   in this file's header), "Proceed?" y.
  # RE-CHECK THE ORDER when bumping the dank-material-shell input.
  # Its deploy step only writes files under ~/.config (checked: no exec in
  # core/internal/config), so it is safe here with no Wayland session yet;
  # an existing autogenerated hyprland.lua is backed up by DMS itself. The
  # ghostty config it writes doesn't clash with home-manager, which only
  # owns ~/.config/ghostty/config when programs.ghostty.settings is set
  # (it isn't, modules/home/ghostty.nix). The `input` group prompt is
  # skipped because max is already in it (hosts/mimir/configuration.nix).
  # Marker is ~/.config/hypr/dms/, which only `dms setup` creates — so it
  # runs exactly once, and never over a setup done by hand. A failure only
  # warns: a broken activation would block the whole nixos-rebuild.
  home.activation.dmsBootstrap = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "$HOME/.config/hypr/dms" ]; then
      echo "dms setup: first run, deploying DMS Hyprland/Ghostty config"
      if ! printf '2\n1\n1\ny\n' | ${config.programs.dank-material-shell.package}/bin/dms setup \
           || [ ! -d "$HOME/.config/hypr/dms" ]; then
        echo "WARNING: automatic 'dms setup' failed; run it by hand (docs/INSTALL.md)" >&2
      fi
    fi
  '';

  # A few wallpapers so DMS's picker (Settings → Wallpaper, which browses a
  # folder) isn't empty on a fresh install: nixos-artwork from nixpkgs, so
  # nothing is downloaded from random sites and licenses are known.
  # Read-only store symlinks are fine here -- DMS only reads them; drop
  # your own files next to them in ~/Pictures/Wallpapers.
  home.file = lib.listToAttrs (map (name: {
    name = "Pictures/Wallpapers/nixos-${name}.png";
    value.source = pkgs.nixos-artwork.wallpapers.${name}.gnomeFilePath;
  }) [ "catppuccin-mocha" "catppuccin-macchiato" "nineish-dark-gray" "moonscape" "waterfall" "dracula" ]);

  # DMS first-run defaults it has no Nix option for, written into its own
  # state file (~/.local/state/DankMaterialShell/session.json, DMS
  # quickshell/Common/SessionData.qml), only where the value is still DMS's
  # factory default -- anything changed in DMS Settings later is left alone:
  # - weather: Rostov-on-Don instead of DMS's "New York, NY" (requested
  #   2026-10-06). Name + coordinates together make DMS skip geocoding
  #   (WeatherService.qml) and query open-meteo directly.
  # - wallpaper: catppuccin-mocha from the set above, when none is set.
  # DMS keeps session.json in memory and rewrites it on its own changes, so
  # it is restarted once when something was actually changed here.
  home.activation.dmsDefaults = lib.hm.dag.entryAfter [ "linkGeneration" "dmsBootstrap" ] ''
    STATE="$HOME/.local/state/DankMaterialShell/session.json"
    mkdir -p "$(dirname "$STATE")"
    [ -s "$STATE" ] || echo '{}' > "$STATE"
    NEW="$(${pkgs.jq}/bin/jq \
      --arg wall "$HOME/Pictures/Wallpapers/nixos-catppuccin-mocha.png" '
        (if ((.weatherLocation // "New York, NY") == "New York, NY") then
           .weatherLocation = "Ростов-на-Дону" | .weatherCoordinates = "47.2357,39.7015"
         else . end)
        | (if ((.wallpaperPath // "") == "") then .wallpaperPath = $wall else . end)
      ' "$STATE")" || NEW=""
    if [ -n "$NEW" ] && [ "$NEW" != "$(cat "$STATE")" ]; then
      printf '%s\n' "$NEW" > "$STATE"
      echo "dms defaults: weather/wallpaper set in $STATE"
      ${pkgs.systemd}/bin/systemctl --user try-restart dms.service 2>/dev/null || true
    fi
  '';

  # Files are rebuilt next to the original and swapped in with one atomic
  # `mv`, then any running Hyprland is told to reload. Editing in place
  # (sed -i, then append) was racy: Hyprland watches its config and once
  # reloaded in between the two writes, i.e. without the INPUT block, and
  # missed the second change -- layout/CapsLock switching silently reset to
  # defaults until the next reload (found live in the VM, 2026-10-06).
  home.activation.dmsHyprlandExtras = lib.hm.dag.entryAfter [ "dmsBootstrap" ] ''
    HYPR_CONF="$HOME/.config/hypr/hyprland.lua"
    if [ -f "$HYPR_CONF" ]; then
      TMP="$(mktemp "$HYPR_CONF.XXXXXX")"
      ${pkgs.gnused}/bin/sed \
        -e '/-- NIXOS-MANAGED INPUT BLOCK START/,/-- NIXOS-MANAGED INPUT BLOCK END/d' \
        -e '/-- NIXOS-MANAGED AUTOSTART BLOCK START/,/-- NIXOS-MANAGED AUTOSTART BLOCK END/d' \
        -e '/-- NIXOS-MANAGED CURSOR BLOCK START/,/-- NIXOS-MANAGED CURSOR BLOCK END/d' \
        "$HYPR_CONF" | ${pkgs.gnused}/bin/sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$TMP"
      cat >> "$TMP" <<'HYPRLUA'

-- NIXOS-MANAGED INPUT BLOCK START -- managed by home-manager activation
-- (modules/home/hyprland.nix), not hand-edited; re-synced on every
-- `nixos-rebuild switch`, don't edit between START/END by hand.
-- kb_options "grp:caps_toggle": one CapsLock tap persistently toggles
-- ru/en (verified against xkeyboard-config's rules/base.xml.in --
-- "grp:caps_switch", used here originally, is documented as "CapsLock
-- (while pressed)", a HOLD not a toggle, which is exactly the
-- "не переключает" symptom reported live; released reverts to the base
-- layout). Tradeoff accepted live: caps_toggle has no reserved fallback
-- combo for real Caps Lock -- xkb has no option pairing a persistent
-- tap-toggle with an alternate real-capslock combo (checked the full
-- option list), so plain CapsLock no longer does normal capslock at
-- all.
--
-- resolve_binds_by_sym: CORRECTED 2026-10-07, previous value here (true)
-- was backwards and is why SUPER+T (and every other letter bind) stopped
-- firing once the ru layout was active -- reported live. What the option
-- actually does (Hyprland wiki, "Keyboard layouts" page; cross-checked
-- against Hyprland's own default of false):
--   false (default): a bind's letter ("T" etc.) is resolved to a keycode
--     ONCE, against the FIRST kb_layout (here "us"), and matched by that
--     keycode from then on -- i.e. the bind sticks to a physical key
--     position regardless of which layout is currently active. This is
--     what "SUPER+T always opens a terminal, even on ru" needs.
--   true: a bind is matched by comparing the SYMBOL the *currently
--     active* layout produces at the pressed key against the bind's
--     letter. Latin "T" has no Cyrillic key that produces it, so under
--     ru the bind becomes unreachable -- exactly the reported symptom.
-- The old comment's assumption ("matches by symbol so it keeps working")
-- had this exactly backwards; grp:caps_toggle (the xkb layout-switch
-- itself) is unrelated to this option and is unaffected by the fix.
hl.config({
  input = {
    kb_layout = "us,ru",
    kb_options = "grp:caps_toggle",
    resolve_binds_by_sym = false,
  },
})
-- NIXOS-MANAGED INPUT BLOCK END

-- NIXOS-MANAGED AUTOSTART BLOCK START -- managed by home-manager activation
-- (modules/home/hyprland.nix), not hand-edited; re-synced on every
-- `nixos-rebuild switch`, don't edit between START/END by hand.
-- SPICE clipboard agent for the session, only where its system daemon
-- runs (the VM rehearsal; services.spice-vdagentd in hosts/mimir is gated
-- on facter detecting QEMU/KVM). Started here because this Hyprland
-- session doesn't run XDG autostart, which is the only thing that would
-- otherwise launch it (found live in the VM, 2026-10-06). On the laptop the
-- socket doesn't exist and this does nothing.
-- (Was: autostart of Crow Translate for its D-Bus hotkey. Crow 4.x has no
-- D-Bus API and its binary is `crow`; the translate bind below now calls
-- the CLI on demand instead, so nothing needs to run in the background.)
-- Portals after a log out / log in (found live in the VM, 2026-10-06): the
-- user systemd manager outlives the Hyprland session, so on logout the
-- portals restart without a compositor, hit systemd's start limit and
-- stay "failed" in the next session (screen sharing, file dialogs and
-- screenshot portals then don't work until reboot). Clear that and start
-- them fresh; the sleep lets DMS's own start hook push the session
-- environment (dbus-update-activation-environment) first.
hl.on("hyprland.start", function()
  hl.exec_cmd("sh -c '[ -S /run/spice-vdagentd/spice-vdagent-sock ] && exec spice-vdagent'")
  hl.exec_cmd("sh -c 'sleep 2; systemctl --user reset-failed xdg-desktop-portal.service xdg-desktop-portal-hyprland.service xdg-desktop-portal-gtk.service; systemctl --user restart xdg-desktop-portal.service'")
end)
-- End the session properly on logout. Hyprland runs via start-hyprland, not
-- a session manager (uwsm would do this), so nothing stopped
-- graphical-session.target when Hyprland exited: dms, dcal and the portals
-- (all PartOf it) kept running without a display, crashed and were
-- restarted in a loop -- a burst of quickshell/portal coredumps at every
-- logout in the VM journal (2026-10-06). Stopping the targets here stops
-- them cleanly; at the next login DMS's own start hook starts
-- hyprland-session.target again with the fresh session environment.
-- --no-block: Hyprland is exiting, don't wait on the jobs.
hl.on("hyprland.shutdown", function()
  hl.exec_cmd("systemctl --user --no-block stop hyprland-session.target graphical-session.target")
end)
-- NIXOS-MANAGED AUTOSTART BLOCK END

-- NIXOS-MANAGED CURSOR BLOCK START -- managed by home-manager activation
-- (modules/home/hyprland.nix, see home.pointerCursor there); don't edit
-- between START/END by hand. Same lines DMS's Settings → Cursor writes
-- to dms/cursor.lua; env for apps started from Hyprland, setcursor for
-- Hyprland's own pointer right after start.
hl.env("XCURSOR_THEME", "${config.home.pointerCursor.name}")
hl.env("XCURSOR_SIZE", "${toString config.home.pointerCursor.size}")
hl.env("HYPRCURSOR_THEME", "${config.home.pointerCursor.name}")
hl.env("HYPRCURSOR_SIZE", "${toString config.home.pointerCursor.size}")
hl.on("hyprland.start", function()
  hl.exec_cmd("hyprctl setcursor ${config.home.pointerCursor.name} ${toString config.home.pointerCursor.size}")
end)
-- NIXOS-MANAGED CURSOR BLOCK END
HYPRLUA
      mv -f "$TMP" "$HYPR_CONF"
    fi

    BINDS_USER="$HOME/.config/hypr/dms/binds-user.lua"
    if [ -f "$BINDS_USER" ]; then
      TMP="$(mktemp "$BINDS_USER.XXXXXX")"
      ${pkgs.gnused}/bin/sed '/-- NIXOS-MANAGED BINDS START/,/-- NIXOS-MANAGED BINDS END/d' "$BINDS_USER" \
        | ${pkgs.gnused}/bin/sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$TMP"
      cat >> "$TMP" <<'HYPRLUA'

-- NIXOS-MANAGED BINDS START -- managed by home-manager activation
-- (modules/home/hyprland.nix), not hand-edited; re-synced on every
-- `nixos-rebuild switch`, don't edit between START/END by hand.
-- Shows DMS's own built-in keybinds cheatsheet modal.
hl.bind("SUPER + slash", hl.dsp.exec_cmd("dms ipc call hypr toggleBinds"))
-- Screenshots via grimblast (DMS's own screenshot IPC is niri-only, see
-- comment above this activation script's home.packages entry) --
-- "copysave" copies to clipboard AND writes a file in one shot, the
-- scheme recommended on Hyprland's own Screenshots & Recording wiki
-- page: bare Print = region select, Shift+Print = whole screen,
-- Super+Print = focused window only.
hl.bind("Print", hl.dsp.exec_cmd("grimblast copysave area"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("grimblast copysave screen"))
hl.bind("SUPER + Print", hl.dsp.exec_cmd("grimblast copysave active"))
-- Annotate: opens the region capture in swappy (arrows/text/blur/shapes)
-- instead of saving it directly, via grimblast's own `edit` action --
-- GRIMBLAST_EDITOR set inline in the command string, not exported
-- globally, so it only affects this one bind and leaves the copysave
-- binds above (which don't call `edit` at all) unaffected either way.
hl.bind("SUPER + SHIFT + Print", hl.dsp.exec_cmd("GRIMBLAST_EDITOR=swappy grimblast edit area"))
-- Screen recording (screenrec, see home.packages): press once to start,
-- same keys again to stop; files in ~/Videos/Recordings. Region / whole
-- screen. SUPER+R alone is DMS's togglesplit, these combos are free.
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("screenrec area"))
hl.bind("SUPER + CTRL + R", hl.dsp.exec_cmd("screenrec screen"))
-- Windows-style Win key (asked for 2026-10-06):
-- - a tap of Win alone opens DMS's app launcher/search, like the Start
--   menu. A lone modifier can only be bound as a *release* bind
--   (`bindr = SUPER, SUPER_L, ...` in hyprlang, `release = true` here); the
--   syntax was checked against the running Hyprland 0.56.1 (registered as
--   bindr, key SUPER_L). SUPER+Space (DMS's default) stays as a fallback in
--   case the tap also fires after other Win combos on your keyboard.
-- - Win+E opens the file manager (Nautilus, desktop-apps.nix).
hl.bind("SUPER + SUPER_L", hl.dsp.exec_cmd("dms ipc call spotlight toggle"), { release = true })
hl.bind("SUPER + E", hl.dsp.exec_cmd("nautilus"))
-- Translate the current selection (system-plan.md §5.11): SUPER+ALT+T runs
-- translate-selection (home.packages) -- selected text -> Crow's CLI ->
-- DMS notification. SUPER+T is taken by DMS's terminal bind (seeded into
-- dms/binds-user.lua by `dms setup`), SUPER+ALT+T is free there.
hl.bind("SUPER + ALT + T", hl.dsp.exec_cmd("translate-selection"))
-- NIXOS-MANAGED BINDS END
HYPRLUA
      mv -f "$TMP" "$BINDS_USER"
    fi

    # Explicit reload of every running Hyprland of this user, after both
    # files are in place (no-op at boot, when none is running yet).
    for inst in "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/hypr/*/; do
      [ -S "$inst.socket.sock" ] || continue
      HYPRLAND_INSTANCE_SIGNATURE="$(basename "$inst")" \
        ${pkgs.hyprland}/bin/hyprctl reload >/dev/null 2>&1 || true
    done
  '';
}
