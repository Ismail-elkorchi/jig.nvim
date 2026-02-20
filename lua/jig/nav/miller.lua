local config = require("jig.nav.config")

local M = {}

local function dir_entries(path, cap)
  local entries = {}
  for name, kind in vim.fs.dir(path) do
    table.insert(entries, {
      label = kind == "directory" and (name .. "/") or name,
      kind = kind,
      name = name,
      path = path .. "/" .. name,
    })
  end

  table.sort(entries, function(a, b)
    return a.label < b.label
  end)

  local max_items = math.max(1, cap)
  return vim.list_slice(entries, 1, max_items)
end

local function make_column(lines, layout)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = layout.row,
    col = layout.col,
    width = layout.width,
    height = layout.height,
    border = "single",
    style = "minimal",
    zindex = 70,
  })

  return buf, win
end

function M.enabled()
  return config.get().enable_miller == true
end

function M.open(opts)
  opts = opts or {}
  if not M.enabled() then
    return false, "miller mode disabled"
  end

  local root = opts.root
  if type(root) ~= "string" or root == "" then
    return false, "miller root is required"
  end

  local columns = math.max(1, opts.columns or 3)
  local width = math.max(20, math.floor(vim.o.columns / columns) - 2)
  local height = math.max(5, math.floor(vim.o.lines * 0.4))

  local states = {
    windows = {},
    buffers = {},
  }

  local function add_column(path, idx)
    local items = dir_entries(path, opts.cap or 40)
    local lines = { "[" .. path .. "]" }
    for _, item in ipairs(items) do
      table.insert(lines, item.label)
    end

    local _, win = make_column(lines, {
      row = 2,
      col = (idx - 1) * (width + 1) + 2,
      width = width,
      height = height,
    })

    table.insert(states.windows, win)
  end

  add_column(root, 1)

  local first_entries = dir_entries(root, opts.cap or 40)
  local next_dir = nil
  for _, item in ipairs(first_entries) do
    if item.kind == "directory" then
      next_dir = item.path
      break
    end
  end

  if next_dir and columns > 1 then
    add_column(next_dir, 2)
  end

  return true, states
end

function M.close(state)
  if type(state) ~= "table" then
    return
  end
  for _, win in ipairs(state.windows or {}) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
end

return M
