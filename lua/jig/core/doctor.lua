local brand = require("jig.core.brand")

local M = {}

local function cmd_verbose_map(opts)
  local lhs = opts.args
  -- boundary: allow-vim-api
  -- Justification: command execution must use Neovim command API for provenance helpers.
  vim.api.nvim_cmd({
    cmd = "verbose",
    args = { "map", lhs },
  }, {})
end

local function cmd_verbose_set(opts)
  local option = opts.args
  -- boundary: allow-vim-api
  -- Justification: command execution must use Neovim command API for provenance helpers.
  vim.api.nvim_cmd({
    cmd = "verbose",
    args = { "set", option .. "?" },
  }, {})
end

local function cmd_health()
  vim.cmd("checkhealth jig")
  vim.cmd("checkhealth provider")
end

local function cmd_bisect_guide()
  vim.notify(
    "Bisect workflow: disable half modules, restart, repeat. See docs/troubleshooting.jig.nvim.md",
    vim.log.levels.INFO
  )
end

function M.setup()
  -- boundary: allow-vim-api
  -- Justification: user command registration is a Neovim host boundary operation.
  vim.api.nvim_create_user_command(brand.command("Health"), cmd_health, {
    desc = "Run Jig and provider health checks",
  })

  vim.api.nvim_create_user_command(brand.command("VerboseMap"), cmd_verbose_map, {
    nargs = 1,
    desc = "Show keymap provenance via :verbose map <lhs>",
  })

  vim.api.nvim_create_user_command(brand.command("VerboseSet"), cmd_verbose_set, {
    nargs = 1,
    desc = "Show option provenance via :verbose set <option>?",
  })

  vim.api.nvim_create_user_command(brand.command("BisectGuide"), cmd_bisect_guide, {
    desc = "Show deterministic bisect guidance",
  })
end

return M
