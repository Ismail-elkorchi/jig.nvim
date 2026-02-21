local policy = require("jig.agent.policy")
local system = require("jig.tools.system")

local M = {}

local function trim(value)
  return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function decode(stdout)
  local payload = trim(stdout)
  if payload == "" then
    return false, "empty_response", nil
  end

  local ok, decoded = pcall(vim.json.decode, payload)
  if ok and type(decoded) == "table" then
    return true, nil, decoded
  end

  for _, line in ipairs(vim.split(payload, "\n", { plain = true })) do
    local candidate = trim(line)
    if candidate ~= "" then
      local ok_line, decoded_line = pcall(vim.json.decode, candidate)
      if ok_line and type(decoded_line) == "table" then
        return true, nil, decoded_line
      end
    end
  end

  return false, "malformed_response", nil
end

local function request(spec, method, params, opts)
  opts = opts or {}
  local timeout_ms = tonumber(opts.timeout_ms) or tonumber(spec.timeout_ms) or 4000
  timeout_ms = math.max(1, math.floor(timeout_ms))

  local argv = { spec.command }
  for _, arg in ipairs(spec.args or {}) do
    table.insert(argv, tostring(arg))
  end

  local payload = {
    jsonrpc = "2.0",
    id = opts.request_id or 1,
    method = method,
    params = params or {},
  }

  local result = system.run_sync(argv, {
    cwd = opts.cwd or spec.cwd,
    env = spec.env,
    timeout_ms = timeout_ms,
    text = true,
    stdin = vim.json.encode(payload) .. "\n",
    actor = opts.actor or "agent",
    origin = opts.origin or "acp.stdio",
  })

  if result.ok ~= true then
    return {
      ok = false,
      reason = result.reason or "spawn_error",
      stderr = result.stderr,
      stdout = result.stdout,
    }
  end

  local ok_decode, reason, decoded = decode(result.stdout)
  if not ok_decode then
    return {
      ok = false,
      reason = reason,
      stderr = result.stderr,
      stdout = result.stdout,
    }
  end

  if type(decoded.error) == "table" then
    return {
      ok = false,
      reason = "rpc_error",
      response = decoded,
    }
  end

  return {
    ok = true,
    response = decoded,
  }
end

function M.name()
  return "acp-stdio"
end

function M.handshake(spec, opts)
  opts = opts or {}

  local decision = policy.authorize({
    tool = "acp.handshake",
    action_class = "shell",
    target = spec.name or spec.command or "acp",
    task_id = opts.task_id,
    ancestor_task_ids = opts.ancestor_task_ids,
  }, {
    log = true,
  })

  if not decision.allowed then
    return {
      ok = false,
      reason = "blocked_by_policy",
      decision = decision,
    }
  end

  return request(spec, "acp/initialize", {
    client = "jig.nvim",
    protocol = "acp-stdio",
    version = "0.1",
  }, opts)
end

function M.prompt(spec, prompt, opts)
  opts = opts or {}

  local decision = policy.authorize({
    tool = "acp.prompt",
    action_class = "read",
    target = spec.name or "acp",
    task_id = opts.task_id,
    ancestor_task_ids = opts.ancestor_task_ids,
  }, {
    log = true,
  })

  if not decision.allowed then
    return {
      ok = false,
      reason = "blocked_by_policy",
      decision = decision,
    }
  end

  local response = request(spec, "acp/prompt", {
    prompt = prompt,
  }, opts)

  if response.ok ~= true then
    return response
  end

  local payload = response.response and response.response.result
  if type(payload) ~= "table" then
    return {
      ok = false,
      reason = "malformed_response",
      response = response.response,
    }
  end

  return {
    ok = true,
    result = {
      type = "candidate",
      content = payload.content,
      metadata = payload.metadata or {},
    },
  }
end

return M
