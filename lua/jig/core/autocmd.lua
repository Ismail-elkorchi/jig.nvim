-- boundary: allow-vim-api
-- Justification: augroup/autocmd registration is a Neovim host boundary operation.
-- The module remains core because it defines default lifecycle policy.
local brand = require("jig.core.brand")
local aug = vim.api.nvim_create_augroup(brand.augroup("Core"), { clear = true })

vim.api.nvim_create_autocmd("TextYankPost", {
  group = aug,
  callback = function()
    vim.highlight.on_yank({ higroup = "Visual", timeout = 120 })
  end,
})

vim.api.nvim_create_autocmd("VimEnter", {
  group = aug,
  callback = function()
    vim.diagnostic.config({
      virtual_text = false,
      signs = true,
      underline = true,
      update_in_insert = false,
      severity_sort = true,
      float = {
        border = vim.g.jig_ui_float_border_secondary or "rounded",
        source = "if_many",
      },
    })
  end,
})
