# direnv + nix-direnv (system-plan.md §5.3: "авто-окружения на проект").
# nix-direnv.enable bundles the nix-direnv extension automatically --
# home-manager's own recommended pairing, confirmed via nix eval against
# this repo's pinned home-manager (see docs/superpowers/specs/
# 2026-08-11-neovim-base-design.md-style verification discipline: checked
# the real option, not assumed).
{ ... }:
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
  };
}
