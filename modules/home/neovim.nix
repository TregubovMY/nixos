# Base LazyVim, see docs/superpowers/specs/2026-08-11-neovim-base-design.md.
# Ruby stack (LSP/rubocop/treesitter/vim-rails/rspec/dap) added on top,
# see docs/superpowers/specs/2026-08-12-neovim-ruby-design.md. Vendored
# starter config under ./neovim/ (fetched fresh from LazyVim/starter, not
# assumed -- see design doc "What was verified before writing this"), not
# live-referenced -- same vendor-not-live-reference precedent as
# modules/nixos/secure-boot-test/. Genuinely impure at runtime:
# lua/config/lazy.lua bootstraps lazy.nvim itself via `git clone` on
# first launch, then lazy.nvim clones every LazyVim default plugin. Not
# worked around -- that's the accepted tradeoff of choosing LazyVim
# (requested) over a fully-declarative alternative like nixvim.
{ pkgs, ... }:
{
  programs.neovim.enable = true;

  # LazyVim's default (non-language-specific) plugin set needs these on
  # PATH at runtime -- not installed by lazy.nvim/mason, so declared here
  # explicitly: ripgrep (telescope live_grep), fd (telescope find_files),
  # a C compiler (nvim-treesitter compiles parsers at runtime), lazygit
  # (LazyVim's default <leader>gg keymap shells out to it), git (LazyVim's
  # own git integration -- declared here too, not just assumed present
  # via shell.nix, so this module is self-contained if imported alone).
  #
  # home.packages, not programs.neovim.extraPackages: extraPackages wraps
  # these into neovim's own PATH-shim, invisible to subshells `:!lazygit`
  # etc. spawn from inside neovim; home.packages puts them on the user's
  # real $PATH, which is what LazyVim's keymaps and treesitter actually
  # need.
  #
  # ruby-lsp/rubocop: deliberately Nix, not Mason -- see
  # docs/superpowers/specs/2026-08-12-neovim-ruby-design.md "Decision:
  # Mason vs Nix". lua/plugins/ruby.lua sets `mason = false` on both
  # server entries so nvim-lspconfig resolves them from $PATH instead of
  # mason-lspconfig auto-installing them.
  home.packages = with pkgs; [ ripgrep fd gcc lazygit git ruby-lsp rubocop ];

  xdg.configFile."nvim" = {
    source = ./neovim;
    recursive = true;
  };
}
