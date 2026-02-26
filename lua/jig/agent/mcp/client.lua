local log = require("jig.agent.log")
local mcp_config = require("jig.agent.mcp.config")
local net_guard = require("jig.security.net_guard")
local mcp_trust = require("jig.security.mcp_trust")
local security_gate = require("jig.security.gate")
local policy = require("jig.agent.policy")
local transport = require("jig.agent.mcp.transport")

local M = {}

local runtime = {
  servers = {},
}

local function server_runtime(name)
  local item = runtime.servers[name]
  if not item then
    item = {
      name = name,
      status = "stopped",
      last_error = "",
      source = "",
      source_label = "",
      initialized_at = nil,
    }
    runtime.servers[name] = item
  end
  return item
end

local function discovered_server_list(report)
  local items = {}
  for _, server in pairs(report.servers or {}) do
    items[#items + 1] = server
  end
  table.sort(items, function(a, b)
    return tostring(a.name) < tostring(b.name)
  end)
  return items
end

local function server_by_name(name, opts)
  local server, report = mcp_config.server(name, opts)
  if not server then
    return nil, report, "server not found: " .. tostring(name)
  end
  return server, report, nil
end

local function record(event)
  log.record(event)
end

local function policy_decision(subject, opts)
  local result = policy.authorize(subject, {
    log = opts.log_policy ~= false,
    origin = opts.origin or subject.tool,
    summary = opts.summary or "",
    notify = opts.notify ~= false,
  })

  if result.allowed then
    return true, result
  end

  return false, result
end

local function response_hint(result)
  local hints = {
    missing_binary = "Install the server binary and run :JigMcpStart <server>.",
    timeout = "Increase timeout or inspect server process; then retry :JigMcpStart.",
    malformed_response = "Server returned malformed JSON-RPC payload.",
    rpc_error = "Server returned JSON-RPC error.",
    not_started = "Run :JigMcpStart <server> first.",
    tool_not_found = "Check :JigMcpTools <server> and use a listed tool name.",
    blocked_by_policy = "Use :JigAgentPolicyGrant allow ... or revoke deny rules.",
    blocked_by_trust = "Use :JigMcpTrust to grant explicit trust after reviewing source and capabilities.",
    blocked_by_net_guard = "Startup network policy denied this operation.",
    blocked_by_security_gate = "Security gate denied the request. Review audit logs and approval identity.",
  }

  return hints[result] or "Inspect :JigMcpList and evidence log for details."
end

local function gate_result(reason, report)
  return {
    ok = false,
    reason = reason or "blocked_by_security_gate",
    payload = report or {},
    hint = response_hint(reason or "blocked_by_security_gate"),
  }
end

local function post_gate(report, result, extra)
  if type(report) ~= "table" then
    return
  end
  security_gate.post_tool_call(report, {
    ok = result.ok == true,
    code = result.code or -1,
    reason = result.reason,
    hint = result.hint,
  }, extra or {})
end

local function normalize_result(ok, payload, reason)
  if ok then
    return {
      ok = true,
      reason = "ok",
      payload = payload,
      hint = "",
    }
  end

  return {
    ok = false,
    reason = reason,
    payload = payload,
    hint = response_hint(reason),
  }
end

local function classify_tool_action(server, tool_name)
  local meta = server.tools and server.tools[tool_name] or nil
  local action_class = meta and meta.action_class or "unknown"
  local target = meta and meta.target or server.name
  return action_class, target
end

function M.list(opts)
  local report = mcp_config.discover(opts)
  local servers = discovered_server_list(report)
  local trust = mcp_trust.list({ servers = servers })
  local trust_by_name = {}

  for _, entry in ipairs(trust) do
    trust_by_name[entry.server_name] = entry
  end

  local items = {}
  for _, server in ipairs(servers) do
    local item = server_runtime(server.name)
    local trust_entry = trust_by_name[server.name]

    items[#items + 1] = {
      name = server.name,
      command = server.command,
      args = server.args,
      source = server._source,
      source_label = server._source_label,
      status = item.status,
      last_error = item.last_error,
      initialized_at = item.initialized_at,
      trust = trust_entry and trust_entry.trust or "ask",
      capabilities = trust_entry and trust_entry.capabilities or {},
      trust_hint = trust_entry and trust_entry.hint or "",
    }
  end

  return {
    root = report.root,
    files = report.files,
    servers = items,
    trust_path = mcp_trust.path(),
  }
end

function M.discovery(opts)
  return mcp_config.discover(opts)
end

function M.start(name, opts)
  opts = opts or {}
  local server, _, err = server_by_name(name, opts)
  if not server then
    local result = normalize_result(false, {}, "not_found")
    result.error = err
    return result
  end

  local trust_result = mcp_trust.authorize_server(server, {
    task_id = opts.task_id,
  })
  if not trust_result.allowed then
    local result = normalize_result(false, trust_result, "blocked_by_trust")
    record({
      event = "mcp_start",
      task_id = opts.task_id,
      tool = "mcp.start",
      request = {
        server = name,
        source_label = server._source_label,
      },
      policy_decision = trust_result.decision,
      result = result,
      error_path = trust_result.hint,
    })
    return result
  end

  local argv = { server.command }
  for _, arg in ipairs(server.args or {}) do
    argv[#argv + 1] = arg
  end

  local actor = opts.actor or "agent"
  local gate_report = security_gate.pre_tool_call({
    actor = actor,
    origin = "mcp.start",
    task_id = opts.task_id,
    action = "exec.run",
    target = server.command,
    target_path = server.command,
    argv = argv,
    prompt_text = opts.prompt_text,
    approval_id = opts.approval_id,
    approval_actor = opts.approval_actor,
    approval_tool = opts.approval_tool,
    project_root = opts.project_root,
    subagent = opts.subagent,
  })
  if gate_report.allowed ~= true then
    local blocked = gate_result("blocked_by_security_gate", gate_report)
    record({
      event = "mcp_start",
      task_id = opts.task_id,
      tool = "mcp.start",
      request = {
        server = name,
        source_label = server._source_label,
      },
      policy_decision = gate_report.decision,
      result = blocked,
      error_path = gate_report.hint,
    })
    post_gate(gate_report, blocked, {
      actor = actor,
      origin = "mcp.start",
      task_id = opts.task_id,
      server = name,
      subagent = opts.subagent,
      approval_id = opts.approval_id,
    })
    return blocked
  end

  local net_report = net_guard.evaluate_argv(argv, {
    actor = actor,
    origin = "mcp.start",
    task_id = opts.task_id,
  })
  if net_report.allowed ~= true then
    local result = normalize_result(false, net_report, "blocked_by_net_guard")
    record({
      event = "mcp_start",
      task_id = opts.task_id,
      tool = "mcp.start",
      request = {
        server = name,
      },
      policy_decision = "deny",
      result = result,
      error_path = net_report.hint,
    })
    post_gate(gate_report, result, {
      actor = actor,
      origin = "mcp.start",
      task_id = opts.task_id,
      server = name,
      subagent = opts.subagent,
      approval_id = opts.approval_id,
    })
    return result
  end

  if vim.fn.executable(server.command) ~= 1 then
    local item = server_runtime(name)
    item.status = "error"
    item.last_error = "missing_binary"

    local result = normalize_result(false, {
      server = name,
      command = server.command,
    }, "missing_binary")

    record({
      event = "mcp_start",
      tool = "mcp.start",
      request = {
        server = name,
      },
      policy_decision = trust_result.decision,
      result = result,
      error_path = result.hint,
    })
    post_gate(gate_report, result, {
      actor = actor,
      origin = "mcp.start",
      task_id = opts.task_id,
      server = name,
      subagent = opts.subagent,
      approval_id = opts.approval_id,
    })

    return result
  end

  local handshake = transport.request(
    server,
    "initialize",
    {
      client = "jig.nvim",
      version = "0.1",
    },
    vim.tbl_deep_extend("force", opts, {
      actor = actor,
      origin = "mcp.start",
    })
  )

  local item = server_runtime(name)
  if handshake.ok ~= true then
    item.status = "error"
    item.last_error = handshake.reason

    local result = normalize_result(false, handshake, handshake.reason)
    record({
      event = "mcp_start",
      tool = "mcp.start",
      request = {
        server = name,
      },
      policy_decision = trust_result.decision,
      result = result,
      error_path = result.hint,
    })
    post_gate(gate_report, result, {
      actor = actor,
      origin = "mcp.start",
      task_id = opts.task_id,
      server = name,
      subagent = opts.subagent,
      approval_id = opts.approval_id,
    })
    return result
  end

  item.status = "running"
  item.last_error = ""
  item.initialized_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
  item.source = server._source or ""
  item.source_label = server._source_label or ""

  local result = normalize_result(true, {
    server = name,
    initialize = handshake.response,
  }, "ok")

  record({
    event = "mcp_start",
    tool = "mcp.start",
    request = {
      server = name,
      source_label = server._source_label,
    },
    policy_decision = trust_result.decision,
    result = result,
  })
  post_gate(gate_report, result, {
    actor = actor,
    origin = "mcp.start",
    task_id = opts.task_id,
    server = name,
    subagent = opts.subagent,
    approval_id = opts.approval_id,
  })

  return result
end

function M.stop(name)
  if name == "all" then
    for server_name, item in pairs(runtime.servers) do
      item.status = "stopped"
      item.last_error = ""
      item.initialized_at = nil
      runtime.servers[server_name] = item
    end
    record({
      event = "mcp_stop",
      tool = "mcp.stop",
      request = {
        server = "all",
      },
      policy_decision = "allow",
      result = {
        ok = true,
      },
    })
    return normalize_result(true, { server = "all" }, "ok")
  end

  local item = runtime.servers[name]
  if not item then
    return normalize_result(false, { server = name }, "not_found")
  end

  item.status = "stopped"
  item.last_error = ""
  item.initialized_at = nil

  record({
    event = "mcp_stop",
    tool = "mcp.stop",
    request = {
      server = name,
    },
    policy_decision = "allow",
    result = {
      ok = true,
    },
  })

  return normalize_result(true, { server = name }, "ok")
end

local function require_started(name, opts)
  local server, _, err = server_by_name(name, opts)
  if not server then
    return nil, normalize_result(false, { error = err }, "not_found")
  end

  local item = runtime.servers[name]
  if not item or item.status ~= "running" then
    return nil, normalize_result(false, { server = name }, "not_started")
  end

  return server, nil
end

function M.tools(name, opts)
  opts = opts or {}
  local server, not_started = require_started(name, opts)
  if not server then
    return not_started
  end

  local trust_result = mcp_trust.authorize_server(server, {
    task_id = opts.task_id,
  })
  if not trust_result.allowed then
    local result = normalize_result(false, trust_result, "blocked_by_trust")
    record({
      event = "mcp_tools",
      task_id = opts.task_id,
      tool = "mcp.tools",
      request = {
        server = name,
      },
      policy_decision = trust_result.decision,
      result = result,
      error_path = trust_result.hint,
    })
    return result
  end

  local allowed, decision = policy_decision(
    {
      tool = "mcp.tools",
      action_class = "read",
      target = name,
      project_root = opts.project_root,
      task_id = opts.task_id,
      ancestor_task_ids = opts.ancestor_task_ids,
    },
    vim.tbl_deep_extend("force", opts, {
      origin = "mcp.tools",
      summary = string.format("server=%s", tostring(name)),
    })
  )

  if not allowed then
    local result = normalize_result(false, decision, "blocked_by_policy")
    record({
      event = "mcp_tools",
      task_id = opts.task_id,
      tool = "mcp.tools",
      request = {
        server = name,
      },
      policy_decision = decision.decision,
      result = result,
      error_path = result.hint,
    })
    return result
  end

  local response = transport.request(
    server,
    "tools/list",
    {},
    vim.tbl_deep_extend("force", opts, {
      actor = opts.actor or "agent",
      origin = "mcp.tools",
    })
  )
  if response.ok ~= true then
    local result = normalize_result(false, response, response.reason)
    record({
      event = "mcp_tools",
      task_id = opts.task_id,
      tool = "mcp.tools",
      request = {
        server = name,
      },
      policy_decision = decision.decision,
      result = result,
      error_path = result.hint,
    })
    return result
  end

  local payload = response.response and response.response.result or {}
  local result = normalize_result(true, payload, "ok")
  record({
    event = "mcp_tools",
    task_id = opts.task_id,
    tool = "mcp.tools",
    request = {
      server = name,
    },
    policy_decision = decision.decision,
    result = {
      ok = true,
      tool_count = type(payload.tools) == "table" and #payload.tools or 0,
    },
  })
  return result
end

function M.call(name, tool_name, arguments, opts)
  opts = opts or {}
  local server, not_started = require_started(name, opts)
  if not server then
    return not_started
  end

  local action_class, target = classify_tool_action(server, tool_name)
  local trust_result = mcp_trust.authorize_tool(server, tool_name, {
    action_class = action_class,
    task_id = opts.task_id,
  })
  if not trust_result.allowed then
    local result = normalize_result(false, trust_result, "blocked_by_trust")
    record({
      event = "mcp_call",
      task_id = opts.task_id,
      tool = "mcp.call",
      request = {
        server = name,
        tool = tool_name,
      },
      policy_decision = trust_result.decision,
      result = result,
      error_path = trust_result.hint,
    })
    return result
  end

  if action_class == "net" then
    local net_result = net_guard.evaluate_action_class("net", {
      actor = opts.actor or "agent",
      origin = "mcp.call",
      task_id = opts.task_id,
    })
    if net_result.allowed ~= true then
      local blocked = normalize_result(false, net_result, "blocked_by_net_guard")
      record({
        event = "mcp_call",
        task_id = opts.task_id,
        tool = "mcp.call",
        request = {
          server = name,
          tool = tool_name,
        },
        policy_decision = "deny",
        result = blocked,
        error_path = net_result.hint,
      })
      return blocked
    end
  end

  local allowed, decision = policy_decision(
    {
      tool = "mcp.call." .. tostring(tool_name),
      action_class = action_class,
      target = target,
      project_root = opts.project_root,
      task_id = opts.task_id,
      ancestor_task_ids = opts.ancestor_task_ids,
    },
    vim.tbl_deep_extend("force", opts, {
      origin = "mcp.call",
      summary = string.format("server=%s tool=%s", tostring(name), tostring(tool_name)),
    })
  )

  if not allowed then
    local result = normalize_result(false, decision, "blocked_by_policy")
    record({
      event = "mcp_call",
      task_id = opts.task_id,
      tool = "mcp.call",
      request = {
        server = name,
        tool = tool_name,
      },
      policy_decision = decision.decision,
      result = result,
      error_path = result.hint,
    })
    return result
  end

  local prompt_text = opts.prompt_text
  if type(prompt_text) ~= "string" or prompt_text == "" then
    prompt_text = vim.inspect(arguments or {})
  end
  local gate_report = security_gate.pre_tool_call({
    actor = opts.actor or "agent",
    origin = "mcp.call",
    task_id = opts.task_id,
    action = action_class,
    target = string.format("%s:%s", tostring(name), tostring(tool_name)),
    project_root = opts.project_root,
    prompt_text = prompt_text,
    approval_id = opts.approval_id or decision.pending_id,
    approval_actor = opts.approval_actor,
    approval_tool = opts.approval_tool,
    subagent = opts.subagent,
  })
  if gate_report.allowed ~= true then
    local blocked = gate_result("blocked_by_security_gate", gate_report)
    record({
      event = "mcp_call",
      task_id = opts.task_id,
      tool = "mcp.call",
      request = {
        server = name,
        tool = tool_name,
      },
      policy_decision = gate_report.decision,
      result = blocked,
      error_path = gate_report.hint,
    })
    post_gate(gate_report, blocked, {
      actor = opts.actor or "agent",
      origin = "mcp.call",
      task_id = opts.task_id,
      subagent = opts.subagent,
      approval_id = opts.approval_id or decision.pending_id,
      server = name,
      target = target,
    })
    return blocked
  end

  local response = transport.request(
    server,
    "tools/call",
    {
      name = tool_name,
      arguments = arguments or {},
    },
    vim.tbl_deep_extend("force", opts, {
      actor = opts.actor or "agent",
      origin = "mcp.call",
      action = action_class,
      target = target,
      prompt_text = prompt_text,
      approval_id = opts.approval_id or decision.pending_id,
      approval_actor = opts.approval_actor,
      approval_tool = opts.approval_tool,
      subagent = opts.subagent,
      server = name,
    })
  )

  if response.ok ~= true then
    local result = normalize_result(false, response, response.reason)
    record({
      event = "mcp_call",
      task_id = opts.task_id,
      tool = "mcp.call",
      request = {
        server = name,
        tool = tool_name,
      },
      policy_decision = decision.decision,
      result = result,
      error_path = result.hint,
    })
    post_gate(gate_report, result, {
      actor = opts.actor or "agent",
      origin = "mcp.call",
      task_id = opts.task_id,
      subagent = opts.subagent,
      approval_id = opts.approval_id or decision.pending_id,
      server = name,
      target = target,
    })
    return result
  end

  local payload = response.response and response.response.result
  if type(payload) ~= "table" then
    local result = normalize_result(false, {
      server = name,
      tool = tool_name,
      payload = payload,
    }, "malformed_response")
    record({
      event = "mcp_call",
      task_id = opts.task_id,
      tool = "mcp.call",
      request = {
        server = name,
        tool = tool_name,
      },
      policy_decision = decision.decision,
      result = result,
      error_path = result.hint,
    })
    post_gate(gate_report, result, {
      actor = opts.actor or "agent",
      origin = "mcp.call",
      task_id = opts.task_id,
      subagent = opts.subagent,
      approval_id = opts.approval_id or decision.pending_id,
      server = name,
      target = target,
    })
    return result
  end

  if payload.error == "tool_not_found" then
    local result = normalize_result(false, payload, "tool_not_found")
    record({
      event = "mcp_call",
      task_id = opts.task_id,
      tool = "mcp.call",
      request = {
        server = name,
        tool = tool_name,
      },
      policy_decision = decision.decision,
      result = result,
      error_path = result.hint,
    })
    post_gate(gate_report, result, {
      actor = opts.actor or "agent",
      origin = "mcp.call",
      task_id = opts.task_id,
      subagent = opts.subagent,
      approval_id = opts.approval_id or decision.pending_id,
      server = name,
      target = target,
    })
    return result
  end

  local result = normalize_result(true, payload, "ok")
  record({
    event = "mcp_call",
    task_id = opts.task_id,
    tool = "mcp.call",
    request = {
      server = name,
      tool = tool_name,
    },
    policy_decision = decision.decision,
    result = {
      ok = true,
    },
  })
  post_gate(gate_report, result, {
    actor = opts.actor or "agent",
    origin = "mcp.call",
    task_id = opts.task_id,
    subagent = opts.subagent,
    approval_id = opts.approval_id or decision.pending_id,
    server = name,
    target = target,
  })

  return result
end

function M.runtime_state()
  return vim.deepcopy(runtime)
end

function M.reset_for_test()
  runtime = {
    servers = {},
  }
end

return M
