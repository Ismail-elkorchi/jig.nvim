return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = function()
      local cfg = require("jig.nav.config").get()
      local excludes = {}
      for _, glob in ipairs(cfg.ignore_globs or {}) do
        local clean = glob:gsub("^!", "")
        if clean ~= "" then
          table.insert(excludes, clean)
        end
      end
      return {
        picker = {
          enabled = true,
          sources = {
            files = {
              limit = cfg.candidate_cap,
              exclude = excludes,
            },
            recent = {
              limit = cfg.candidate_cap,
            },
            buffers = {
              limit = cfg.candidate_cap,
            },
            diagnostics = {
              limit = cfg.candidate_cap,
            },
            git_status = {
              limit = cfg.candidate_cap,
            },
            command_history = {
              limit = cfg.candidate_cap,
            },
          },
        },
      }
    end,
  },
}
