local icons = require("jig.ui.icons")

local M = {}

local function filename(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return "[No Name]"
  end
  return vim.fn.fnamemodify(name, ":t")
end

local function pending_approvals_segment()
  local pending = tonumber(vim.g.jig_agent_pending_approvals) or 0
  if pending <= 0 then
    return ""
  end
  return string.format(
    " %%#JigUiWarning#%s approvals:%d%%#JigUiNeutral#",
    icons.get("warning"),
    pending
  )
end

function M.render_statusline(active, bufnr)
  local mode_icon = icons.get("action")
  local diag_icon = icons.get("health")
  if active then
    return table.concat({
      "%#JigStatuslineActive# ",
      mode_icon,
      " %#JigUiNeutral# ",
      filename(bufnr),
      pending_approvals_segment(),
      "%m",
      "%r",
      "%=",
      "%#JigUiDiagnostics#",
      diag_icon,
      " %l:%c ",
    })
  end

  return table.concat({
    "%#JigStatuslineInactive# ",
    filename(bufnr),
    pending_approvals_segment(),
    "%m%r",
    "%=",
    "%#JigUiInactive# %l:%c ",
  })
end

function M.render_winbar(active, bufnr)
  local warning_icon = icons.get("warning")
  local pending = tonumber(vim.g.jig_agent_pending_approvals) or 0
  local pending_chunk = pending > 0 and (" " .. warning_icon .. pending) or ""
  if active then
    return table.concat({
      "%#JigWinbarActive# ",
      warning_icon,
      " ",
      filename(bufnr),
      pending_chunk,
      " ",
    })
  end
  return table.concat({
    "%#JigWinbarInactive# ",
    filename(bufnr),
    pending_chunk,
    " ",
  })
end

local function apply_for_window(win, is_active)
  local bufnr = vim.api.nvim_win_get_buf(win)
  local statusline = M.render_statusline(is_active, bufnr)
  local winbar = M.render_winbar(is_active, bufnr)

  vim.api.nvim_set_option_value("statusline", statusline, { win = win })
  vim.api.nvim_set_option_value("winbar", winbar, { win = win })
end

function M.refresh()
  local current = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    apply_for_window(win, win == current)
  end
end

function M.setup()
  local augroup = vim.api.nvim_create_augroup("JigUiChrome", { clear = true })
  vim.api.nvim_create_autocmd({
    "WinEnter",
    "WinLeave",
    "BufWinEnter",
    "BufEnter",
    "ColorScheme",
  }, {
    group = augroup,
    callback = function()
      M.refresh()
    end,
  })
  M.refresh()
end

return M
