local brand = require("jig.core.brand")
local config = require("jig.lsp.config")
local diagnostics = require("jig.lsp.diagnostics")
local format_on_save = require("jig.lsp.format_on_save")
local health = require("jig.lsp.health")
local inlay_hints = require("jig.lsp.inlay_hints")
local lifecycle = require("jig.lsp.lifecycle")
local snapshot = require("jig.lsp.snapshot")

local M = {}

local initialized = false
local commands_registered = false

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map or {}) do
    table.insert(keys, key)
  end
  table.sort(keys)
  return keys
end

local function create_command(name, fn, opts)
  if vim.fn.exists(":" .. name) == 2 then
    return
  end
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

local function cmd_lsp_info()
  local snap = snapshot.capture()
  local enabled = {}
  local degraded = {}

  for _, name in ipairs(sorted_keys(snap.servers)) do
    local server = snap.servers[name]
    if server.status == "enabled" then
      table.insert(enabled, name)
    elseif server.status ~= "disabled" then
      table.insert(degraded, string.format("%s(%s)", name, server.status))
    end
  end

  local attached = {}
  for _, client in ipairs(snap.attached_clients) do
    table.insert(attached, client.name)
  end

  local lines = {
    string.format("profile=%s appname=%s", tostring(snap.profile), tostring(snap.appname)),
    string.format("buffer=%d diagnostics=%d", snap.bufnr, snap.diagnostics.total),
    string.format("enabled_servers=%s", #enabled > 0 and table.concat(enabled, ",") or "none"),
    string.format("degraded_servers=%s", #degraded > 0 and table.concat(degraded, ",") or "none"),
    string.format("attached_clients=%s", #attached > 0 and table.concat(attached, ",") or "none"),
  }

  local message = table.concat(lines, "\n")
  vim.notify(message, vim.log.levels.INFO)
  vim.g.jig_lsp_last_info = {
    lines = lines,
    snapshot = snap,
  }
end

local function cmd_lsp_snapshot(opts)
  local snap = snapshot.capture()
  local encoded = vim.json.encode(snap)

  if opts.args ~= nil and opts.args ~= "" then
    local ok, path_or_err = snapshot.write(opts.args, snap)
    if not ok then
      vim.notify("Jig LSP snapshot write failed: " .. tostring(path_or_err), vim.log.levels.ERROR)
      return
    end
    vim.notify("Jig LSP snapshot written: " .. path_or_err, vim.log.levels.INFO)
    vim.g.jig_lsp_last_snapshot = path_or_err
    return
  end

  print(encoded)
  vim.g.jig_lsp_last_snapshot = snap
end

local function register_commands()
  if commands_registered or vim.g.jig_safe_profile then
    return
  end

  create_command(brand.command("LspHealth"), function()
    health.notify()
  end, {
    desc = "Show Jig LSP health with remediation",
  })

  create_command(brand.command("LspInfo"), function()
    cmd_lsp_info()
  end, {
    desc = "Show enabled LSP servers and current buffer attach state",
  })

  create_command(brand.command("LspSnapshot"), function(opts)
    cmd_lsp_snapshot(opts)
  end, {
    nargs = "?",
    complete = "file",
    desc = "Print JSON snapshot or write LSP state to file",
  })

  commands_registered = true
end

function M.setup(opts)
  opts = opts or {}

  if vim.g.jig_safe_profile then
    return {
      profile = "safe",
      initialized = false,
    }
  end

  if initialized and opts.force ~= true then
    register_commands()
    return lifecycle.state()
  end

  local cfg = config.get(opts)
  diagnostics.apply(cfg.diagnostics)
  inlay_hints.setup(cfg.inlay_hints)
  format_on_save.setup(cfg.format_on_save)

  local result = lifecycle.setup({
    servers = cfg.servers,
    notify = opts.notify,
  })

  register_commands()
  initialized = true
  vim.g.jig_lsp_initialized = true
  return result
end

function M.context_snapshot(opts)
  return snapshot.capture(opts)
end

return M
