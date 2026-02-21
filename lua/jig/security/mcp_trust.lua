local security_config = require("jig.security.config")

local M = {}

local valid_state = {
  allow = true,
  ask = true,
  deny = true,
}

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function state_path()
  local cfg = security_config.get()
  return security_config.path(cfg.mcp_trust.state_file)
end

local function normalize_token(value)
  local token = tostring(value or "")
  token = token:gsub("^%s+", ""):gsub("%s+$", "")
  token = token:gsub("\\", "/")
  return token
end

local function normalize_argv(args)
  local out = {}
  for _, item in ipairs(args or {}) do
    out[#out + 1] = tostring(item)
  end
  return out
end

local function read_store()
  local path = state_path()
  if vim.fn.filereadable(path) ~= 1 then
    return {
      version = 1,
      entries = {},
    }
  end

  local payload = table.concat(vim.fn.readfile(path), "\n")
  local ok, decoded = pcall(vim.json.decode, payload)
  if not ok or type(decoded) ~= "table" then
    return {
      version = 1,
      entries = {},
    }
  end

  if type(decoded.entries) ~= "table" then
    decoded.entries = {}
  end

  return decoded
end

local function write_store(store)
  local path = state_path()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local ok, err = pcall(vim.fn.writefile, { vim.json.encode(store) }, path)
  if not ok then
    return false, tostring(err)
  end
  return true, path
end

local function source_label(server)
  if type(server._source_label) == "string" and server._source_label ~= "" then
    return server._source_label
  end

  local source = normalize_token(server._source)
  if source == "" then
    return "builtin"
  end

  if source:match("/%.mcp%.json$") or source:match("/mcp%.json$") then
    local config_home = normalize_token(vim.fn.stdpath("config"))
    if config_home ~= "" and source:find(config_home, 1, true) == 1 then
      return "user-config"
    end
    return "project-config"
  end

  return "unknown"
end

local function executable_fingerprint(command)
  local path = vim.fn.exepath(command)
  if path == "" then
    path = normalize_token(command)
  end

  local stat = vim.uv.fs_stat(path)
  if stat == nil then
    return path
  end

  local mtime = stat.mtime and stat.mtime.sec or 0
  return string.format("%s|%d|%d", path, stat.size or 0, mtime)
end

local function declared_capabilities(server)
  local caps = {}
  for tool_name, meta in pairs(server.tools or {}) do
    local action_class = tostring(meta.action_class or "unknown")
    local destructive = ({ write = true, net = true, shell = true, git = true })[action_class]
      == true
    caps[tool_name] = {
      action_class = action_class,
      target = tostring(meta.target or "*"),
      destructive = destructive,
    }
  end
  return caps
end

local function server_id(server)
  local material = {
    name = tostring(server.name or ""),
    command = tostring(server.command or ""),
    command_fingerprint = executable_fingerprint(server.command or ""),
    args = normalize_argv(server.args),
    cwd = tostring(server.cwd or ""),
    source = tostring(server._source or ""),
    source_label = source_label(server),
  }
  return vim.fn.sha256(vim.json.encode(material))
end

local function default_state_for(server)
  local cfg = security_config.get()
  local label = source_label(server)
  local map = cfg.mcp_trust.default_source_state or {}
  return map[label] or map.unknown or "ask"
end

local function audit(event)
  local ok_log, agent_log = pcall(require, "jig.agent.log")
  if not ok_log or type(agent_log.record) ~= "function" then
    return
  end
  agent_log.record(event)
end

function M.snapshot_server(server)
  local id = server_id(server)
  return {
    id = id,
    server_name = tostring(server.name or ""),
    source = tostring(server._source or ""),
    source_label = source_label(server),
    command = tostring(server.command or ""),
    args = normalize_argv(server.args),
    capabilities = declared_capabilities(server),
  }
end

function M.get(server)
  local snapshot = M.snapshot_server(server)
  local store = read_store()
  local entry = store.entries[snapshot.id]
  if type(entry) ~= "table" then
    entry = {
      id = snapshot.id,
      trust = default_state_for(server),
      server_name = snapshot.server_name,
      source = snapshot.source,
      source_label = snapshot.source_label,
      command = snapshot.command,
      args = snapshot.args,
      capabilities = snapshot.capabilities,
      updated_at = now_iso(),
      note = "",
      persisted = false,
    }
  else
    entry = vim.tbl_deep_extend("force", snapshot, entry)
    entry.persisted = true
  end

  return entry
end

function M.set_state(server, trust_state, opts)
  opts = opts or {}
  if not valid_state[trust_state] then
    return false, "invalid trust state: " .. tostring(trust_state)
  end

  local store = read_store()
  local snapshot = M.snapshot_server(server)
  local entry = store.entries[snapshot.id] or {}

  entry.id = snapshot.id
  entry.server_name = snapshot.server_name
  entry.source = snapshot.source
  entry.source_label = snapshot.source_label
  entry.command = snapshot.command
  entry.args = snapshot.args
  entry.capabilities = snapshot.capabilities
  entry.trust = trust_state
  entry.updated_at = now_iso()
  entry.note = tostring(opts.note or "")

  store.entries[snapshot.id] = entry
  local ok, path_or_err = write_store(store)
  if not ok then
    return false, path_or_err
  end

  audit({
    event = "mcp_trust_set",
    task_id = opts.task_id,
    tool = "mcp.trust",
    request = {
      server = entry.server_name,
      state = trust_state,
      source_label = entry.source_label,
    },
    policy_decision = trust_state,
    result = {
      persisted = true,
      path = path_or_err,
    },
  })

  return true, entry
end

function M.revoke(server, opts)
  opts = opts or {}
  local store = read_store()
  local snapshot = M.snapshot_server(server)
  local existing = store.entries[snapshot.id]

  if existing == nil then
    return false, "trust entry not found"
  end

  store.entries[snapshot.id] = nil
  local ok, path_or_err = write_store(store)
  if not ok then
    return false, path_or_err
  end

  audit({
    event = "mcp_trust_revoke",
    task_id = opts.task_id,
    tool = "mcp.trust",
    request = {
      server = existing.server_name,
    },
    policy_decision = "revoke",
    result = {
      path = path_or_err,
    },
  })

  return true, existing
end

function M.authorize_server(server, ctx)
  ctx = ctx or {}
  local entry = M.get(server)

  if entry.trust == "allow" then
    return {
      allowed = true,
      decision = "allow",
      reason = "trusted-server",
      entry = entry,
      hint = "",
    }
  end

  if entry.trust == "deny" then
    return {
      allowed = false,
      decision = "deny",
      reason = "server-denied",
      entry = entry,
      hint = "MCP server denied by trust policy. Use :JigMcpTrust allow <server> if intended.",
    }
  end

  return {
    allowed = false,
    decision = "ask",
    reason = "server-untrusted",
    entry = entry,
    hint = "MCP server requires trust grant. Use :JigMcpTrust allow <server> after review.",
  }
end

function M.authorize_tool(server, tool_name, ctx)
  ctx = ctx or {}
  local server_auth = M.authorize_server(server, ctx)
  if not server_auth.allowed then
    return server_auth
  end

  local entry = server_auth.entry
  local capability = entry.capabilities and entry.capabilities[tool_name] or nil
  local action_class = tostring(ctx.action_class or "unknown")
  local cfg = security_config.get()
  local high_risk = cfg.mcp_trust.high_risk_actions or {}

  if capability == nil then
    if high_risk[action_class] then
      return {
        allowed = false,
        decision = "deny",
        reason = "undeclared-high-risk-tool",
        entry = entry,
        hint = "Tool is not declared in server capabilities and action class is high risk.",
      }
    end

    return {
      allowed = false,
      decision = "ask",
      reason = "undeclared-tool",
      entry = entry,
      hint = "Tool is not declared. Declare capability or review with :JigMcpTrust.",
    }
  end

  local declared_action = tostring(capability.action_class or "unknown")
  if high_risk[action_class] and declared_action ~= action_class then
    return {
      allowed = false,
      decision = "deny",
      reason = "capability-action-mismatch",
      entry = entry,
      hint = "Requested tool action class does not match declared capability.",
    }
  end

  return {
    allowed = true,
    decision = "allow",
    reason = "declared-capability",
    entry = entry,
    capability = capability,
    hint = "",
  }
end

function M.list(discovery)
  local items = {}
  local store = read_store()

  for _, server in ipairs(discovery.servers or {}) do
    local auth = M.authorize_server(server, {})
    local persisted = store.entries[auth.entry.id] ~= nil
    items[#items + 1] = {
      id = auth.entry.id,
      server_name = auth.entry.server_name,
      source = auth.entry.source,
      source_label = auth.entry.source_label,
      trust = auth.entry.trust,
      decision = auth.decision,
      persisted = persisted,
      capabilities = auth.entry.capabilities or {},
      command = auth.entry.command,
      args = auth.entry.args,
      hint = auth.hint,
    }
  end

  table.sort(items, function(a, b)
    return a.server_name < b.server_name
  end)

  return items
end

function M.path()
  return state_path()
end

function M.reset_for_test()
  local path = state_path()
  if vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path)
  end
end

return M
