local config = require("jig.agent.config")
local state = require("jig.agent.state")

local M = {}

local session_id =
  string.format("jig-%d-%d", vim.uv.os_getpid(), math.floor(vim.uv.hrtime() / 1000000))

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function log_file()
  local cfg = config.get()
  return cfg.logging.evidence_file
end

local function normalize(entry)
  local payload = vim.deepcopy(entry or {})
  payload.timestamp = payload.timestamp or now_iso()
  payload.session_id = payload.session_id or session_id
  payload.task_id = payload.task_id
  payload.tool = payload.tool or ""
  payload.request = payload.request or {}
  payload.policy_decision = payload.policy_decision or ""
  payload.result = payload.result or {}
  payload.error_path = payload.error_path or ""
  return payload
end

function M.session_id()
  return session_id
end

function M.record(entry)
  local payload = normalize(entry)
  local ok, path_or_err = state.append_jsonl(log_file(), payload)
  if not ok then
    return false, path_or_err
  end
  return true, payload
end

function M.path()
  return state.path(log_file())
end

function M.tail(limit)
  return state.tail_jsonl(log_file(), limit)
end

return M
