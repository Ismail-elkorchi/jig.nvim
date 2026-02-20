local M = {}

local function grouped(entries)
  local groups = {}

  for _, entry in ipairs(entries or {}) do
    local discoverability = entry.discoverability or {}
    if discoverability.hidden ~= true then
      local group = discoverability.group or entry.layer or "Other"
      groups[group] = groups[group] or {}
      table.insert(groups[group], entry)
    end
  end

  local order = vim.tbl_keys(groups)
  table.sort(order)

  for _, group in ipairs(order) do
    table.sort(groups[group], function(a, b)
      local left = (a.discoverability and a.discoverability.order) or 999
      local right = (b.discoverability and b.discoverability.order) or 999
      if left == right then
        return a.lhs < b.lhs
      end
      return left < right
    end)
  end

  return groups, order
end

local function render(entries)
  local lines = {
    "Jig Keymaps",
    "",
  }

  local groups, order = grouped(entries)
  for _, group in ipairs(order) do
    table.insert(lines, "[" .. group .. "]")
    for _, entry in ipairs(groups[group]) do
      table.insert(lines, string.format("  %-12s %s", entry.lhs, entry.desc))
    end
    table.insert(lines, "")
  end

  if #lines == 2 then
    table.insert(lines, "No keymaps registered")
  end

  return lines
end

function M.open(entries, opts)
  opts = opts or {}
  local lines = render(entries)
  local width = math.min(math.max(42, opts.width or 72), math.max(42, vim.o.columns - 4))
  local height = math.min(#lines + 2, math.max(8, math.floor(vim.o.lines * 0.7)))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(1, math.floor((vim.o.lines - height) / 2)),
    col = math.max(1, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    border = "rounded",
    style = "minimal",
    title = "Jig Keys",
    title_pos = "left",
    zindex = 85,
  })

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true, noremap = true })

  return {
    buf = buf,
    win = win,
    lines = lines,
  }
end

function M.close(state)
  if type(state) ~= "table" then
    return
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
end

return M
