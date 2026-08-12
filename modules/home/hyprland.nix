# Real Hyprland config content -- see
# docs/superpowers/specs/2026-08-12-hyprland-config-design.md. Uses
# home-manager's own wayland.windowManager.hyprland module (fetched and
# read in full against this repo's pinned home-manager rev before
# writing this -- see design doc "Decision"), not hand-vendored Lua text:
# package/portalPackage = null defers installation to
# modules/nixos/hyprland.nix's programs.hyprland.enable (this module only
# generates config, matching that option's own documented purpose for
# NixOS-module users). configType = "lua" -- Hyprland 0.55 (2026-05-09)
# deprecated the old hyprlang .conf format in favor of Lua, see
# system-plan.md §5.11.
{ lib, pkgs, ... }:
let
  inherit (lib.generators) mkLuaInline;

  # One `hl.bind(key, <raw lua handler>, opts?)` call. handler is raw Lua
  # source (wrapped in mkLuaInline here so callers just pass a string) --
  # see design doc "Nix -> Lua translation rules" for why this needs
  # mkLuaInline and _var/string-concat locals don't (nothing here is a
  # runtime Lua variable, it's all resolved at Nix-eval time).
  bind =
    key: handler: opts:
    {
      _args = [ key (mkLuaInline handler) ] ++ lib.optional (opts != null) opts;
    };
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    package = null;
    portalPackage = null;
    systemd.enable = true;

    settings = {
      monitor = {
        output = "";
        mode = "preferred";
        position = "auto";
        scale = "auto";
      };

      # general/decoration/input/dwindle etc. all nest inside one
      # hl.config({...}) call -- see design doc, multiple hl.config()
      # calls are equivalent but this is simpler.
      config = {
        general = {
          gaps_in = 5;
          gaps_out = 10;
          border_size = 2;
          layout = "dwindle";
        };
        input = {
          kb_layout = "us";
          follow_mouse = 1;
          touchpad.natural_scroll = true;
        };
        dwindle.preserve_split = true;
      };

      bind = [
        (bind "SUPER + RETURN" ''hl.dsp.exec_cmd("kitty")'' null)
        (bind "SUPER + Q" "hl.dsp.window.close()" null)
        (bind "SUPER + D" ''hl.dsp.exec_cmd("fuzzel")'' null)
        (bind "SUPER + V" ''hl.dsp.window.float({ action = "toggle" })'' null)
        (bind "SUPER + F" ''hl.dsp.window.fullscreen({ action = "toggle" })'' null)
        (bind "SUPER + L" ''hl.dsp.exec_cmd("hyprlock")'' null)
        # Region screenshot -> clipboard. Nix's ''...'' strings don't
        # treat " or \ specially, so \" here passes through untouched
        # into the generated Lua source as the correct Lua string-escape
        # for grim's embedded "$(slurp)" quoting -- see design doc.
        (bind "SUPER + SHIFT + S" ''hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy")'' null)
        (bind "SUPER + SHIFT + V" ''hl.dsp.exec_cmd("cliphist list | fuzzel --dmenu | cliphist decode | wl-copy")'' null)
        # Crow Translate hotkey -- system-plan.md §5.11, verbatim
        # (translateSelection is the app's own documented D-Bus
        # integration point for compositors without global hotkeys).
        (bind "SUPER + T" ''hl.dsp.exec_cmd("gdbus call --session --dest io.crow_translate.CrowTranslate --object-path /io/crow_translate/CrowTranslate/MainWindow --method io.crow_translate.CrowTranslate.MainWindow.translateSelection")'' null)

        (bind "SUPER + left" ''hl.dsp.focus({ direction = "left" })'' null)
        (bind "SUPER + right" ''hl.dsp.focus({ direction = "right" })'' null)
        (bind "SUPER + up" ''hl.dsp.focus({ direction = "up" })'' null)
        (bind "SUPER + down" ''hl.dsp.focus({ direction = "down" })'' null)

        (bind "SUPER + mouse_down" ''hl.dsp.focus({ workspace = "e+1" })'' null)
        (bind "SUPER + mouse_up" ''hl.dsp.focus({ workspace = "e-1" })'' null)

        (bind "SUPER + mouse:272" "hl.dsp.window.drag()" {
          mouse = true;
        })
        (bind "SUPER + mouse:273" "hl.dsp.window.resize()" {
          mouse = true;
        })

        (bind "SUPER + SHIFT + Q" "hl.dsp.exit()" null)
      ]
      # Workspaces 1-9,0 (key "0" maps to workspace 10, matching
      # upstream example/hyprland.lua's own convention) + move-window
      # variants.
      ++ (lib.concatMap (
        i:
        let
          key = if i == 10 then 0 else i;
        in
        [
          (bind "SUPER + ${toString key}" "hl.dsp.focus({ workspace = ${toString i} })" null)
          (bind "SUPER + SHIFT + ${toString key}" ''hl.dsp.window.move({ workspace = ${toString i} })'' null)
        ]
      ) (lib.range 1 10));

      # Autostart -- one hook, not scattered exec_cmd calls at
      # file-load time (those would fire on every config reload, not
      # just session start). crow-translate: backgrounded so its D-Bus
      # service is ready before the first SUPER+T. wl-paste --watch:
      # the standard (and only) way cliphist actually populates its
      # history -- the package alone does nothing without this.
      on = [
        {
          _args = [
            "hyprland.start"
            (mkLuaInline ''
              function()
                hl.exec_cmd("crow-translate")
                hl.exec_cmd("wl-paste --type text --watch cliphist store")
                hl.exec_cmd("wl-paste --type image --watch cliphist store")
              end
            '')
          ];
        }
      ];
    };
  };

  # Shared session target waybar/hypridle/mako's own systemd integration
  # binds to -- defaults to generic "graphical-session.target", which
  # nothing here would ever start. wayland.windowManager.hyprland's
  # hyprland-session.target (above, systemd.enable = true) is what
  # actually gets reached on hyprland.start.
  wayland.systemd.target = "hyprland-session.target";

  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 30;
      modules-left = [ "hyprland/workspaces" ];
      modules-center = [ "clock" ];
      modules-right = [
        "pulseaudio"
        "network"
        "battery"
        "tray"
      ];
    };
    # Catppuccin Mocha -- user picked this after being shown the choice
    # of a few ready-made themes (Catppuccin/Cherry Crush/etc), not
    # invented here. Vendored palette + our own module styling, see
    # ./hyprland/waybar-mocha.css's own header comment for the split.
    style = ./hyprland/waybar-mocha.css;
  };

  # D-Bus-activatable (org.freedesktop.Notifications) -- no autostart
  # entry needed. Catppuccin Mocha Mauve, vendored verbatim from
  # https://github.com/catppuccin/mako (themes/catppuccin-mocha/
  # catppuccin-mocha-mauve), MIT license -- matches waybar's accent
  # (mauve) for a consistent look across both.
  services.mako = {
    enable = true;
    settings = {
      background-color = "#1e1e2e";
      text-color = "#cdd6f4";
      border-color = "#cba6f7";
      "progress-color" = "over #313244";
      "urgency=high" = {
        border-color = "#fab387";
      };
    };
  };

  # Needs system-level PAM config to actually authenticate -- see
  # modules/nixos/hyprland.nix's security.pam.services.hyprlock.
  # Settings below translate catppuccin/hyprlock's real
  # hyprlock.conf + themes/mocha.conf (MIT license) into this module's
  # Nix settings attrset -- their $accent/$mauve variable indirection
  # (hyprlock's own feature) isn't used here since Nix is already doing
  # that substitution at eval time. Dropped: the user-avatar image block
  # (needs $HOME/.face, no such asset in this repo) and the fingerprint
  # label (no fingerprint hardware to assume) -- same "no fabricated
  # asset/preference" boundary as skipping hyprpaper below.
  programs.hyprlock = {
    enable = true;
    settings = {
      general.hide_cursor = true;
      background = [
        {
          # No hyprpaper wallpaper (see comment below) -- solid Mocha
          # base color instead of a path.
          color = "rgba(1e1e2eff)";
        }
      ];
      label = [
        {
          text = "$TIME";
          color = "rgba(cdd6f4ff)";
          font_size = 90;
          font_family = "JetBrainsMono Nerd Font";
          position = "-30, 0";
          halign = "right";
          valign = "top";
        }
        {
          text = ''cmd[update:43200000] date +"%A, %d %B %Y"'';
          color = "rgba(cdd6f4ff)";
          font_size = 25;
          font_family = "JetBrainsMono Nerd Font";
          position = "-30, -150";
          halign = "right";
          valign = "top";
        }
      ];
      input-field = [
        {
          size = "300, 60";
          outline_thickness = 4;
          dots_size = 0.2;
          dots_spacing = 0.2;
          dots_center = true;
          outer_color = "rgba(cba6f7ff)";
          inner_color = "rgba(313244ff)";
          font_color = "rgba(cdd6f4ff)";
          fade_on_empty = false;
          hide_input = false;
          check_color = "rgba(cba6f7ff)";
          fail_color = "rgba(f38ba8ff)";
          fail_text = "<i>$FAIL <b>($ATTEMPTS)</b></i>";
          capslock_color = "rgba(f9e2afff)";
          position = "0, -47";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };

  # settings taken directly from the module's own documented example
  # (real, required auto-lock timing, not invented from nothing):
  # lock after 15min idle, screen off after 20min, guard against
  # stacking multiple hyprlock instances.
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        {
          timeout = 900;
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 1200;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };

  # services.hyprpaper deliberately not enabled -- no wallpaper image
  # asset in this repo, picking one is a personal choice out of this
  # round's scope (see design doc). Binary is already installed at the
  # system level (modules/nixos/hyprland.nix).

  home.packages = with pkgs; [ crow-translate ];
}
