local agent_config = require("jig.agent.config")
local system = require("jig.tools.system")

local M = {}

local next_id = 1

local function trim(value)
  return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function content_length_payload(stdout)
  local text = stdout or ""
  local header, body = text:match("Content%-Length:%s*(%d+)%s*\r?\n\r?\n(.*)")
  if not header then
    return nil
  end

  local length = tonumber(header)
  if not length or length <= 0 then
    return nil
  end

  if #body < length then
    return nil
  end

  return body:sub(1, length)
end

local function decode_response(stdout)
  local payload = trim(stdout)
  if payload == "" then
    return false, "empty_response", nil
  end

  local content_length = content_length_payload(stdout)
  if content_length then
    local ok_length, decoded_length = pcall(vim.json.decode, content_length)
    if ok_length and type(decoded_length) == "table" then
      return true, nil, decoded_length
    end
  end

  local ok_full, decoded_full = pcall(vim.json.decode, payload)
  if ok_full and type(decoded_full) == "table" then
    return true, nil, decoded_full
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

local function method_timeout(server, opts)
  local cfg = agent_config.get(opts)
  if type(opts) == "table" and tonumber(opts.timeout_ms) then
    return tonumber(opts.timeout_ms)
  end

  if server.timeout_ms then
    return tonumber(server.timeout_ms)
  end

  return tonumber(cfg.mcp.timeout_ms) or 5000
end

local function request_payload(method, params)
  local id = next_id
  next_id = next_id + 1

  return {
    id = id,
    request = {
      jsonrpc = "2.0",
      id = id,
      method = method,
      params = params or {},
    },
  }
end

function M.request(server, method, params, opts)
  opts = opts or {}

  local payload = request_payload(method, params)
  local timeout_ms = math.max(1, math.floor(method_timeout(server, opts)))

  local argv = { server.command }
  for _, arg in ipairs(server.args or {}) do
    table.insert(argv, tostring(arg))
  end

  local result = system.run_sync(argv, {
    cwd = opts.cwd or server.cwd,
    env = server.env,
    timeout_ms = timeout_ms,
    stdin = vim.json.encode(payload.request) .. "\n",
    text = true,
    actor = opts.actor or "agent",
    origin = opts.origin or "mcp.transport",
    allow_network = opts.allow_network == true,
  })

  if result.ok ~= true then
    local reason = result.reason or "spawn_error"
    if reason == "timeout" or reason == "system_wait_nil" or reason == "system_wait_error" then
      reason = "timeout"
    end

    return {
      ok = false,
      reason = reason,
      code = result.code,
      stderr = result.stderr,
      stdout = result.stdout,
      timeout_ms = timeout_ms,
      request_id = payload.id,
    }
  end

  local ok_decode, decode_reason, response = decode_response(result.stdout)
  if not ok_decode then
    return {
      ok = false,
      reason = decode_reason,
      code = result.code,
      stderr = result.stderr,
      stdout = result.stdout,
      timeout_ms = timeout_ms,
      request_id = payload.id,
    }
  end

  if type(response.error) == "table" then
    return {
      ok = false,
      reason = "rpc_error",
      code = result.code,
      stderr = result.stderr,
      stdout = result.stdout,
      response = response,
      timeout_ms = timeout_ms,
      request_id = payload.id,
    }
  end

  return {
    ok = true,
    reason = "ok",
    code = result.code,
    stderr = result.stderr,
    stdout = result.stdout,
    response = response,
    timeout_ms = timeout_ms,
    request_id = payload.id,
  }
end

return M
