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
    # Ctrl+Left/Right = word jumps. Ghostty sends xterm-style
    # "\e[1;5D"/"\e[1;5C"; zsh's emacs keymap has no binding for them, so
    # the tail was typed literally (";5C", reported live). forward-word is
    # also in zsh-autosuggestions' default ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS,
    # so Ctrl+Right accepts the grey suggestion one word at a time — the
    # behaviour asked for. "\e[5C"/"\e[5D" cover terminals that omit "1;".
    initContent = ''
      bindkey '^[[1;5C' forward-word
      bindkey '^[[1;5D' backward-word
      bindkey '^[[5C' forward-word
      bindkey '^[[5D' backward-word
      # Ctrl+Backspace / Ctrl+Delete = delete a word back / forward (were
      # unbound, reported 2026-10-06). Ghostty sends ^H for Ctrl+Backspace
      # (plain Backspace is \x7f, so ^H is free) or \e[27;5;127~ with
      # modifyOtherKeys, and \e[3;5~ for Ctrl+Delete (ghostty
      # src/input/function_keys.zig).
      bindkey '^H' backward-kill-word
      bindkey '^[[27;5;127~' backward-kill-word
      bindkey '^[[3;5~' kill-word
    '';
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
