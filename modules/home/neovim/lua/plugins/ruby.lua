-- Ruby stack -- see
-- docs/superpowers/specs/2026-08-12-neovim-ruby-design.md. Imports
-- LazyVim's own lang.ruby extra as-is (ruby_lsp + rubocop LSP/formatter,
-- treesitter ruby parser, nvim-dap-ruby, neotest-rspec -- all fetched
-- and confirmed against the real upstream file before writing this, see
-- design doc "What was verified before writing this"), then overrides
-- just the two servers it configures to skip Mason (ruby-lsp/rubocop
-- come from Nix, see neovim.nix's home.packages) -- `mason = false`
-- excludes a server from mason-lspconfig's auto-install list without
-- touching how nvim-lspconfig sets it up (still resolves the binary via
-- $PATH). vim-rails isn't part of LazyVim's ruby extra (checked
-- upstream) -- added separately, plain lazy.nvim plugin spec.
return {
  { import = "lazyvim.plugins.extras.lang.ruby" },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ruby_lsp = { mason = false },
        rubocop = { mason = false },
      },
    },
  },
  { "tpope/vim-rails" },
}
