local brand = require("jig.core.brand")

local M = {}

local valid_profiles = {
  default = true,
  ["high-contrast"] = true,
  ["reduced-decoration"] = true,
  ["reduced-motion"] = true,
}

local function profile()
  local current = vim.g.jig_ui_profile or "default"
  if valid_profiles[current] then
    return current
  end
  return "default"
end

function M.current()
  return profile()
end

function M.is(profile_name)
  return profile() == profile_name
end

function M.apply(profile_name)
  if not valid_profiles[profile_name] then
    return false, "invalid profile: " .. profile_name
  end

  vim.g.jig_ui_profile = profile_name
  vim.g.jig_ui_reduced_motion = profile_name == "reduced-motion"
  vim.g.jig_ui_reduced_decoration = profile_name == "reduced-decoration"
  vim.g.jig_ui_high_contrast = profile_name == "high-contrast"
  return true
end

function M.list()
  return {
    "default",
    "high-contrast",
    "reduced-decoration",
    "reduced-motion",
  }
end

local function complete_profile(arg_lead)
  local matches = {}
  for _, item in ipairs(M.list()) do
    if vim.startswith(item, arg_lead) then
      table.insert(matches, item)
    end
  end
  return matches
end

local function set_profile_command(opts)
  if opts.args == "" then
    vim.notify("Current UI profile: " .. M.current(), vim.log.levels.INFO)
    return
  end

  local ok, err = M.apply(opts.args)
  if not ok then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  require("jig.ui").reapply()
  vim.notify("UI profile set to " .. opts.args, vim.log.levels.INFO)
end

function M.setup_commands()
  -- boundary: allow-vim-api
  -- Justification: user command registration is a Neovim host boundary operation.
  vim.api.nvim_create_user_command(brand.command("UiProfile"), set_profile_command, {
    nargs = "?",
    complete = complete_profile,
    desc = "Set accessibility profile (default|high-contrast|reduced-decoration|reduced-motion)",
  })
end

return M
