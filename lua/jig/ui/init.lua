local brand = require("jig.core.brand")
local profile = require("jig.ui.profile")
local tokens = require("jig.ui.tokens")
local chrome = require("jig.ui.chrome")
local icons = require("jig.ui.icons")
local cmdline = require("jig.ui.cmdline")
local float = require("jig.ui.float")

local M = {}

local function set_icon_mode_command(opts)
  if opts.args == "" then
    vim.notify("Current icon mode: " .. icons.mode(), vim.log.levels.INFO)
    return
  end

  if not icons.set_mode(opts.args) then
    vim.notify("Invalid icon mode: " .. opts.args .. " (use auto|nerd|ascii)", vim.log.levels.ERROR)
    return
  end

  M.reapply()
  vim.notify("Icon mode set to " .. opts.args, vim.log.levels.INFO)
end

function M.reapply()
  vim.g.jig_ui_float_border_secondary = float.border("secondary")
  tokens.apply()
  chrome.refresh()
  vim.diagnostic.config({
    float = {
      border = vim.g.jig_ui_float_border_secondary,
      source = "if_many",
    },
  })
end

function M.setup()
  profile.apply(vim.g.jig_ui_profile or "default")
  profile.setup_commands()
  cmdline.setup()
  M.reapply()
  chrome.setup()

  -- boundary: allow-vim-api
  -- Justification: user command registration is a Neovim host boundary operation.
  vim.api.nvim_create_user_command(brand.command("IconMode"), set_icon_mode_command, {
    nargs = "?",
    complete = function(arg_lead)
      local modes = { "auto", "nerd", "ascii" }
      local out = {}
      for _, item in ipairs(modes) do
        if vim.startswith(item, arg_lead) then
          table.insert(out, item)
        end
      end
      return out
    end,
    desc = "Set icon mode (auto|nerd|ascii)",
  })

  vim.api.nvim_create_user_command(brand.command("CmdlineCheck"), function()
    local ok = cmdline.open_close_check()
    if ok then
      vim.notify("Cmdline open/close check passed", vim.log.levels.INFO)
      return
    end
    vim.notify("Cmdline open/close check failed", vim.log.levels.ERROR)
  end, {
    desc = "Verify native ':' cmdline opens and closes cleanly",
  })

  vim.api.nvim_create_user_command(brand.command("FloatDemo"), function()
    float.open({
      "Jig float policy demo",
      "border hierarchy + elevation + collision",
    }, {
      level = "primary",
      title = "Primary",
      width = 42,
      height = 4,
      row = 2,
      col = 6,
      enter = false,
    })

    float.open({ "Second float (collision shifted)" }, {
      level = "secondary",
      title = "Secondary",
      width = 38,
      height = 3,
      row = 2,
      col = 6,
      enter = false,
    })
  end, {
    desc = "Open demo floats using Jig float design policy",
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("JigUiTokens", { clear = true }),
    callback = function()
      M.reapply()
    end,
  })
end

return M
