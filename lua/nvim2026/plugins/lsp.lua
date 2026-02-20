return {
  {
    "neovim/nvim-lspconfig",
    config = function()
      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            diagnostics = { globals = { "vim" } },
          },
        },
      })

      vim.lsp.config("bashls", {})

      vim.lsp.enable("lua_ls")
      vim.lsp.enable("bashls")
    end,
  },
  {
    "williamboman/mason.nvim",
    opts = {},
    config = true,
  },
}
