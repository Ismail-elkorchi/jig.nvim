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

local function rotate_limits()
  local cfg = config.get()
  local max_file_bytes = tonumber(cfg.logging.max_file_bytes) or 262144
  local max_files = tonumber(cfg.logging.max_files) or 4
  max_file_bytes = math.max(1024, math.floor(max_file_bytes))
  max_files = math.max(2, math.floor(max_files))
  return max_file_bytes, max_files
end

local function rotate_if_needed()
  local path = state.path(log_file())
  local stat = vim.uv.fs_stat(path)
  if stat == nil then
    return
  end

  local max_file_bytes, max_files = rotate_limits()
  if (stat.size or 0) < max_file_bytes then
    return
  end

  for index = max_files - 1, 1, -1 do
    local src = string.format("%s.%d", path, index)
    local dst = string.format("%s.%d", path, index + 1)
    if vim.fn.filereadable(src) == 1 then
      if index + 1 >= max_files then
        vim.fn.delete(dst)
      end
      vim.fn.rename(src, dst)
    end
  end

  if vim.fn.filereadable(path) == 1 then
    vim.fn.rename(path, path .. ".1")
  end
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
  rotate_if_needed()
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
