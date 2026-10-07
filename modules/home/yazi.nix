# yazi: terminal file manager (asked for 2026-10-06, next to the GUI one,
# Nautilus in modules/nixos/desktop-apps.nix). The most popular terminal
# file manager on Arch by pkgstats (20% of ~32k systems; ranger 11%,
# nnn 5%). Fast, vim-style keys, previews of images/PDF/video/archives --
# ghostty speaks the kitty graphics protocol yazi uses for images.
#
# Start it with `y`, not `yazi`: the wrapper changes the shell's directory
# to where you were in yazi when you quit (q); plain `yazi` can't do that
# (a child process can't `cd` its parent). The wrapper name is set
# explicitly: home-manager's default depends on home.stateVersion ("ys"
# below 26.05) and warns when it is left implicit.
#
# Preview helpers (ffmpeg, poppler, 7zip, jq, fd, ripgrep, fzf, zoxide,
# imagemagick) come with nixpkgs' yazi wrapper itself, not listed here.
# No settings/keymap invented: upstream defaults first, tune by use
# (same "no fabricated preferences" rule as zellij.nix).
{ ... }:
{
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    shellWrapperName = "y";
  };
}
