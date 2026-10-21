-- Vendored verbatim from LazyVim/starter -- intentionally empty
-- extension point, not a gap in this work (see design doc).
-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Normal-mode commands in the Russian layout: with langmap, pressing "й" acts
-- as "q", "ш" as "i", and so on, so there is no need to switch the layout to
-- navigate or edit (requested 2026-10-20). Letters only: punctuation entries
-- need escaping and are rarely needed. Insert mode still types Russian.
vim.o.langmap = "ФИСВУАПРШОЛДЬТЩЗЙКЫЕГМЦЧНЯ;ABCDEFGHIJKLMNOPQRSTUVWXYZ,фисвуапршолдьтщзйкыегмцчня;abcdefghijklmnopqrstuvwxyz"
