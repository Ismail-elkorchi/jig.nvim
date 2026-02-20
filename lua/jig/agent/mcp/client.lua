local mcp_config = require("jig.agent.mcp.config")
local log = require("jig.agent.log")
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
      initialized_at = nil,
    }
    runtime.servers[name] = item
  end
  return item
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

local function decision_for(subject, opts)
  local result = policy.authorize(subject, {
    log = opts.log_policy ~= false,
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
  }

  return hints[result] or "Inspect :JigMcpList and evidence log for details."
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
  local action_class = meta and meta.action_class or "net"
  local target = meta and meta.target or server.name
  return action_class, target
end

function M.list(opts)
  local report = mcp_config.discover(opts)
  local items = {}

  for name, server in pairs(report.servers) do
    local item = server_runtime(name)
    table.insert(items, {
      name = name,
      command = server.command,
      args = server.args,
      source = server._source,
      status = item.status,
      last_error = item.last_error,
      initialized_at = item.initialized_at,
    })
  end

  table.sort(items, function(a, b)
    return a.name < b.name
  end)

  return {
    root = report.root,
    files = report.files,
    servers = items,
  }
end

function M.start(name, opts)
  opts = opts or {}
  local server, _, err = server_by_name(name, opts)
  if not server then
    local result = normalize_result(false, {}, "not_found")
    result.error = err
    return result
  end

  local allowed, decision = decision_for({
    tool = "mcp.start." .. tostring(name),
    action_class = "shell",
    target = name,
    project_root = opts.project_root,
    task_id = opts.task_id,
    ancestor_task_ids = opts.ancestor_task_ids,
  }, opts)

  if not allowed then
    local result = normalize_result(false, decision, "blocked_by_policy")
    record({
      event = "mcp_start",
      task_id = opts.task_id,
      tool = "mcp.start",
      request = {
        server = name,
      },
      policy_decision = decision.decision,
      result = result,
      error_path = result.hint,
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
      policy_decision = decision.decision,
      result = result,
      error_path = result.hint,
    })

    return result
  end

  local handshake = transport.request(server, "initialize", {
    client = "jig.nvim",
    version = "0.1",
  }, opts)

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
      policy_decision = decision.decision,
      result = result,
      error_path = result.hint,
    })
    return result
  end

  item.status = "running"
  item.last_error = ""
  item.initialized_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
  item.source = server._source or ""

  local result = normalize_result(true, {
    server = name,
    initialize = handshake.response,
  }, "ok")

  record({
    event = "mcp_start",
    tool = "mcp.start",
    request = {
      server = name,
    },
    policy_decision = decision.decision,
    result = result,
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

  local allowed, decision = decision_for({
    tool = "mcp.tools",
    action_class = "read",
    target = name,
    project_root = opts.project_root,
    task_id = opts.task_id,
    ancestor_task_ids = opts.ancestor_task_ids,
  }, opts)

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

  local response = transport.request(server, "tools/list", {}, opts)
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
  local allowed, decision = decision_for({
    tool = "mcp.call." .. tostring(tool_name),
    action_class = action_class,
    target = target,
    project_root = opts.project_root,
    task_id = opts.task_id,
    ancestor_task_ids = opts.ancestor_task_ids,
  }, opts)

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

  local response = transport.request(server, "tools/call", {
    name = tool_name,
    arguments = arguments or {},
  }, opts)

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
