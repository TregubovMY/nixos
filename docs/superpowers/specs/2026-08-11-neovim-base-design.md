# `modules/home/neovim.nix` (base LazyVim) Design

## Goal

Base LazyVim, no Ruby tooling yet (confirmed as a separate later round).
`system-plan.md` §5.3 leaves the base as "LazyVim/kickstart.nvim" — chosen
LazyVim (impure `lazy.nvim`, the standard/popular path), vendored starter
config, verified with a real build the same depth as `shell.nix`.

## What was verified before writing this

Fetched LazyVim's actual `starter` repo files (not assumed):
`init.lua` is one line (`require("config.lazy")`);
`lua/config/lazy.lua` bootstraps `lazy.nvim` itself via `git clone` at
first run (genuinely impure — matches the chosen approach, not a surprise
to work around) and then `require("lazy").setup({ spec = { { "LazyVim/LazyVim",
import = "lazyvim.plugins" }, { import = "plugins" } }, ... })`;
`lua/config/options.lua`/`keymaps.lua`/`autocmds.lua` are comment-only
extension-point stubs, vendored as-is (real upstream content, not a gap in
this work); `lua/plugins/example.lua` is disabled by its own `if true then
return {} end` and not meaningful to vendor — replaced with a real, minimal
`lua/plugins/init.lua` (`return {}`) so `{ import = "plugins" }` resolves
to a real module instead of a missing directory.

## Files

```
modules/home/neovim.nix     # the home-manager module
modules/home/neovim/        # vendored LazyVim starter content
  init.lua
  lua/config/lazy.lua
  lua/config/options.lua
  lua/config/keymaps.lua
  lua/config/autocmds.lua
  lua/plugins/init.lua       # return {} -- Ruby plugin specs land here in
                              # the future Ruby-stack round, not this one
```

`modules/home/neovim.nix`:
```nix
{ pkgs, ... }:
{
  programs.neovim.enable = true;

  # LazyVim's default (non-language-specific) plugin set needs these on
  # PATH at runtime -- not Nix-installed by lazy.nvim/mason, so declared
  # here explicitly: ripgrep (telescope live_grep), fd (telescope
  # find_files), a C compiler (nvim-treesitter compiles parsers at
  # runtime), lazygit (LazyVim's default <leader>gg keymap shells out to
  # it), git (LazyVim's own git integration -- declared here too, not
  # just assumed present via shell.nix, so this module is self-contained
  # if imported without it).
  home.packages = with pkgs; [ ripgrep fd gcc lazygit git ];

  xdg.configFile."nvim" = {
    source = ./neovim;
    recursive = true;
  };
}
```

`home.packages` (not `programs.neovim.extraPackages`) is deliberate:
`extraPackages` wraps them into neovim's own PATH-shim, invisible to
subshells `:!lazygit` etc. spawn from inside neovim; `home.packages` puts
them on the user's actual `$PATH`, which is what LazyVim's own keymaps
(shelling out to `lazygit`) and treesitter (invoking `cc` as a real
external process) need.

## Mason — deliberately undecided this round

LazyVim ships `mason.nvim` as a core plugin regardless of language extras;
with no language extras enabled yet, nothing forces it to download
anything on its own. Whether to disable Mason and route all future
LSP/tool installs through Nix packages instead (the common NixOS pattern)
is a real decision — deferred to the Ruby-stack round, where it first
actually matters (`ruby-lsp`/`rubocop` need to come from *somewhere*).

## Test Host

`hosts/test-neovim/` — mirrors `hosts/test-shell/`'s shape (ext4
`/dev/vda1` + grub, throwaway `testuser`, `home-manager.nix` +
`neovim.nix` via `home-manager.users.testuser`). Real (non-dry-run) build,
same reasoning as `shell.nix`: `xdg.configFile` symlinking and the package
list are real activation-time content.

## Explicitly not verified here

Whether `lazy.nvim`'s first-run plugin install actually succeeds (a real
`git clone` of `folke/lazy.nvim` plus every LazyVim default plugin) is
**not** exercised by this round's build — that's a live, impure, network-
and-time-heavy step, the same category of "can't verify from this sandbox"
as Hyprland's visual check. What's verified: the Nix-side inputs (neovim
+ supporting packages build, the vendored config symlinks in via
home-manager's activation script) are real and correct.

## Out of Scope

- Ruby LSP/rubocop/treesitter/vim-rails/rspec/dap — separate round.
- kitty, direnv/nix-direnv, podman, mise (§5.3) — untouched.
- Colorscheme/UI customization beyond LazyVim's own defaults
  (`tokyonight`/`habamax`) — not requested, no reason to deviate yet.
