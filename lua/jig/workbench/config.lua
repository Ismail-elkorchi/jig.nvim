local M = {}

M.defaults = {
  enabled = true,
  nav_width = 36,
  term_height = 12,
  agent_width = 44,
  nav_cap = 40,
  presets = {
    dev = {
      nav_source = "files",
      terminal = true,
      agent_panel = false,
    },
    review = {
      nav_source = "git_changes",
      terminal = true,
      agent_panel = false,
    },
    agent = {
      nav_source = "files",
      terminal = true,
      agent_panel = true,
    },
    minimal = {
      nav_source = "files",
      terminal = false,
      agent_panel = false,
    },
  },
}

function M.get()
  local cfg = vim.deepcopy(M.defaults)
  if type(vim.g.jig_workbench) == "table" then
    cfg = vim.tbl_deep_extend("force", cfg, vim.g.jig_workbench)
  end
  return cfg
end

function M.resolve_preset(name)
  local cfg = M.get()
  local key = tostring(name or ""):lower()
  if key == "" then
    key = "dev"
  end

  local preset = cfg.presets[key]
  if type(preset) ~= "table" then
    return nil, key, cfg
  end

  return vim.tbl_deep_extend("force", {}, preset), key, cfg
end

function M.preset_names()
  local cfg = M.get()
  local names = {}
  for key, _ in pairs(cfg.presets or {}) do
    names[#names + 1] = key
  end
  table.sort(names)
  return names
end

return M
