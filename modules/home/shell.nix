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
      # Ctrl+Left/Right and Ctrl+Backspace jumped/deleted a whole path in
      # one go instead of stopping at each "/" (reported live 2026-10-19)
      # -- not a bindkey problem, zsh's default $WORDCHARS
      # ("*?_-.[]~=/&;!#$%^(){}<>") includes "/" itself, so
      # forward-word/backward-word/kill-word treat the whole path as one
      # word. Stripping just "/" out (not hardcoding the rest of the
      # default, in case zsh changes it upstream) makes each path segment
      # its own word for all four widgets below, without touching
      # anything else WORDCHARS covers (dots in filenames, etc).
      WORDCHARS=''${WORDCHARS//\//}

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

      # Tab-completion for agent-sandbox: subcommands, @name configs (read
      # fresh from ~/.config/agent-sandbox/projects/*.conf every time, so a
      # newly added config shows up without a new shell) and its flags. Runs after compinit further up in this
      # same initContent (home-manager injects compinit at a lower
      # mkOrder, 570, than this file's own plain initContent, 1000 by
      # default -- confirmed against this repo's pinned home-manager
      # source, modules/programs/zsh/default.nix -- so `compdef` below is
      # always called after compinit has defined it). Deliberately not
      # state-perfect (e.g. still offers @name after one was already
      # typed) -- a full argument-position state machine is more machinery
      # than a personal dotfiles completion needs; worse case is one
      # harmless extra suggestion, nothing breaks.
      _agent_sandbox() {
        local conf_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/agent-sandbox/projects"
        local -a names
        local f
        for f in "$conf_dir"/*.conf(N); do
          names+=("@''${f:t:r}")
        done

        if (( CURRENT == 2 )); then
          compadd -- up down status "''${names[@]}"
          return
        fi

        _arguments -s \
          '-C[start in this directory (must be inside the sandbox)]:directory:_files -/' \
          '--gui[Wayland + GPU passthrough]' \
          '--no-tty[never allocate a TTY]' \
          '--gitlab-token[pass GITLAB_TOKEN through]' \
          '*::target:->target'

        if [[ "$state" == target ]]; then
          compadd -- "''${names[@]}"
        fi
      }
      compdef _agent_sandbox agent-sandbox
    '';
    shellAliases = {
      # claude-code in the sandbox that covers the current directory, started
      # right here (bin/agent-sandbox finds the sandbox by cwd).
      sclaude = "agent-sandbox -- claude";
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
