# kitty terminal emulator (system-plan.md §5.3). Minimal on purpose: no
# theme/font customization invented here (same "no fabricated
# preferences" boundary as zellij.nix's bare defaults and shell.nix's
# lack of a starship.toml) -- upstream defaults are a reasonable start,
# real preferences are a live, interactive decision for whoever actually
# uses this terminal day to day.
{ ... }:
{
  programs.kitty.enable = true;
}
