local brand = require("jig.core.brand")
local backend = require("jig.nav.backend")
local config = require("jig.nav.config")
local miller = require("jig.nav.miller")
local root = require("jig.nav.root")

local M = {}

local function nav_call(action, opts)
  local path = nil
  if opts and opts.args and opts.args ~= "" then
    path = opts.args
  end

  local context = root.resolve({ path = path })
  local runtime = config.get()
  runtime.select = #vim.api.nvim_list_uis() > 0

  local ok, result = pcall(backend[action], context, runtime)
  if not ok then
    vim.notify("Jig navigation failed: " .. tostring(result), vim.log.levels.ERROR)
    return
  end

  vim.g.jig_nav_last = result
end

local function set_root_command(opts)
  local target = opts.args ~= "" and opts.args or vim.uv.cwd()
  local ok, value = root.set(target)
  if not ok then
    vim.notify(value, vim.log.levels.ERROR)
    return
  end
  vim.notify("Jig root override set: " .. value, vim.log.levels.INFO)
end

local function reset_root_command()
  root.reset()
  vim.notify("Jig root override cleared", vim.log.levels.INFO)
end

local function miller_command(opts)
  local context = root.resolve({ path = opts.args ~= "" and opts.args or nil })
  local ok, state = miller.open({
    root = context.root,
    columns = 3,
    cap = 40,
  })

  if not ok then
    vim.notify(state, vim.log.levels.INFO)
    return
  end

  vim.g.jig_nav_last_miller = state
end

function M.setup()
  vim.api.nvim_create_user_command(brand.command("RootSet"), set_root_command, {
    nargs = "?",
    complete = "dir",
    desc = "Set deterministic root override",
  })

  vim.api.nvim_create_user_command(brand.command("RootReset"), reset_root_command, {
    nargs = 0,
    desc = "Clear deterministic root override",
  })

  vim.api.nvim_create_user_command(brand.command("Files"), function(opts)
    nav_call("files", opts)
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Find files using deterministic root policy",
  })

  vim.api.nvim_create_user_command(brand.command("Buffers"), function(opts)
    nav_call("buffers", opts)
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Find buffers filtered by deterministic root",
  })

  vim.api.nvim_create_user_command(brand.command("Recent"), function(opts)
    nav_call("recent", opts)
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Find recent files filtered by deterministic root",
  })

  vim.api.nvim_create_user_command(brand.command("Symbols"), function(opts)
    nav_call("symbols", opts)
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Find symbols with fallback behavior",
  })

  vim.api.nvim_create_user_command(brand.command("Diagnostics"), function(opts)
    nav_call("diagnostics", opts)
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Find diagnostics with fallback behavior",
  })

  vim.api.nvim_create_user_command(brand.command("History"), function(opts)
    nav_call("history", opts)
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Find command history entries",
  })

  vim.api.nvim_create_user_command(brand.command("GitChanges"), function(opts)
    nav_call("git_changes", opts)
  end, {
    nargs = "?",
    complete = "dir",
    desc = "Find git changes with fallback behavior",
  })

  vim.api.nvim_create_user_command(brand.command("Miller"), miller_command, {
    nargs = "?",
    complete = "dir",
    desc = "Open optional Miller-column navigation mode",
  })
end

return M
