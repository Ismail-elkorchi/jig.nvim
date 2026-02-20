local profile = require("jig.ui.profile")

local M = {}

local border_styles = {
  default = {
    primary = "rounded",
    secondary = "single",
    tertiary = "rounded",
  },
  ["high-contrast"] = {
    primary = "double",
    secondary = "single",
    tertiary = "single",
  },
  ["reduced-decoration"] = {
    primary = "none",
    secondary = "none",
    tertiary = "none",
  },
  ["reduced-motion"] = {
    primary = "rounded",
    secondary = "single",
    tertiary = "rounded",
  },
}

local elevation = {
  primary = {
    zindex = 90,
    winhighlight = "FloatBorder:JigFloatBorderPrimary,FloatTitle:JigFloatTitle",
  },
  secondary = {
    zindex = 80,
    winhighlight = "FloatBorder:JigFloatBorderSecondary,FloatTitle:JigFloatTitle",
  },
  tertiary = {
    zindex = 70,
    winhighlight = "FloatBorder:JigFloatBorderTertiary,FloatTitle:JigFloatTitle",
  },
}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function as_number(value)
  if type(value) == "table" then
    return math.floor(value[false] or value[1] or 0)
  end
  return math.floor(value or 0)
end

function M.border(level)
  local p = profile.current()
  local styles = border_styles[p] or border_styles.default
  return styles[level] or styles.secondary
end

function M.elevation(level)
  return elevation[level] or elevation.secondary
end

local function intersects(a, b)
  return a.row < b.row + b.height
    and b.row < a.row + a.height
    and a.col < b.col + b.width
    and b.col < a.col + a.width
end

function M.resolve(spec)
  local lines = vim.o.lines
  local columns = vim.o.columns
  local level = spec.level or "secondary"
  local width = clamp(spec.width or math.floor(columns * 0.5), 20, columns - 4)
  local height = clamp(spec.height or math.floor(lines * 0.3), 3, lines - 4)
  local row = clamp(spec.row or math.floor((lines - height) / 2), 1, lines - height - 1)
  local col = clamp(spec.col or math.floor((columns - width) / 2), 1, columns - width - 1)

  local candidate = {
    row = row,
    col = col,
    width = width,
    height = height,
  }

  -- Collision policy: for editor-relative floats, shift down on overlap with existing floats.
  if (spec.relative or "editor") == "editor" then
    local existing = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local conf = vim.api.nvim_win_get_config(win)
      if conf.relative ~= "" then
        table.insert(existing, {
          row = as_number(conf.row),
          col = as_number(conf.col),
          width = conf.width,
          height = conf.height,
        })
      end
    end

    for _ = 1, 8 do
      local collided = false
      for _, other in ipairs(existing) do
        if intersects(candidate, other) then
          candidate.row = clamp(other.row + other.height + 1, 1, lines - height - 1)
          collided = true
          break
        end
      end
      if not collided then
        break
      end
    end
  end

  local style = M.elevation(level)
  return {
    relative = spec.relative or "editor",
    row = candidate.row,
    col = candidate.col,
    width = candidate.width,
    height = candidate.height,
    border = M.border(level),
    zindex = style.zindex,
    style = "minimal",
    title = spec.title,
    title_pos = spec.title and "left" or nil,
  },
    style
end

function M.open(lines, spec)
  spec = spec or {}
  local config, style = M.resolve(spec)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local win = vim.api.nvim_open_win(buf, spec.enter == true, config)
  vim.api.nvim_set_option_value("winhighlight", style.winhighlight, { win = win })
  return buf, win
end

return M
