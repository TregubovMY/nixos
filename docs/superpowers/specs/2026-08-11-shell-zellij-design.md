# `modules/home/shell.nix` + `zellij.nix` Design

## Goal

Add the first real `modules/home/*` content (home-manager dotfiles):
`shell.nix` (zsh + starship + eza + git config/aliases) and `zellij.nix`
(a terminal multiplexer, substituted for the `tmux` originally listed in
`system-plan.md` §5.3/§3 — see "Tool substitution" below). Verified with a
real (non-dry-run) build against a throwaway host, same rigor as the
home-manager infrastructure round — this content actually activates
(writes dotfiles, installs aliases), unlike the Hyprland round's
module-only scope.

Explicitly out of scope, confirmed with the human partner before writing
this spec: **neovim** (§5.3's LazyVim/kickstart.nvim + Ruby LSP/rubocop/
treesitter/vim-rails/rspec/dap stack) — substantially larger than
shell+zellij, a separate future round. Also out of scope: kitty (terminal
emulator), direnv/nix-direnv, podman, mise — all named in §5.3 but not
selected for this round; genuine gaps, not forgotten, left for later.

## Tool substitution: zellij instead of tmux

`system-plan.md` §3's aspirational file tree and §5.3's package list both
say `tmux` (+ `tpm`, `tmux-resurrect`, `tmux-continuum`,
`vim-tmux-navigator`). Human partner requested a newer, more popular
alternative instead — **Zellij** chosen over WezTerm (WezTerm is a
terminal emulator with built-in multiplexing, a different class of tool
that would also replace `kitty`, not a narrow tmux swap). Zellij has a
native home-manager module (`programs.zellij`, confirmed present in this
repo's pinned `home-manager` rev) — no plugin-manager equivalent needed;
zellij's plugin system is WASM-based and mostly unnecessary for a default
setup, unlike tmux's TPM/resurrect/continuum stack that §5.3 explicitly
called out. `modules/home/tmux.nix` in §3's structure becomes
`modules/home/zellij.nix`; this design doc's own documentation task
corrects both §3 and §5.3 to reflect the substitution.

## Research findings — verified against this repo's pinned `home-manager`, not assumed

Same discipline as every prior round's package/option verification
(`jetbrains.ruby-mine`, `qt6ct`, `programs.hyprland`'s real defaults).
Checked by evaluating a real `nixosSystem` with `home-manager.nixosModules.home-manager`
and reading the actual module source at this repo's locked
`home-manager` rev (`c30c7955c...`, from `flake.lock`).

- **`programs.eza.enableZshIntegration = true` already generates
  `ls`/`ll`/`la`/`lt`/`lla` shell aliases** (confirmed by reading
  `modules/programs/eza.nix`'s `aliases` attrset directly) — no need to
  hand-write ls-replacement aliases in `shell.nix`.
- **`programs.git.aliases` and `programs.git.extraConfig` are obsolete**
  in this repo's pinned home-manager — a real eval produced "Obsolete
  option ... renamed to `programs.git.settings.alias`" /
  "... `programs.git.settings`" warnings. The current, non-obsolete shape
  is a single `programs.git.settings` attrset covering both aliases and
  arbitrary git config sections (`init.defaultBranch`, `pull.rebase`,
  etc.) — used directly, not the deprecated split options.
- **`programs.starship`'s zsh integration auto-enables** once
  `programs.zsh.enable = true` (its `enableZshIntegration` default reads
  `config.home.shell.enableZshIntegration`, home-manager's global
  per-shell integration toggle) — confirmed by evaluating a config with
  only `programs.zsh.enable`/`programs.starship.enable` set and reading
  back `programs.starship.enableZshIntegration`, which came back `true`
  with no explicit setting. No extra option needed in `shell.nix`.
- **`programs.zellij.enableZshIntegration` defaults to `false`** — its
  own module hardcodes this via a locally-defined
  `mkShellIntegrationOption` helper (distinct from the global
  `home.shell.enableZshIntegration`-driven default `starship` uses) —
  confirmed by reading `modules/programs/zellij.nix` directly. Auto-attach
  behavior stays opt-in, matching the design decision below; setting it
  explicitly in `zellij.nix` documents the choice rather than leaving it
  silently implicit.

## `modules/home/shell.nix`

```nix
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
    enableZshIntegration = true;
    git = true; # adds --git to the generated `eza` alias -- shows git
      # status markers (modified/untracked/etc.) inline in listings
  };

  programs.starship.enable = true; # zsh integration auto-enables, see
    # Research findings above -- default prompt preset, no custom
    # starship.toml content yet; a reasonable place to iterate later.

  programs.git = {
    enable = true;
    settings = {
      alias = {
        co = "checkout";
        br = "branch";
        st = "status";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };
}
```

**Deliberately no `programs.git.settings.user`** (`name`/`email`) — that's
real personal identity, same boundary every other piece of host/user-
specific data already has in this repo (SSH host key, GPG key, hostname,
`users.users.*`). Git already prompts clearly the first time it's needed
without one; a placeholder identity here would be worse than an honest
gap. Real value gets set once a real `home-manager.users.<name>` exists
for `hosts/mimir/`.

## `modules/home/zellij.nix`

```nix
{ ... }:
{
  programs.zellij = {
    enable = true;
    # Matches the upstream default (false) -- set explicitly so the
    # decision is documented, not silently implicit. Auto-attaching to an
    # existing session on every new shell (what enableZshIntegration
    # turns on) is a common tmux-adjacent annoyance/surprise; opt-in
    # later if actually wanted, not a default someone has to discover by
    # reading zellij.nix's source.
    enableZshIntegration = false;
  };
}
```

No custom `programs.zellij.settings` (KDL config) yet — upstream's
default keybinds/theme are a reasonable starting point; this round proves
the plumbing and gives a real, usable multiplexer, not a fully bespoke
config.

## Test Host

```
hosts/test-shell/
  configuration.nix   # mirrors hosts/test-home-manager/'s shape: ext4
                       # /dev/vda1 + grub, throwaway testuser, no
                       # qemu-vm.nix
```
Imports `modules/nixos/boot.nix` + `modules/nixos/home-manager.nix` +
`modules/home/shell.nix` + `modules/home/zellij.nix` (the latter two via
`home-manager.users.testuser`). A new host, not an extension of
`hosts/test-home-manager/` — keeps that host as the pure "infra only, no
content" proof its own header comment already documents, unmutated.

## Testing — why a real build, not dry-run

Same reasoning as the home-manager infrastructure round: this content has
real activation-time behavior (shell alias files, `starship.toml`,
`.gitconfig`, zellij config all get written by home-manager's activation
script), unlike the Hyprland round's module-only scope which had nothing
to activate. A real `nix build .#nixosConfigurations.test-shell.config.system.build.toplevel`
(no `--dry-run`) confirms the whole chain — option resolution, package
availability, activation-script generation — actually builds, not just
evaluates.

1. `nix flake check --no-build` — eval-only, routine after every edit.
2. `nix build .#nixosConfigurations.test-shell.config.system.build.toplevel`
   — real build, same depth as the home-manager infrastructure round's
   own Task 2.

No VM boot: confirming the *activated* dotfiles look/feel right (does the
prompt render, do the aliases actually work interactively) needs a real
login shell, which this sandbox can't meaningfully provide any more than
it could visually verify Hyprland — a human-only check once this lands on
`hosts/mimir/`'s real user.

## Out of Scope

- **neovim** (`modules/home/neovim.nix`) — LazyVim/kickstart.nvim base +
  Ruby LSP/rubocop/treesitter/vim-rails/rspec/dap. Confirmed as a
  separate, later round with the human partner — substantially larger
  than shell+zellij combined.
- kitty, direnv/nix-direnv, podman, mise (all §5.3) — genuine remaining
  gaps, not selected for this round.
- `apps.nix` (§3's "весь список GUI-софта" — largely already covered by
  `modules/nixos/desktop-apps.nix` at the system level; whether anything
  meaningful remains for a home-manager-level `apps.nix` is undetermined,
  not this round's concern).
- Real git identity (`user.name`/`user.email`) and any per-user
  `home-manager.users.<name>` block on `hosts/mimir/` — real-install-time
  step, unchanged boundary from every prior round.
