-- boundary: allow-vim-api
-- Justification: user command registration is a Neovim host boundary operation.
local brand = require("jig.core.brand")
local panel = require("jig.core.keymap_panel")
local registry = require("jig.core.keymap_registry")

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

local entries = registry.defaults({ safe_profile = vim.g.jig_safe_profile == true })
registry.apply(entries)

vim.api.nvim_create_user_command(brand.command("Keys"), function()
  local state = panel.open(entries)
  vim.g.jig_keys_last_panel = state
end, {
  desc = "Show keymap registry index",
})
