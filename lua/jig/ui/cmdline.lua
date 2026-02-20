local M = {}

function M.setup()
  -- Baseline-safe default: do not hijack ":" cmdline with UI overlays.
  vim.g.jig_cmdline_mode = "native"
end

function M.open_close_check()
  local has_ui = #vim.api.nvim_list_uis() > 0

  local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "n", false)
  end

  press(":")
  local entered_cmdline = vim.wait(200, function()
    return vim.fn.mode() == "c"
  end, 25)
  local open_ok = entered_cmdline or not has_ui

  press("<Esc>")
  local close_ok = vim.wait(200, function()
    return vim.fn.mode() == "n"
  end, 25)

  return open_ok and close_ok, {
    open_ok = open_ok,
    close_ok = close_ok,
  }
end

return M
