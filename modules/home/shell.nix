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
    historySubstringSearch = {
      enable = true;
      # Up/Down search the history for what is already typed. home-manager's
      # default binds only "^[[A"/"^[[B" (normal cursor mode), but zsh puts
      # the terminal into application cursor mode (terminfo smkx) while the
      # line editor runs, and then Ghostty sends "^[OA"/"^[OB" -- the binding
      # silently never fired ("поиск по командам сломался", 2026-10-20). Bind
      # both forms. Not verified live: written in a sandbox without the host
      # session; if Up still just walks the history, run `cat -v` and press Up
      # to see which sequence your terminal sends.
      searchUpKey = [ "^[[A" "^[OA" ];
      searchDownKey = [ "^[[B" "^[OB" ];
    };
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

    '';
    shellAliases = {
      # Same reason as in bin/ai: an interactive `claude` must be the account
      # wrapper even when mise's node dir (first in PATH) holds its own copy.
      claude = "/run/current-system/sw/bin/claude";
      # ai (bin/ai): claude on the host; `aiv` the same in the agent VM
      # (agent-vm, folder must be in agentVm.mounts). Sessions are shared.
      # (sclaude/ais/aih and the agent-sandbox completion went with the
      # sandbox to the `agent-sandbox` branch, 2026-11-02.)
      aiv = "ai --vm";
      ".." = "cd ..";
      "..." = "cd ../..";
      gs = "git status";
      gc = "git commit";
      gp = "git push";
      gl = "git pull";
      gd = "git diff";
    };
  };

  # fzf key bindings for zsh: Ctrl+R = fuzzy search of the whole command history
  # (type a few letters of any part of the command, Enter inserts it), Ctrl+T =
  # pick a file, Alt+C = cd into a directory. fzf was already installed
  # (base.nix, used by zoxide's `zi`); this only adds the zsh integration.
  # Works in the English layout only: Ctrl+Cyrillic reaches the terminal as no
  # control code (see docs/DAILY-WORKFLOW.md, "Русская раскладка").
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
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
