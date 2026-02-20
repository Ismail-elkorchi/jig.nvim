local brand = require("jig.core.brand")

local M = {}

local state = {
  lazypath = nil,
  bootstrap_command = brand.command("PluginBootstrap"),
}

local function lockfile_path()
  return vim.fn.stdpath("config") .. "/lazy-lock.json"
end

local function rollback_path()
  return vim.fn.stdpath("state") .. "/jig/lazy-lock.previous.json"
end

local function file_exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

local function copy_file(src, dst)
  local content = vim.fn.readfile(src, "b")
  vim.fn.mkdir(vim.fn.fnamemodify(dst, ":h"), "p")
  vim.fn.writefile(content, dst, "b")
end

local function lazy_available()
  return state.lazypath ~= nil and file_exists(state.lazypath)
end

local function require_lazy_or_prompt()
  if lazy_available() then
    return true
  end

  vim.notify(
    "lazy.nvim not installed. Run :" .. state.bootstrap_command .. " first.",
    vim.log.levels.WARN
  )
  return false
end

local function backup_lockfile()
  local lockfile = lockfile_path()
  if not file_exists(lockfile) then
    return false
  end
  copy_file(lockfile, rollback_path())
  return true
end

function M.install()
  if not lazy_available() then
    vim.cmd(state.bootstrap_command)
    return
  end
  vim.cmd("Lazy sync")
end

function M.restore()
  if not require_lazy_or_prompt() then
    return
  end
  vim.cmd("Lazy restore")
end

function M.update()
  if not require_lazy_or_prompt() then
    return
  end

  vim.cmd("Lazy check")
  local choice = vim.fn.confirm("Apply plugin updates?", "&Apply\n&Cancel", 2)
  if choice ~= 1 then
    vim.notify("Plugin update cancelled", vim.log.levels.INFO)
    return
  end

  if backup_lockfile() then
    vim.notify("Lockfile backup saved to " .. rollback_path(), vim.log.levels.INFO)
  else
    vim.notify("No lazy-lock.json found; continuing update without backup", vim.log.levels.WARN)
  end

  vim.cmd("Lazy update")
end

function M.rollback()
  if not require_lazy_or_prompt() then
    return
  end

  local backup = rollback_path()
  local lockfile = lockfile_path()
  if not file_exists(backup) then
    vim.notify("No rollback lockfile found at " .. backup, vim.log.levels.ERROR)
    return
  end

  copy_file(backup, lockfile)
  vim.notify("Rollback lockfile restored to " .. lockfile, vim.log.levels.INFO)
  vim.cmd("Lazy restore")
end

function M.register(opts)
  opts = opts or {}
  if opts.lazypath then
    state.lazypath = opts.lazypath
  end
  if opts.bootstrap_command and opts.bootstrap_command ~= "" then
    state.bootstrap_command = opts.bootstrap_command
  end

  local commands = {
    {
      name = brand.command("PluginInstall"),
      fn = M.install,
      desc = "Install/sync plugins from lock state",
    },
    {
      name = brand.command("PluginUpdate"),
      fn = M.update,
      desc = "Preview then apply plugin updates (explicit confirm)",
    },
    {
      name = brand.command("PluginRestore"),
      fn = M.restore,
      desc = "Restore plugins from lazy-lock.json",
    },
    {
      name = brand.command("PluginRollback"),
      fn = M.rollback,
      desc = "Restore previous lockfile backup and run Lazy restore",
    },
  }

  for _, command in ipairs(commands) do
    -- boundary: allow-vim-api
    -- Justification: command registration is a Neovim host boundary operation.
    vim.api.nvim_create_user_command(command.name, command.fn, { desc = command.desc })
  end
end

return M
