local brand = require("jig.core.brand")

local M = {}

M.minimum_version = "0.11.2"

local function current_appname()
  local value = vim.env.NVIM_APPNAME
  if value == nil or value == "" then
    return "nvim"
  end
  return value
end

function M.is_safe_profile(appname)
  return appname == brand.safe_appname
end

local function set_runtime_flags(appname)
  local safe = M.is_safe_profile(appname)
  vim.g.jig_appname = appname
  vim.g.jig_profile = safe and "safe" or "default"
  vim.g.jig_safe_profile = safe
end

local function fail_version_gate()
  local message = string.format(
    "%s requires Neovim >= %s. Current version: %s",
    brand.brand,
    M.minimum_version,
    vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch
  )

  -- boundary: allow-vim-api
  -- Justification: deterministic startup diagnostics must use host error channel.
  vim.api.nvim_echo({ { message, "ErrorMsg" } }, true, { err = true })
  vim.g.jig_boot_ok = false
  vim.cmd("cquit 1")
end

function M.bootstrap()
  if vim.fn.has("nvim-" .. M.minimum_version) ~= 1 then
    fail_version_gate()
    return false
  end

  set_runtime_flags(current_appname())
  vim.g.jig_boot_ok = true
  return true
end

return M
