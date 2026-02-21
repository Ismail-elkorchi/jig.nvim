local brand = require("jig.core.brand")

local M = {}

local startup_done = false
local initialized = false

function M.is_startup()
  return not startup_done
end

function M.mark_startup_done(reason)
  startup_done = true
  vim.g.jig_startup_done_reason = reason or "manual"
  vim.g.jig_startup_phase = "done"
end

local function setup_markers()
  -- boundary: allow-vim-api
  -- Justification: startup lifecycle markers require host autocmd registration.
  local aug = vim.api.nvim_create_augroup(brand.augroup("StartupPhase"), { clear = true })

  vim.api.nvim_create_autocmd("VimEnter", {
    group = aug,
    callback = function()
      M.mark_startup_done("VimEnter")
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = aug,
    pattern = "VeryLazy",
    callback = function()
      M.mark_startup_done("User VeryLazy")
    end,
  })
end

function M.setup()
  if initialized then
    return
  end

  startup_done = false
  vim.g.jig_startup_phase = "startup"
  setup_markers()
  initialized = true
end

return M
