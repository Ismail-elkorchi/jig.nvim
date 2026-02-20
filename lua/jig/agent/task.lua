local config = require("jig.agent.config")
local log = require("jig.agent.log")
local state = require("jig.agent.state")

local M = {}

local runners = {}

local function task_file()
  local cfg = config.get()
  return cfg.tasks.metadata_file
end

local function default_store()
  return {
    version = 1,
    next_id = 1,
    tasks = {},
  }
end

local function load_store()
  local store = state.read_json(task_file(), default_store())
  if type(store.tasks) ~= "table" then
    store.tasks = {}
  end
  if type(store.next_id) ~= "number" then
    store.next_id = 1
  end
  return store
end

local function save_store(store)
  return state.write_json(task_file(), store)
end

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function summarize_result(result)
  if type(result) == "string" then
    return result
  end
  if type(result) == "table" then
    local summary = {}
    for key, value in pairs(result) do
      if type(value) ~= "table" then
        table.insert(summary, string.format("%s=%s", key, tostring(value)))
      end
      if #summary >= 4 then
        break
      end
    end
    table.sort(summary)
    return table.concat(summary, ",")
  end
  return tostring(result)
end

local function sorted_tasks(tasks)
  local out = {}
  for _, item in pairs(tasks or {}) do
    table.insert(out, item)
  end
  table.sort(out, function(a, b)
    return tostring(a.id) < tostring(b.id)
  end)
  return out
end

local function update_task(task_id, mutate)
  local store = load_store()
  local task = store.tasks[task_id]
  if not task then
    return false, "task not found: " .. tostring(task_id)
  end
  mutate(task)
  task.updated_at = now_iso()
  save_store(store)
  return true, task
end

local function run_task(task_id, run_fn, timeout_ms)
  vim.schedule(function()
    local store = load_store()
    local task = store.tasks[task_id]
    if not task then
      return
    end

    if task.status ~= "running" then
      return
    end

    local started = vim.uv.hrtime()
    local context = {
      task_id = task_id,
      is_cancelled = function()
        local current_store = load_store()
        local current = current_store.tasks[task_id]
        return current ~= nil and current.cancel_requested == true
      end,
      timeout_ms = timeout_ms,
    }

    local ok, result = pcall(run_fn, context)

    store = load_store()
    task = store.tasks[task_id]
    if not task then
      return
    end

    if task.cancel_requested == true then
      task.status = "cancelled"
      task.result_summary = "cancelled"
      task.completed_at = now_iso()
      save_store(store)
      log.record({
        event = "task_cancelled",
        task_id = task_id,
        tool = "task",
        request = {
          action = "cancelled_during_run",
        },
        policy_decision = "allow",
        result = {
          status = task.status,
        },
      })
      return
    end

    local duration_ms = math.floor((vim.uv.hrtime() - started) / 1000000)
    if timeout_ms > 0 and duration_ms > timeout_ms then
      task.status = "failed"
      task.error = string.format("task timeout (%dms > %dms)", duration_ms, timeout_ms)
      task.result_summary = "timeout"
    elseif ok then
      task.status = "completed"
      task.result_summary = summarize_result(result)
      task.error = ""
    else
      task.status = "failed"
      task.error = tostring(result)
      task.result_summary = "error"
    end
    task.completed_at = now_iso()
    save_store(store)

    log.record({
      event = "task_finished",
      task_id = task_id,
      tool = "task",
      request = {
        action = "finish",
      },
      policy_decision = "allow",
      result = {
        status = task.status,
        result_summary = task.result_summary,
        duration_ms = duration_ms,
      },
      error_path = task.error,
    })
  end)
end

function M.start(spec)
  spec = spec or {}
  local store = load_store()
  local id = string.format("t-%06d", store.next_id)
  store.next_id = store.next_id + 1

  local task = {
    id = id,
    title = spec.title or "agent-task",
    kind = spec.kind or "generic",
    status = "running",
    parent_task_id = spec.parent_task_id,
    cancel_requested = false,
    resume_count = 0,
    metadata = spec.metadata or {},
    created_at = now_iso(),
    updated_at = now_iso(),
    completed_at = nil,
    error = "",
    result_summary = "",
  }

  store.tasks[id] = task
  save_store(store)

  if type(spec.run) == "function" then
    runners[id] = spec.run
    local cfg = config.get()
    local timeout_ms = tonumber(spec.timeout_ms) or tonumber(cfg.tasks.default_timeout_ms) or 5000
    run_task(id, spec.run, math.max(1, math.floor(timeout_ms)))
  end

  log.record({
    event = "task_started",
    task_id = id,
    tool = "task",
    request = {
      action = "start",
      kind = task.kind,
      title = task.title,
      parent_task_id = task.parent_task_id,
    },
    policy_decision = "allow",
    result = {
      status = task.status,
    },
  })

  return vim.deepcopy(task)
end

function M.cancel(task_id, reason)
  local ok, task_or_err = update_task(task_id, function(task)
    task.cancel_requested = true
    task.status = "cancelled"
    task.result_summary = "cancelled"
    task.error = reason or ""
    task.completed_at = now_iso()
  end)
  if not ok then
    return false, task_or_err
  end

  log.record({
    event = "task_cancelled",
    task_id = task_id,
    tool = "task",
    request = {
      action = "cancel",
      reason = reason or "",
    },
    policy_decision = "allow",
    result = {
      status = task_or_err.status,
    },
  })

  return true, vim.deepcopy(task_or_err)
end

function M.resume(task_id, spec)
  spec = spec or {}

  local store = load_store()
  local task = store.tasks[task_id]
  if not task then
    return false, "task not found: " .. tostring(task_id)
  end

  local resumable = {
    cancelled = true,
    failed = true,
    completed = true,
  }
  if not resumable[task.status] then
    return false, "task is not resumable: " .. tostring(task.status)
  end

  task.status = "running"
  task.cancel_requested = false
  task.resume_count = (task.resume_count or 0) + 1
  task.completed_at = nil
  task.error = ""
  task.updated_at = now_iso()
  save_store(store)

  local run_fn = spec.run or runners[task_id]
  if type(run_fn) == "function" then
    runners[task_id] = run_fn
    local cfg = config.get()
    local timeout_ms = tonumber(spec.timeout_ms) or tonumber(cfg.tasks.default_timeout_ms) or 5000
    run_task(task_id, run_fn, math.max(1, math.floor(timeout_ms)))
  end

  local evidence = {}
  for _, item in ipairs(log.tail(200)) do
    if item.task_id == task_id then
      table.insert(evidence, item)
    end
  end

  log.record({
    event = "task_resumed",
    task_id = task_id,
    tool = "task",
    request = {
      action = "resume",
      evidence_events = #evidence,
    },
    policy_decision = "allow",
    result = {
      status = task.status,
      resume_count = task.resume_count,
    },
  })

  return true, {
    task = vim.deepcopy(task),
    evidence_events = #evidence,
  }
end

function M.get(task_id)
  local store = load_store()
  local task = store.tasks[task_id]
  if not task then
    return nil
  end
  return vim.deepcopy(task)
end

function M.list()
  local store = load_store()
  return sorted_tasks(store.tasks)
end

function M.ancestors(task_id)
  local out = {}
  local store = load_store()
  local current = store.tasks[task_id]
  local seen = {}

  while current and current.parent_task_id do
    local parent_id = current.parent_task_id
    if seen[parent_id] then
      break
    end
    seen[parent_id] = true
    table.insert(out, parent_id)
    current = store.tasks[parent_id]
  end

  return out
end

function M.reset_for_test()
  runners = {}
  state.delete(task_file())
end

return M
