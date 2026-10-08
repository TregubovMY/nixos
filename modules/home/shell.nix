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

      # `sclaude`: run from inside any subdirectory of a project and it
      # opens claude-code in whichever agent-sandbox covers it, cd'd to
      # that same subdirectory inside the container -- requested live
      # 2026-10-07 ("write one command in a project subdir, claude opens
      # in the sandbox there"). Matches cwd against every
      # ~/.config/agent-sandbox/projects/*.conf's `dir =` (longest prefix
      # wins, for nested configs), falls back to the git root (or cwd
      # itself outside any repo) as a plain path -- `up` on a bare path
      # works without a config too (docs/AGENT-SANDBOX.md). The actual
      # "open in a subdir" part is bin/agent-sandbox's own `--workdir`
      # flag (built for git worktrees); this just works out which
      # project/config that is and the path relative to its root. `up`
      # before `attach` is idempotent -- a no-op one-liner if already running.
      sclaude() {
        emulate -L zsh
        local cwd="$(pwd -P)"
        local conf_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/agent-sandbox/projects"
        local target="" root="" best_len=0 f d
        for f in "$conf_dir"/*.conf(N); do
          d=$(sed -n 's/^[[:space:]]*dir[[:space:]]*=[[:space:]]*\([^#]*\).*/\1/p' "$f" \
            | head -1 | sed 's/[[:space:]]*$//')
          [ -n "$d" ] || continue
          # Same ~-expansion bin/agent-sandbox's own cfg_path() does.
          case "$d" in
            "~") d="$HOME" ;;
            "~/"*) d="$HOME/''${d#"~/"}" ;;
          esac
          [ -d "$d" ] || continue
          d="$(cd "$d" && pwd -P)"
          case "$cwd" in
            "$d"|"$d"/*)
              [ "''${#d}" -gt "$best_len" ] || continue
              best_len="''${#d}"; root="$d"; target="@''${f:t:r}"
              ;;
          esac
        done
        if [ -z "$target" ]; then
          root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || root="$cwd"
          target="$root"
        fi
        local rel=.
        [ "$cwd" = "$root" ] || rel="''${cwd#$root/}"
        agent-sandbox up "$target"
        if [ "$rel" = . ]; then
          agent-sandbox attach "$target" -- claude
        else
          agent-sandbox attach --workdir "$rel" "$target" -- claude
        fi
      }

      # Tab-completion for agent-sandbox: subcommands, @name configs (read
      # fresh from ~/.config/agent-sandbox/projects/*.conf every time, so a
      # newly added config shows up without a new shell), plain
      # directories, and its flags. Runs after compinit further up in this
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
          compadd -- up attach exec down status "''${names[@]}"
          _files -/
          return
        fi

        _arguments -s \
          '--gui[Wayland + GPU passthrough]' \
          '--workdir[start in a subdirectory of the project]:subdirectory:_files -/' \
          '--no-tty[never allocate a TTY]' \
          '--publish[publish host\:container port]:host\:container' \
          '--gitlab-token[pass GITLAB_TOKEN through]' \
          '--shared-root[directory holds several projects (up only)]' \
          '*::target:->target'

        if [[ "$state" == target ]]; then
          compadd -- "''${names[@]}"
          _files -/
        fi
      }
      compdef _agent_sandbox agent-sandbox
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
