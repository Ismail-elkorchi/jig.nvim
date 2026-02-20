local agent_config = require("jig.agent.config")

local M = {}

local function normalize_env(env)
  local out = {}
  for key, value in pairs(env or {}) do
    out[tostring(key)] = tostring(value)
  end
  return out
end

local function normalize_args(args)
  local out = {}
  for _, value in ipairs(args or {}) do
    table.insert(out, tostring(value))
  end
  return out
end

local function normalize_tools(tools)
  if type(tools) ~= "table" then
    return {}
  end

  local out = {}
  for name, payload in pairs(tools) do
    if type(payload) == "table" then
      out[name] = {
        action_class = tostring(payload.action_class or "net"),
        target = tostring(payload.target or "*"),
      }
    else
      out[name] = {
        action_class = "net",
        target = "*",
      }
    end
  end
  return out
end

local function extract_servers(payload)
  if type(payload) ~= "table" then
    return {}
  end

  local servers = payload.mcpServers
  if type(servers) ~= "table" then
    servers = payload.servers
  end
  if type(servers) ~= "table" then
    return {}
  end

  local out = {}
  for name, spec in pairs(servers) do
    if type(spec) == "table" and type(spec.command) == "string" and spec.command ~= "" then
      out[name] = {
        name = name,
        command = spec.command,
        args = normalize_args(spec.args),
        env = normalize_env(spec.env),
        cwd = spec.cwd,
        timeout_ms = tonumber(spec.timeout_ms),
        transport = tostring(spec.transport or "stdio"),
        tools = normalize_tools(spec.tools),
      }
    end
  end

  return out
end

local function load_file(path)
  if vim.fn.filereadable(path) ~= 1 then
    return {
      exists = false,
      path = path,
      servers = {},
      error = "",
    }
  end

  local payload = table.concat(vim.fn.readfile(path), "\n")
  local ok_decode, decoded = pcall(vim.json.decode, payload)
  if not ok_decode then
    return {
      exists = true,
      path = path,
      servers = {},
      error = "invalid_json",
      detail = tostring(decoded),
    }
  end

  return {
    exists = true,
    path = path,
    servers = extract_servers(decoded),
    error = "",
  }
end

function M.discover(opts)
  local cfg = agent_config.get(opts)
  local root = agent_config.normalize_path(cfg.root or vim.uv.cwd())
  local precedence = cfg.mcp.config_precedence or cfg.mcp.config_files
  local files = {}
  local servers = {}

  for _, name in ipairs(precedence or {}) do
    local path = root .. "/" .. name
    local report = load_file(path)
    report.name = name
    report.server_count = vim.tbl_count(report.servers)
    table.insert(files, report)

    for server_name, spec in pairs(report.servers) do
      if servers[server_name] == nil then
        spec._source = path
        servers[server_name] = spec
      end
    end
  end

  return {
    root = root,
    files = files,
    servers = servers,
  }
end

function M.server(name, opts)
  local report = M.discover(opts)
  return report.servers[name], report
end

return M
