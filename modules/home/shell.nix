# First real modules/home/* content (home-manager dotfiles, not just
# infrastructure) -- zsh + starship + eza + git config/aliases. See
# docs/superpowers/specs/2026-08-11-shell-zellij-design.md "Research
# findings" for the home-manager option details confirmed here (eza's
# auto-generated ls aliases, git's non-obsolete `settings` option,
# starship's auto zsh-integration).
{ ... }:
{
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    historySubstringSearch.enable = true;
    shellAliases = {
      ".." = "cd ..";
      "..." = "cd ../..";
      gs = "git status";
      gc = "git commit";
      gp = "git push";
      gl = "git pull";
      gd = "git diff";
    };
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true; # generates ls/ll/la/lt/lla aliases
      # automatically -- confirmed by reading home-manager's own
      # eza.nix module source at this repo's pinned rev, not assumed.
    git = true; # adds --git to the generated `eza` alias -- shows git
      # status markers (modified/untracked/etc.) inline in listings
  };

  programs.starship.enable = true; # zsh integration auto-enables once
    # programs.zsh.enable = true (confirmed by eval, see design doc) --
    # default prompt preset, no custom starship.toml content yet.

  programs.git = {
    enable = true;
    # programs.git.aliases/extraConfig are obsolete in this repo's
    # pinned home-manager (confirmed via a real eval warning) -- the
    # current, non-obsolete shape is this single `settings` attrset.
    settings = {
      alias = {
        co = "checkout";
        br = "branch";
        st = "status";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
    };
    # Deliberately no settings.user (name/email) -- real personal
    # identity, same real-install-time boundary as SSH/GPG host keys and
    # users.users.* elsewhere in this repo. Git already prompts clearly
    # the first time it's needed without one.
  };
}
