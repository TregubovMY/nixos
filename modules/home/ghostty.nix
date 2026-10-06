# Ghostty terminal emulator (system-plan.md §5.3, originally kitty --
# switched per explicit user request, discussed live: zellij already
# owns tabs/splits/multiplexing in this repo, so kitty's own
# tabs/splits/graphics-protocol edge over a minimal terminal buys
# nothing here; Ghostty picked for being actively popular/fast-growing
# and native tabs/splits of its own, a straight 1:1 terminal swap, not a
# multi-tool consolidation). Minimal on purpose, same as the kitty
# config it replaces: no theme/font customization invented here (same
# "no fabricated preferences" boundary as zellij.nix's bare defaults and
# shell.nix's lack of a starship.toml) -- upstream defaults are a
# reasonable start, real preferences are a live, interactive decision
# for whoever actually uses this terminal day to day.
{ lib, pkgs, ... }:
{
  programs.ghostty.enable = true;

  # Ctrl+V pastes in the terminal (asked for 2026-10-06; ghostty's default
  # is Ctrl+Shift+V, which stays working too). Written as a managed block
  # into ~/.config/ghostty/config -- NOT through programs.ghostty.settings:
  # that would make home-manager own the file as a read-only Nix symlink,
  # but `dms setup` (modules/home/hyprland.nix, dmsBootstrap) writes this
  # very file (fonts, padding, theme include) and the activation would
  # refuse to replace it. DMS even ships the line commented out
  # (`#keybind = ctrl+v=paste_from_clipboard`); the block goes last so it
  # wins. Rebuilt in a temp file and swapped with one `mv`, same reason as
  # the hyprland.lua blocks (an in-place edit races with the app's reload).
  #
  # Trade-off: Ctrl+V no longer reaches programs in the terminal -- in
  # Neovim visual-block mode is Ctrl+Q then (Neovim documents <C-q> as the
  # same command "for terminals where CTRL-V means paste"). Takes effect in
  # new ghostty windows, or reload the config with Ctrl+Shift+,.
  home.activation.ghosttyKeys = lib.hm.dag.entryAfter [ "writeBoundary" "dmsBootstrap" ] ''
    CONF="$HOME/.config/ghostty/config"
    if [ -f "$CONF" ]; then
      TMP="$(mktemp "$CONF.XXXXXX")"
      # (second sed: drop trailing blank lines, otherwise the blank line the
      # block starts with accumulates once per activation)
      ${pkgs.gnused}/bin/sed '/# NIXOS-MANAGED KEYS START/,/# NIXOS-MANAGED KEYS END/d' "$CONF" \
        | ${pkgs.gnused}/bin/sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$TMP"
      cat >> "$TMP" <<'GHOSTTY'

# NIXOS-MANAGED KEYS START -- managed by home-manager activation
# (modules/home/ghostty.nix), don't edit between START/END by hand.
keybind = ctrl+v=paste_from_clipboard
# NIXOS-MANAGED KEYS END
GHOSTTY
      mv -f "$TMP" "$CONF"
    fi
  '';
}
