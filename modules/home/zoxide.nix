# zoxide: fast `cd` by frecency (asked live 2026-10-19, "быстро переходить
# по часто используемым папкам") -- `z <part-of-name>` jumps straight to a
# previously-visited directory that matches, `zi` opens an fzf picker when
# there's more than one match (fzf already on this system, base.nix). No
# per-project config needed -- it just learns from normal `cd` usage over
# time. Pairs with yazi (modules/home/yazi.nix, `y`) and LazyVim
# (modules/home/neovim.nix) for the full "jump → browse → edit" flow asked
# for in the same conversation.
{ ... }:
{
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };
}
