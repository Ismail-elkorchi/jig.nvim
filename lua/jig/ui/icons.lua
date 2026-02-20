local M = {}

local nerd_icons = {
  health = "󰓙",
  warning = "",
  danger = "",
  neutral = "",
  action = "",
}

local ascii_icons = {
  health = "H",
  warning = "!",
  danger = "X",
  neutral = "*",
  action = ">",
}

local valid_modes = {
  auto = true,
  nerd = true,
  ascii = true,
}

local function resolved_mode()
  local configured = vim.g.jig_icon_mode or "auto"
  if configured == "auto" then
    return vim.g.have_nerd_font and "nerd" or "ascii"
  end
  if valid_modes[configured] then
    return configured
  end
  return "ascii"
end

function M.mode()
  return resolved_mode()
end

function M.set_mode(mode)
  if not valid_modes[mode] then
    return false
  end
  vim.g.jig_icon_mode = mode
  return true
end

function M.get(name)
  if resolved_mode() == "nerd" then
    return nerd_icons[name] or nerd_icons.neutral
  end
  return ascii_icons[name] or ascii_icons.neutral
end

function M.ascii_only(text)
  for i = 1, #text do
    if text:byte(i) > 127 then
      return false
    end
  end
  return true
end

return M
