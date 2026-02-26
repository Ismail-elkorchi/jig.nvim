local config = require("jig.agent.config")
local log = require("jig.agent.log")
local state = require("jig.agent.state")

local M = {}

local once_allowances = {}

local valid_resolution = {
  allow = true,
  deny = true,
  allow_once = true,
  deny_once = true,
  allow_always = true,
  deny_always = true,
}

local function approvals_file()
  local cfg = config.get()
  return cfg.approvals.persistence_file
end

local function default_store()
  return {
    version = 1,
    next_id = 1,
    entries = {},
  }
end

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function normalize_subject(subject)
  subject = subject or {}
  local cfg = config.get()
  local project_root = config.normalize_path(subject.project_root or cfg.root)

  local ancestors = {}
  if type(subject.ancestor_task_ids) == "table" then
    for _, item in ipairs(subject.ancestor_task_ids) do
      if type(item) == "string" and item ~= "" then
        ancestors[#ancestors + 1] = item
      end
    end
  end
  table.sort(ancestors)

  return {
    tool = tostring(subject.tool or ""),
    action_class = tostring(subject.action_class or "unknown"),
    target = tostring(subject.target or "*"),
    task_id = type(subject.task_id) == "string" and subject.task_id or "",
    project_root = project_root or "",
    ancestor_task_ids = ancestors,
  }
end

local function subject_key(subject)
  local normalized = normalize_subject(subject)
  local chunks = {
    normalized.tool,
    normalized.action_class,
    normalized.target,
    normalized.task_id,
    normalized.project_root,
    table.concat(normalized.ancestor_task_ids or {}, ","),
  }
  return table.concat(chunks, "|")
end

local function load_store()
  local store = state.read_json(approvals_file(), default_store())
  if type(store.entries) ~= "table" then
    store.entries = {}
  end
  if type(store.next_id) ~= "number" then
    store.next_id = 1
  end
  return store
end

local function save_store(store)
  return state.write_json(approvals_file(), store)
end

local function sorted_entries(entries)
  local out = {}
  for _, entry in ipairs(entries or {}) do
    out[#out + 1] = entry
  end
  table.sort(out, function(a, b)
    return tostring(a.id) < tostring(b.id)
  end)
  return out
end

local function sync_indicator(store)
  local source = store or load_store()
  local pending = 0
  for _, entry in ipairs(source.entries or {}) do
    if entry.status == "pending" then
      pending = pending + 1
    end
  end
  vim.g.jig_agent_pending_approvals = pending
  local ok_chrome, chrome = pcall(require, "jig.ui.chrome")
  if ok_chrome and type(chrome.refresh) == "function" then
    pcall(chrome.refresh)
  end
  return pending
end

local function to_notification(entry)
  return string.format(
    "approval required [%s] tool=%s action=%s target=%s",
    tostring(entry.id),
    tostring(entry.subject.tool),
    tostring(entry.subject.action_class),
    tostring(entry.subject.target)
  )
end

local function find_entry(store, id)
  for index, entry in ipairs(store.entries or {}) do
    if entry.id == id then
      return entry, index
    end
  end
  return nil, nil
end

local function record(event, entry, extra)
  local payload = {
    event = event,
    task_id = entry.subject and entry.subject.task_id or "",
    tool = entry.subject and entry.subject.tool or "",
    request = {
      action_class = entry.subject and entry.subject.action_class or "",
      target = entry.subject and entry.subject.target or "",
      approval_id = entry.id,
      reason = entry.reason,
      origin = entry.origin,
    },
    policy_decision = entry.decision or "ask",
    result = {
      status = entry.status,
      resolution = entry.resolution,
    },
    error_path = entry.hint or "",
  }

  if type(extra) == "table" then
    payload.result = vim.tbl_deep_extend("force", payload.result, extra)
  end

  log.record(payload)
end

function M.path()
  return state.path(approvals_file())
end

function M.list(opts)
  opts = opts or {}
  local status = opts.status and tostring(opts.status) or nil
  local store = load_store()
  local out = {}

  for _, entry in ipairs(sorted_entries(store.entries)) do
    if status == nil or entry.status == status then
      out[#out + 1] = vim.deepcopy(entry)
    end
  end

  return out
end

function M.get(id)
  local store = load_store()
  local entry = find_entry(store, tostring(id or ""))
  if not entry then
    return nil
  end
  return vim.deepcopy(entry)
end

function M.pending_count()
  return sync_indicator()
end

function M.enqueue(subject, opts)
  opts = opts or {}

  local normalized = normalize_subject(subject)
  local key = subject_key(normalized)
  local store = load_store()

  for _, entry in ipairs(store.entries) do
    if entry.status == "pending" and entry.subject_key == key then
      sync_indicator(store)
      return vim.deepcopy(entry), false
    end
  end

  local id = string.format("a-%06d", store.next_id)
  store.next_id = store.next_id + 1

  local entry = {
    id = id,
    status = "pending",
    created_at = now_iso(),
    updated_at = now_iso(),
    resolved_at = "",
    decision = tostring(opts.decision or "ask"),
    reason = tostring(opts.reason or "policy_ask"),
    hint = tostring(opts.hint or "Approval required."),
    origin = tostring(opts.origin or "unknown"),
    summary = tostring(opts.summary or ""),
    subject = normalized,
    subject_key = key,
    resolution = "",
    resolution_note = "",
    rule_id = "",
  }

  store.entries[#store.entries + 1] = entry
  save_store(store)
  local pending = sync_indicator(store)

  record("approval_pending", entry, {
    pending_total = pending,
  })

  if opts.notify ~= false and #vim.api.nvim_list_uis() > 0 then
    vim.notify(to_notification(entry), vim.log.levels.WARN)
  end

  return vim.deepcopy(entry), true
end

function M.consume_once_allowance(subject)
  local key = subject_key(subject)
  local value = tonumber(once_allowances[key]) or 0
  if value <= 0 then
    return false
  end
  once_allowances[key] = value - 1
  if once_allowances[key] <= 0 then
    once_allowances[key] = nil
  end
  return true
end

function M.resolve(id, resolution, opts)
  opts = opts or {}
  local normalized_resolution = tostring(resolution or "")
  if not valid_resolution[normalized_resolution] then
    return false, "invalid resolution: " .. normalized_resolution
  end

  local store = load_store()
  local entry = find_entry(store, tostring(id or ""))
  if not entry then
    return false, "approval not found: " .. tostring(id)
  end

  if entry.status ~= "pending" then
    return false, "approval is not pending: " .. tostring(id)
  end

  entry.status = "resolved"
  entry.resolution = normalized_resolution
  entry.resolution_note = tostring(opts.note or "")
  entry.rule_id = tostring(opts.rule_id or "")
  entry.updated_at = now_iso()
  entry.resolved_at = entry.updated_at

  if normalized_resolution == "allow_once" or normalized_resolution == "allow" then
    local key = subject_key(entry.subject)
    once_allowances[key] = (tonumber(once_allowances[key]) or 0) + 1
  elseif normalized_resolution == "allow_always" then
    local key = subject_key(entry.subject)
    once_allowances[key] = (tonumber(once_allowances[key]) or 0) + 1
  end

  save_store(store)
  local pending = sync_indicator(store)

  record("approval_resolved", entry, {
    pending_total = pending,
    rule_id = entry.rule_id,
  })

  return true, vim.deepcopy(entry)
end

function M.reset_for_test()
  once_allowances = {}
  local store = default_store()
  save_store(store)
  sync_indicator(store)
end

sync_indicator()

return M
