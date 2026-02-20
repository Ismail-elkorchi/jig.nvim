return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      vim.cmd.colorscheme("tokyonight-night")
    end,
  },
  {
    "nvim-mini/mini.icons",
    opts = function()
      return { style = vim.g.have_nerd_font and "glyph" or "ascii" }
    end,
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "modern",
      delay = 200,
      icons = {
        mappings = vim.g.have_nerd_font,
      },
      win = {
        border = "rounded",
      },
    },
  },
}
