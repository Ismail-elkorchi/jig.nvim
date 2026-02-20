local profile = require("jig.ui.profile")

local M = {}

M.groups = {
  diagnostics = "JigUiDiagnostics",
  action = "JigUiAction",
  inactive = "JigUiInactive",
  accent = "JigUiAccent",
  neutral = "JigUiNeutral",
  danger = "JigUiDanger",
  warning = "JigUiWarning",
}

local palettes = {
  default = {
    diagnostics = { fg = "#7dcfff" },
    action = { fg = "#7aa2f7", bold = true },
    inactive = { fg = "#6b7089" },
    accent = { fg = "#bb9af7", bold = true },
    neutral = { fg = "#c0caf5" },
    danger = { fg = "#f7768e", bold = true },
    warning = { fg = "#e0af68", bold = true },
  },
  ["high-contrast"] = {
    diagnostics = { fg = "#00ffff", bold = true },
    action = { fg = "#00ff00", bold = true },
    inactive = { fg = "#808080", bold = true },
    accent = { fg = "#ffffff", bg = "#000000", bold = true },
    neutral = { fg = "#ffffff", bg = "#000000" },
    danger = { fg = "#ff3030", bg = "#000000", bold = true },
    warning = { fg = "#ffff00", bg = "#000000", bold = true },
  },
  ["reduced-decoration"] = {
    diagnostics = { fg = "#89ddff" },
    action = { fg = "#82aaff" },
    inactive = { fg = "#7c7f93" },
    accent = { fg = "#c792ea" },
    neutral = { fg = "#c3ccdc" },
    danger = { fg = "#ff5370" },
    warning = { fg = "#ffcb6b" },
  },
  ["reduced-motion"] = {
    diagnostics = { fg = "#7dcfff" },
    action = { fg = "#7aa2f7" },
    inactive = { fg = "#6b7089" },
    accent = { fg = "#bb9af7" },
    neutral = { fg = "#c0caf5" },
    danger = { fg = "#f7768e" },
    warning = { fg = "#e0af68" },
  },
}

local function palette()
  return palettes[profile.current()] or palettes.default
end

local function set(name, spec)
  -- boundary: allow-vim-api
  -- Justification: highlight groups must be registered through Neovim host API.
  vim.api.nvim_set_hl(0, name, spec)
end

function M.apply()
  local p = palette()

  set(M.groups.diagnostics, p.diagnostics)
  set(M.groups.action, p.action)
  set(M.groups.inactive, p.inactive)
  set(M.groups.accent, p.accent)
  set(M.groups.neutral, p.neutral)
  set(M.groups.danger, p.danger)
  set(M.groups.warning, p.warning)

  set("JigStatuslineActive", { link = M.groups.action })
  set("JigStatuslineInactive", { link = M.groups.inactive })
  set("JigWinbarActive", { link = M.groups.neutral })
  set("JigWinbarInactive", { link = M.groups.inactive })

  set("JigFloatBorderPrimary", { link = M.groups.accent })
  set("JigFloatBorderSecondary", { link = M.groups.neutral })
  set("JigFloatBorderTertiary", { link = M.groups.inactive })
  set("JigFloatTitle", { link = M.groups.action })
end

return M
