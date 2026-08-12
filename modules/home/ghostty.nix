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
{ ... }:
{
  programs.ghostty.enable = true;
}
