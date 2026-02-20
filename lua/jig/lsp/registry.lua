local config = require("jig.lsp.config")

local M = {}

local function sorted_names(servers)
  local names = {}
  for name in pairs(servers or {}) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

local function is_string_list(value)
  if value == nil then
    return true
  end
  if type(value) ~= "table" then
    return false
  end
  for _, item in ipairs(value) do
    if type(item) ~= "string" or item == "" then
      return false
    end
  end
  return true
end

local function normalize_config(name, spec)
  local payload = {}

  if spec.config ~= nil then
    if type(spec.config) == "function" then
      local ok, result = pcall(spec.config)
      if not ok then
        return nil, string.format("server '%s' config() failed: %s", name, tostring(result))
      end
      if result ~= nil and type(result) ~= "table" then
        return nil, string.format("server '%s' config() must return table", name)
      end
      payload = result or {}
    elseif type(spec.config) == "table" then
      payload = vim.deepcopy(spec.config)
    else
      return nil, string.format("server '%s' config must be table or function", name)
    end
  end

  if spec.cmd ~= nil and payload.cmd == nil then
    payload.cmd = vim.deepcopy(spec.cmd)
  end

  if spec.filetypes ~= nil and payload.filetypes == nil then
    payload.filetypes = vim.deepcopy(spec.filetypes)
  end

  if spec.root_markers ~= nil and payload.root_markers == nil and payload.root_dir == nil then
    payload.root_markers = vim.deepcopy(spec.root_markers)
  end

  if spec.settings ~= nil and payload.settings == nil then
    payload.settings = vim.deepcopy(spec.settings)
  end

  if spec.init_options ~= nil and payload.init_options == nil then
    payload.init_options = vim.deepcopy(spec.init_options)
  end

  return payload, nil
end

function M.validate(servers)
  local errors = {}

  if type(servers) ~= "table" then
    return false, { "servers must be a table" }
  end

  for _, name in ipairs(sorted_names(servers)) do
    local spec = servers[name]
    if type(name) ~= "string" or name == "" then
      table.insert(errors, "server name must be non-empty string")
    end

    if type(spec) ~= "table" then
      table.insert(errors, string.format("server '%s' spec must be table", tostring(name)))
    else
      if spec.enabled ~= nil and type(spec.enabled) ~= "boolean" then
        table.insert(errors, string.format("server '%s' enabled must be boolean", name))
      end

      if spec.binary ~= nil and (type(spec.binary) ~= "string" or spec.binary == "") then
        table.insert(errors, string.format("server '%s' binary must be non-empty string", name))
      end

      if spec.cmd ~= nil and not is_string_list(spec.cmd) then
        table.insert(errors, string.format("server '%s' cmd must be string list", name))
      end

      if not is_string_list(spec.filetypes) then
        table.insert(errors, string.format("server '%s' filetypes must be string list", name))
      end

      if not is_string_list(spec.root_markers) then
        table.insert(errors, string.format("server '%s' root_markers must be string list", name))
      end

      if
        spec.config ~= nil
        and type(spec.config) ~= "table"
        and type(spec.config) ~= "function"
      then
        table.insert(errors, string.format("server '%s' config must be table or function", name))
      end
    end
  end

  return #errors == 0, errors
end

function M.resolve(opts)
  opts = opts or {}
  local cfg = opts.cfg or config.get(opts)
  local servers = opts.servers or cfg.servers or {}

  local ok, errors = M.validate(servers)
  if not ok then
    return false, errors
  end

  local entries = {}
  for _, name in ipairs(sorted_names(servers)) do
    local spec = servers[name]
    local lsp_config, config_error = normalize_config(name, spec)

    table.insert(entries, {
      name = name,
      enabled = spec.enabled ~= false,
      binary = spec.binary or (type(spec.cmd) == "table" and spec.cmd[1] or nil),
      remediation = spec.remediation,
      lsp_config = lsp_config,
      config_error = config_error,
    })
  end

  return true, entries
end

return M
