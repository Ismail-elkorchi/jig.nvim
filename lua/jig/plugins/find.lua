return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      picker = {
        enabled = true,
      },
    },
    keys = {
      {
        "<leader><leader>",
        function()
          require("snacks").picker.files()
        end,
        desc = "Find files",
      },
      {
        "<leader>/",
        function()
          require("snacks").picker.grep()
        end,
        desc = "Grep",
      },
      {
        "<leader>fb",
        function()
          require("snacks").picker.buffers()
        end,
        desc = "Buffers",
      },
      {
        "<leader>fh",
        function()
          require("snacks").picker.help()
        end,
        desc = "Help tags",
      },
    },
  },
}
