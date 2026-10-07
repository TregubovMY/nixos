# First real modules/home/* content (home-manager dotfiles, not just
# infrastructure) -- zsh + starship + eza + git config/aliases. See
# docs/superpowers/specs/2026-08-11-shell-zellij-design.md "Research
# findings" for the home-manager option details confirmed here (eza's
# auto-generated ls aliases, git's non-obsolete `settings` option,
# starship's auto zsh-integration).
{ lib, ... }:
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
      # Global/default identity -- GitHub and everything else not covered
      # by the includeIf block below. Previously left unset on purpose
      # (real personal identity, same boundary as SSH/GPG keys elsewhere
      # in this repo); reversed 2026-10-07 on explicit request -- name and
      # email aren't secrets, there's no reason not to commit them like
      # any other dotfile value.
      user = {
        name = "Maxim Tregubov";
        email = "tregubov-m@inbox.ru";
      };
    };
    # Per-project-folder identity override, requested live 2026-10-07:
    # "своя идентичность для каждой из папки work" -- one includeIf block
    # per work subfolder (only ~/code/work/rnds/ exists so far, see
    # home.activation.codeDirs below; copy this block's shape for the next
    # employer's folder when one shows up). gitdir patterns without a
    # trailing "/**" still match the whole subtree -- git-config(1):
    # a pattern ending in "/" has "**" appended implicitly.
    # SSH key selection for br.rnds.pro is NOT done here and NOT managed
    # by Nix at all -- ~/.ssh/config (Host blocks, IdentityFile per host)
    # is kept out of this repo on purpose: a real per-host config would
    # expose internal IPs/hostnames not meant to be committed. It's a
    # secure note in Bitwarden instead, copied to ~/.ssh/config by hand
    # (same "real infra details live in Bitwarden" boundary as the SSH
    # keys/Throne proxy config themselves, system-plan.md §6/§7) -- ssh
    # config is host-based, so it applies regardless of which directory
    # the repo happens to live in.
    includes = [
      {
        condition = "gitdir:~/code/work/rnds/";
        contents.user = {
          name = "Maxim Tregubov";
          email = "mtregubov@rnds.pro";
        };
      }
    ];
  };

  # ~/code project-folder skeleton, requested live 2026-10-07. Plain
  # `mkdir -p` via activation, not `home.file."…/.keep".text = ""`: the
  # latter would leave a Nix-store-symlinked placeholder file sitting in
  # every one of these folders forever; mkdir -p only needs to run once
  # per missing directory and leaves the folders themselves as normal,
  # freely-writable directories, same reasoning as the ghostty.nix
  # activation block next to this one. Idempotent -- never touches
  # anything already there.
  home.activation.codeDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/code/work/rnds" "$HOME/code/sfedu" "$HOME/code/learn"
  '';
}
