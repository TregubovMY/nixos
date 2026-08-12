# `modules/home/neovim.nix` (Ruby stack) Design

## Goal

Full Ruby support on top of the base LazyVim module (see
`docs/superpowers/specs/2026-08-11-neovim-base-design.md`), which
explicitly deferred this: LSP + rubocop + treesitter + `vim-rails` +
rspec (via neotest) + DAP. Confirmed scope with the user (2026-08-12):
full LazyVim `lang.ruby` extra, not the bare-minimum LSP-only subset.

## Decision: Mason vs Nix for `ruby_lsp`/`rubocop`

The base design doc left this "deliberately undecided this round" — it's
decided now, per user confirmation: **Nix, not Mason.** `ruby-lsp`
(0.26.3) and `rubocop` (1.80.2) are both top-level nixpkgs packages,
installed via `home.packages` (same pattern as `ripgrep`/`fd`/`gcc`/
`lazygit`/`git` in the base module — real `$PATH`, not
`programs.neovim.extraPackages`'s neovim-only PATH-shim, for the same
reason: LazyVim's own keymaps/conform/lspconfig invocations need them on
the actual `$PATH`).

Mechanism: fetched LazyVim core's actual
`lua/lazyvim/plugins/lsp/init.lua` (not assumed) — each server entry in
`opts.servers` accepts a `mason` field; `sopts.mason ~= false` gates
whether `mason-lspconfig` auto-installs it. Setting `mason = false` on a
server leaves it configured via `nvim-lspconfig` as normal (which
resolves the binary via `$PATH` by default) while excluding it from
Mason's install list. This is server-scoped, not a global Mason
disable — `mason.nvim`/`mason-lspconfig.nvim` stay as dependencies of
`nvim-lspconfig` (still used for `lua_ls`, untouched, out of scope here).

ERB tooling (`erb-formatter`/`erb-lint`, Mason-installed in LazyVim's
stock ruby extra) is dropped: `erb-lint` isn't in nixpkgs at all, ERB was
never in this round's stated scope (`Ruby LSP/rubocop/treesitter/
vim-rails/rspec/dap` — see base design doc's "Out of Scope"), and mixing
one Mason-installed tool back in after deciding "route through Nix"
defeats the point. If ERB/Rails-template editing turns out to matter
later, that's a separate follow-up.

## What was verified before writing this

Fetched LazyVim's actual `lua/lazyvim/plugins/extras/lang/ruby.lua` (not
assumed): confirms the LSP server is `ruby_lsp` (or `solargraph`, not
used here) via `vim.g.lazyvim_ruby_lsp`, formatter is `rubocop` (or
`standardrb`, not used here) via `vim.g.lazyvim_ruby_formatter`, both
default and left un-overridden; treesitter `ruby` parser via
`ensure_installed`; DAP via `mfussenegger/nvim-dap`'s optional
`suketa/nvim-dap-ruby` dependency; rspec via `nvim-neotest/neotest`'s
optional `olimorris/neotest-rspec` dependency — all of these are
lazy.nvim-managed plugins (git-cloned by `lazy.nvim` itself, same
accepted impurity as the base module's `lazy.nvim`/LazyVim bootstrap),
not Nix packages, so nothing further to declare for them.
`nvim-dap-ruby`/`neotest-rspec` shell out to the target *project's* Ruby
(`bundle exec rspec`, a debug gem, etc.) at runtime — a per-project
concern already out of this module's scope (same boundary as `mise`
handling per-project runtime versions elsewhere in this repo), not
something this module pins.

`vim-rails` (`tpope/vim-rails`) isn't part of LazyVim's ruby extra at
all (checked upstream — the extra covers LSP/format/test/debug, not
Rails-specific navigation) — added separately as a plain plugin spec per
the user's explicit "full" scope choice.

## Files

```
modules/home/neovim.nix          # + ruby-lsp, rubocop on home.packages
modules/home/neovim/
  lua/plugins/ruby.lua            # new — the actual Ruby stack changes
```

`lua/plugins/ruby.lua`:
```lua
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
```

New file rather than extending `lua/plugins/init.lua` (which the base
design doc's own comment flagged as where "Ruby plugin specs land") —
one file per concern matches this repo's existing precedent
(`hyprland.lua` for the Crow Translate hotkey, §5.11) and keeps the
Ruby-specific diff self-contained; `lazy.nvim`'s `{ import = "plugins" }`
already imports every file under `lua/plugins/`, not just `init.lua`, so
this needs no other wiring.

`modules/home/neovim.nix` gains only:
```nix
home.packages = with pkgs; [ ripgrep fd gcc lazygit git ruby-lsp rubocop ];
```

## Test Host

Reuses `hosts/test-neovim/` (already imports `modules/home/neovim.nix`
directly — no new throwaway host needed, this round only adds files
under the same module). Real (non-dry-run) build:
```
nix build .#nixosConfigurations.test-neovim.config.system.build.toplevel
```
Proves: `ruby-lsp`/`rubocop` derivations build, and the vendored
`lua/plugins/ruby.lua` symlinks in via the same `xdg.configFile.nvim`
mechanism as the rest of the vendored config.

## Explicitly not verified here

Same category as the base round: whether `lazy.nvim` actually
successfully clones `LazyVim/LazyVim`'s ruby extra module, `tpope/
vim-rails`, `suketa/nvim-dap-ruby`, `olimorris/neotest-rspec` on first
launch, and whether `ruby_lsp`/`rubocop` actually attach correctly
against a real Ruby/Rails project — live, impure, network-and-project
dependent, out of what this sandbox build can prove.

## Out of Scope

- ERB tooling (`erb-formatter`/`erb-lint`) — see "Decision" above.
- `solargraph`/`standardrb` (LazyVim's alternative LSP/formatter) — not
  requested, `ruby_lsp`/`rubocop` are LazyVim's own defaults.
- Pinning a Ruby interpreter/version for projects — that's `mise`'s job
  (`modules/home/mise.nix`), not this module's.
- Rails generators/scaffolding UI beyond what `vim-rails` itself
  provides out of the box — not requested.
