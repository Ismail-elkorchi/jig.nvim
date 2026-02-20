return {
  {
    "neovim/nvim-lspconfig",
    config = function()
      require("jig.lsp").setup()
    end,
  },
  {
    "williamboman/mason.nvim",
    cmd = { "Mason", "MasonInstall", "MasonUpdate" },
    opts = {},
    config = true,
  },
}
