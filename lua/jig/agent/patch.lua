local config = require("jig.agent.config")
local icons = require("jig.ui.icons")
local log = require("jig.agent.log")
local state = require("jig.agent.state")

local M = {}

local function sessions_file()
  local cfg = config.get()
  return cfg.patch.persistence_file
end

local function default_store()
  return {
    version = 1,
    next_id = 1,
    sessions = {},
  }
end

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function load_store()
  local payload = state.read_json(sessions_file(), default_store())
  if type(payload.sessions) ~= "table" then
    payload.sessions = {}
  end
  if type(payload.next_id) ~= "number" then
    payload.next_id = 1
  end
  return payload
end

local function save_store(store)
  return state.write_json(sessions_file(), store)
end

local function normalize_path(path)
  return config.normalize_path(path or "")
end

local function read_lines(path)
  if vim.fn.filereadable(path) ~= 1 then
    return {}
  end
  return vim.fn.readfile(path)
end

local function write_lines(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local ok, err = pcall(vim.fn.writefile, lines, path)
  if not ok then
    return false, tostring(err)
  end
  return true, path
end

local function sorted_sessions(sessions)
  local out = {}
  for _, session in pairs(sessions or {}) do
    out[#out + 1] = session
  end
  table.sort(out, function(a, b)
    return tostring(a.id) < tostring(b.id)
  end)
  return out
end

local function hunk_status_emoji(status)
  if status == "accepted" then
    return icons.get("action")
  end
  if status == "rejected" then
    return icons.get("danger")
  end
  return icons.get("warning")
end

local function normalize_hunk(spec, file_lines)
  local start_line = tonumber(spec.start_line) or tonumber(spec.start) or 1
  local end_line = tonumber(spec.end_line) or tonumber(spec["end"]) or start_line

  start_line = math.max(1, math.floor(start_line))
  end_line = math.max(start_line, math.floor(end_line))

  local replacement = spec.replacement or spec.replacement_lines or {}
  if type(replacement) == "string" then
    replacement = vim.split(replacement, "\n", { plain = true, trimempty = false })
  end
  if type(replacement) ~= "table" then
    replacement = {}
  end

  local original = spec.original_lines
  if type(original) ~= "table" then
    original = {}
    for idx = start_line, math.min(end_line, #file_lines) do
      original[#original + 1] = file_lines[idx]
    end
  end

  return {
    start_line = start_line,
    end_line = end_line,
    original_lines = original,
    replacement_lines = replacement,
    summary = tostring(spec.summary or ""),
    status = tostring(spec.status or "pending"),
  }
end

local function normalized_files(spec_files)
  local files = {}

  for _, file_spec in ipairs(spec_files or {}) do
    local path = normalize_path(file_spec.path)
    if path and path ~= "" then
      local base_lines = read_lines(path)
      local hunks = {}

      for _, hunk_spec in ipairs(file_spec.hunks or {}) do
        hunks[#hunks + 1] = normalize_hunk(hunk_spec, base_lines)
      end

      table.sort(hunks, function(a, b)
        if a.start_line == b.start_line then
          return a.end_line < b.end_line
        end
        return a.start_line < b.start_line
      end)

      files[#files + 1] = {
        path = path,
        hunks = hunks,
        checkpoint_lines = base_lines,
      }
    end
  end

  return files
end

local function find_session(store, session_id)
  return store.sessions[tostring(session_id or "")]
end

local function validate_hunk_indices(session, file_index, hunk_index)
  local file = session.files[tonumber(file_index)]
  if not file then
    return nil, nil, "file index out of range"
  end

  local hunk = file.hunks[tonumber(hunk_index)]
  if not hunk then
    return nil, nil, "hunk index out of range"
  end

  return file, hunk, nil
end

local function update_session(session, mutator)
  mutator(session)
  session.updated_at = now_iso()
end

local function has_overlap(hunks)
  local accepted = {}
  for _, hunk in ipairs(hunks or {}) do
    if hunk.status == "accepted" then
      accepted[#accepted + 1] = hunk
    end
  end

  table.sort(accepted, function(a, b)
    return a.start_line < b.start_line
  end)

  for index = 2, #accepted do
    local prev = accepted[index - 1]
    local cur = accepted[index]
    if cur.start_line <= prev.end_line then
      return true
    end
  end

  return false
end

local function apply_hunks(base_lines, hunks)
  local accepted = {}
  for _, hunk in ipairs(hunks or {}) do
    if hunk.status == "accepted" then
      accepted[#accepted + 1] = hunk
    end
  end

  table.sort(accepted, function(a, b)
    return a.start_line < b.start_line
  end)

  local out = {}
  local cursor = 1

  for _, hunk in ipairs(accepted) do
    local start_line = math.max(1, hunk.start_line)
    local end_line = math.max(start_line - 1, hunk.end_line)

    for idx = cursor, math.min(start_line - 1, #base_lines) do
      out[#out + 1] = base_lines[idx]
    end

    for _, line in ipairs(hunk.replacement_lines or {}) do
      out[#out + 1] = tostring(line)
    end

    cursor = math.max(cursor, end_line + 1)
  end

  for idx = cursor, #base_lines do
    out[#out + 1] = base_lines[idx]
  end

  return out
end

function M.path()
  return state.path(sessions_file())
end

function M.create(spec)
  spec = spec or {}

  local files = normalized_files(spec.files)
  if #files == 0 then
    return false, "patch session requires at least one file"
  end

  local store = load_store()
  local session_id = string.format("patch-%06d", store.next_id)
  store.next_id = store.next_id + 1

  local session = {
    id = session_id,
    intent = tostring(spec.intent or "agent_candidate_patch"),
    summary = tostring(spec.summary or ""),
    source_task_id = tostring(spec.source_task_id or ""),
    status = "open",
    created_at = now_iso(),
    updated_at = now_iso(),
    applied_at = "",
    rolled_back_at = "",
    files = files,
  }

  store.sessions[session.id] = session
  save_store(store)

  log.record({
    event = "patch_session_created",
    task_id = session.source_task_id,
    tool = "agent.patch",
    request = {
      session_id = session.id,
      intent = session.intent,
      files = #session.files,
    },
    policy_decision = "allow",
    result = {
      status = session.status,
    },
  })

  return true, vim.deepcopy(session)
end

function M.list()
  local store = load_store()
  return vim.deepcopy(sorted_sessions(store.sessions))
end

function M.get(session_id)
  local store = load_store()
  local session = find_session(store, session_id)
  if not session then
    return nil
  end
  return vim.deepcopy(session)
end

function M.set_hunk_status(session_id, file_index, hunk_index, status)
  status = tostring(status or "")
  if status ~= "accepted" and status ~= "rejected" and status ~= "pending" then
    return false, "invalid hunk status: " .. status
  end

  local store = load_store()
  local session = find_session(store, session_id)
  if not session then
    return false, "patch session not found: " .. tostring(session_id)
  end

  local file, hunk, err = validate_hunk_indices(session, file_index, hunk_index)
  if err ~= nil then
    return false, err
  end

  update_session(session, function(item)
    file.hunks[tonumber(hunk_index)].status = status
    item.status = "open"
  end)
  save_store(store)

  log.record({
    event = "patch_hunk_status",
    task_id = session.source_task_id,
    tool = "agent.patch",
    request = {
      session_id = session.id,
      file_index = tonumber(file_index),
      hunk_index = tonumber(hunk_index),
      file = file.path,
    },
    policy_decision = "allow",
    result = {
      status = status,
    },
  })

  return true, vim.deepcopy(hunk)
end

function M.accept_hunk(session_id, file_index, hunk_index)
  return M.set_hunk_status(session_id, file_index, hunk_index, "accepted")
end

function M.reject_hunk(session_id, file_index, hunk_index)
  return M.set_hunk_status(session_id, file_index, hunk_index, "rejected")
end

function M.apply_all(session_id)
  local store = load_store()
  local session = find_session(store, session_id)
  if not session then
    return false, "patch session not found: " .. tostring(session_id)
  end

  update_session(session, function(item)
    for _, file in ipairs(item.files or {}) do
      for _, hunk in ipairs(file.hunks or {}) do
        hunk.status = "accepted"
      end
    end
  end)
  save_store(store)
  return true, vim.deepcopy(session)
end

function M.discard_all(session_id)
  local store = load_store()
  local session = find_session(store, session_id)
  if not session then
    return false, "patch session not found: " .. tostring(session_id)
  end

  update_session(session, function(item)
    for _, file in ipairs(item.files or {}) do
      for _, hunk in ipairs(file.hunks or {}) do
        hunk.status = "rejected"
      end
    end
    item.status = "discarded"
  end)
  save_store(store)

  log.record({
    event = "patch_discard_all",
    task_id = session.source_task_id,
    tool = "agent.patch",
    request = {
      session_id = session.id,
    },
    policy_decision = "allow",
    result = {
      status = "discarded",
    },
  })

  return true, vim.deepcopy(session)
end

function M.apply(session_id)
  local store = load_store()
  local session = find_session(store, session_id)
  if not session then
    return false, "patch session not found: " .. tostring(session_id)
  end

  for _, file in ipairs(session.files or {}) do
    if has_overlap(file.hunks) then
      return false, "accepted hunks overlap in file: " .. tostring(file.path)
    end
  end

  for _, file in ipairs(session.files or {}) do
    local base_lines = vim.deepcopy(file.checkpoint_lines or {})
    local output = apply_hunks(base_lines, file.hunks)
    local ok_write, err_write = write_lines(file.path, output)
    if not ok_write then
      return false, err_write
    end
  end

  update_session(session, function(item)
    item.status = "applied"
    item.applied_at = now_iso()
  end)
  save_store(store)

  log.record({
    event = "patch_apply",
    task_id = session.source_task_id,
    tool = "agent.patch",
    request = {
      session_id = session.id,
      files = #session.files,
    },
    policy_decision = "allow",
    result = {
      status = session.status,
    },
  })

  return true, vim.deepcopy(session)
end

function M.rollback(session_id)
  local store = load_store()
  local session = find_session(store, session_id)
  if not session then
    return false, "patch session not found: " .. tostring(session_id)
  end

  for _, file in ipairs(session.files or {}) do
    local ok_write, err_write = write_lines(file.path, file.checkpoint_lines or {})
    if not ok_write then
      return false, err_write
    end
  end

  update_session(session, function(item)
    item.status = "rolled_back"
    item.rolled_back_at = now_iso()
  end)
  save_store(store)

  log.record({
    event = "patch_rollback",
    task_id = session.source_task_id,
    tool = "agent.patch",
    request = {
      session_id = session.id,
      files = #session.files,
    },
    policy_decision = "allow",
    result = {
      status = session.status,
    },
  })

  return true, vim.deepcopy(session)
end

function M.write_direct(path, lines, opts)
  opts = opts or {}
  log.record({
    event = "patch_direct_write_denied",
    task_id = tostring(opts.task_id or ""),
    tool = "agent.patch",
    request = {
      path = normalize_path(path),
      line_count = type(lines) == "table" and #lines or 0,
    },
    policy_decision = "deny",
    result = {
      ok = false,
      reason = "patch_pipeline_required",
    },
    error_path = "Direct writes are blocked. Create a patch session and apply reviewed hunks.",
  })

  return {
    ok = false,
    reason = "patch_pipeline_required",
    hint = "Use patch session commands (:JigPatchReview, :JigPatchApply, :JigPatchRollback).",
  }
end

function M.render_review_lines(session)
  local lines = {
    "Jig Patch Review",
    string.rep("=", 48),
    "session: " .. tostring(session.id),
    "intent: " .. tostring(session.intent),
    "summary: " .. tostring(session.summary),
    "status: " .. tostring(session.status),
    "",
    "files:",
  }

  for file_index, file in ipairs(session.files or {}) do
    lines[#lines + 1] = string.format("[%d] %s", file_index, tostring(file.path))
    for hunk_index, hunk in ipairs(file.hunks or {}) do
      lines[#lines + 1] = string.format(
        "  %s hunk=%d range=%d-%d status=%s %s",
        hunk_status_emoji(hunk.status),
        hunk_index,
        tonumber(hunk.start_line) or 0,
        tonumber(hunk.end_line) or 0,
        tostring(hunk.status),
        tostring(hunk.summary or "")
      )
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] =
    "commands: :JigPatchHunkAccept/:JigPatchHunkReject/:JigPatchApplyAll/:JigPatchDiscardAll/:JigPatchApply/:JigPatchRollback"
  lines[#lines + 1] = "drill-down: :JigPatchHunkShow <session> <file_index> <hunk_index>"

  return lines
end

function M.render_hunk_lines(session, file_index, hunk_index)
  local file, hunk, err = validate_hunk_indices(session, file_index, hunk_index)
  if err ~= nil then
    return false, err
  end

  local old_count = #(hunk.original_lines or {})
  local new_count = #(hunk.replacement_lines or {})

  local lines = {
    "Jig Patch Hunk",
    string.rep("=", 48),
    "session: " .. tostring(session.id),
    "file: " .. tostring(file.path),
    string.format("range: %d-%d", hunk.start_line, hunk.end_line),
    "status: " .. tostring(hunk.status),
    "summary: " .. tostring(hunk.summary or ""),
    "",
    "--- " .. tostring(file.path),
    "+++ " .. tostring(file.path),
    string.format("@@ -%d,%d +%d,%d @@", hunk.start_line, old_count, hunk.start_line, new_count),
  }

  for _, line in ipairs(hunk.original_lines or {}) do
    lines[#lines + 1] = "-" .. tostring(line)
  end
  for _, line in ipairs(hunk.replacement_lines or {}) do
    lines[#lines + 1] = "+" .. tostring(line)
  end

  return true, lines
end

local function open_scratch(name, lines)
  if #vim.api.nvim_list_uis() == 0 then
    vim.g.jig_patch_last_report = {
      name = name,
      lines = lines,
    }
    return {
      headless = true,
      name = name,
      lines = lines,
    }
  end

  vim.cmd("botright new")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = "jigpatch"
  vim.api.nvim_buf_set_name(bufnr, name)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  return {
    bufnr = bufnr,
    win = vim.api.nvim_get_current_win(),
  }
end

function M.open_review(session_id)
  local session = M.get(session_id)
  if not session then
    return false, "patch session not found: " .. tostring(session_id)
  end

  local lines = M.render_review_lines(session)
  local view = open_scratch("JigPatchReview", lines)
  view.session_id = session.id
  return true, view
end

function M.open_hunk(session_id, file_index, hunk_index)
  local session = M.get(session_id)
  if not session then
    return false, "patch session not found: " .. tostring(session_id)
  end

  local ok_lines, lines_or_err = M.render_hunk_lines(session, file_index, hunk_index)
  if not ok_lines then
    return false, lines_or_err
  end

  local lines = lines_or_err
  if #vim.api.nvim_list_uis() == 0 then
    vim.g.jig_patch_last_hunk = {
      session_id = session.id,
      file_index = file_index,
      hunk_index = hunk_index,
      lines = lines,
    }
    return true, {
      headless = true,
      lines = lines,
    }
  end

  local ok_float, float = pcall(require, "jig.ui.float")
  if ok_float and type(float.open) == "function" then
    local buf, win = float.open(lines, {
      title = "Jig Hunk",
      level = "secondary",
      width = math.max(60, math.floor(vim.o.columns * 0.6)),
      height = math.min(22, math.floor(vim.o.lines * 0.65)),
    })
    return true, {
      bufnr = buf,
      win = win,
    }
  end

  local view = open_scratch("JigPatchHunk", lines)
  return true, view
end

function M.reset_for_test()
  state.delete(sessions_file())
end

return M
