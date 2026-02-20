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
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = function()
      local nerd = vim.g.have_nerd_font == true
      return {
        options = {
          theme = "auto",
          globalstatus = true,
          icons_enabled = nerd,
          section_separators = nerd and { left = "", right = "" }
            or { left = "", right = "" },
          component_separators = nerd and { left = "", right = "" }
            or { left = "|", right = "|" },
        },
      }
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
