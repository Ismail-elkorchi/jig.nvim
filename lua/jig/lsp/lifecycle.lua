local format_on_save = require("jig.lsp.format_on_save")
local inlay_hints = require("jig.lsp.inlay_hints")
local registry = require("jig.lsp.registry")

local M = {}

local state = {
  initialized = false,
  started_at = nil,
  registry_errors = {},
  servers = {},
  attach_events = {},
}

local function deepcopy(value)
  return vim.deepcopy(value)
end

local function reset_state()
  state = {
    initialized = true,
    started_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    registry_errors = {},
    servers = {},
    attach_events = {},
  }
end

local function set_server(name, payload)
  state.servers[name] = vim.tbl_extend("force", { name = name }, payload)
end

local function degraded_count()
  local count = 0
  for _, server in pairs(state.servers) do
    if server.status ~= "enabled" and server.status ~= "disabled" then
      count = count + 1
    end
  end
  return count
end

local function active_count()
  local count = 0
  for _, server in pairs(state.servers) do
    if server.status == "enabled" then
      count = count + 1
    end
  end
  return count
end

local function register_attach_tracking()
  local group = vim.api.nvim_create_augroup("JigLspAttach", { clear = true })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
      local client_id = args.data and args.data.client_id or nil
      local client = client_id and vim.lsp.get_client_by_id(client_id) or nil
      if not client then
        return
      end

      local event = {
        bufnr = args.buf,
        client_id = client.id,
        client_name = client.name,
        attached_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      }

      local ok_inlay, inlay_status = pcall(inlay_hints.on_attach, client, args.buf)
      event.inlay_hints = ok_inlay and inlay_status or ("error: " .. tostring(inlay_status))

      local ok_format, format_status = pcall(format_on_save.on_attach, client, args.buf)
      event.format_on_save = ok_format and format_status or ("error: " .. tostring(format_status))

      table.insert(state.attach_events, event)
    end,
    desc = "Jig LSP attach policy hooks",
  })
end

local function resolve_server_error(entry)
  if entry.remediation and entry.remediation ~= "" then
    return entry.remediation
  end

  if entry.binary and entry.binary ~= "" then
    return string.format("Install '%s', restart Neovim, then run :JigLspHealth", entry.binary)
  end

  return "Run :JigLspHealth and inspect :JigLspSnapshot for details"
end

local function apply_entry(entry)
  if entry.enabled ~= true then
    set_server(entry.name, {
      status = "disabled",
      message = "disabled by policy",
      configured = false,
      enabled = false,
    })
    return
  end

  if entry.config_error then
    set_server(entry.name, {
      status = "config_error",
      message = entry.config_error,
      remediation = resolve_server_error(entry),
      configured = false,
      enabled = false,
    })
    return
  end

  if entry.binary and vim.fn.executable(entry.binary) ~= 1 then
    set_server(entry.name, {
      status = "missing_binary",
      message = string.format("missing executable: %s", entry.binary),
      remediation = resolve_server_error(entry),
      configured = false,
      enabled = false,
      binary = entry.binary,
    })
    return
  end

  local ok_config, config_err = pcall(vim.lsp.config, entry.name, entry.lsp_config or {})
  if not ok_config then
    set_server(entry.name, {
      status = "config_error",
      message = tostring(config_err),
      remediation = "Inspect server config and run :JigLspHealth",
      configured = false,
      enabled = false,
    })
    return
  end

  local ok_enable, enable_err = pcall(vim.lsp.enable, entry.name)
  if not ok_enable then
    set_server(entry.name, {
      status = "enable_error",
      message = tostring(enable_err),
      remediation = "Inspect :JigLspSnapshot and re-run :JigLspInfo",
      configured = true,
      enabled = false,
    })
    return
  end

  set_server(entry.name, {
    status = "enabled",
    message = "configured and enabled",
    configured = true,
    enabled = true,
  })
end

function M.setup(opts)
  opts = opts or {}
  reset_state()
  local interactive = #vim.api.nvim_list_uis() > 0

  local ok, result = registry.resolve({
    servers = opts.servers,
    cfg = opts.cfg,
  })

  if not ok then
    state.registry_errors = result
    if opts.notify ~= false and interactive then
      vim.schedule(function()
        vim.notify("Jig LSP registry validation failed. Run :JigLspHealth", vim.log.levels.ERROR)
      end)
    end
    register_attach_tracking()
    return deepcopy(state)
  end

  for _, entry in ipairs(result) do
    apply_entry(entry)
  end

  register_attach_tracking()

  local degraded = degraded_count()
  local active = active_count()

  if opts.notify ~= false and interactive and degraded > 0 then
    vim.schedule(function()
      vim.notify(
        string.format(
          "Jig LSP degraded (%d/%d). Run :JigLspHealth for actionable fixes.",
          degraded,
          active + degraded
        ),
        vim.log.levels.WARN
      )
    end)
  end

  return deepcopy(state)
end

function M.state()
  return deepcopy(state)
end

function M.summary()
  return {
    initialized = state.initialized,
    started_at = state.started_at,
    active_servers = active_count(),
    degraded_servers = degraded_count(),
    registry_errors = deepcopy(state.registry_errors),
    servers = deepcopy(state.servers),
  }
end

function M.reset_for_test()
  reset_state()
  inlay_hints.reset_for_test()
  format_on_save.reset_for_test()
end

return M
