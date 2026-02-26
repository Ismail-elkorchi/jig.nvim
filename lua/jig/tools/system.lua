local M = {}

local queue_state = {
  queue = {},
  active_capture = 0,
  next_id = 0,
}

local function now_ms()
  return math.floor(vim.uv.hrtime() / 1000000)
end

local function defaults()
  local user = vim.g.jig_tools_system
  if type(user) ~= "table" then
    user = {}
  end

  return vim.tbl_deep_extend("force", {
    timeout_ms = 8000,
    capture_concurrency = 1,
    parallel_capture_concurrency = 4,
    text = true,
  }, user)
end

local function copy_argv(argv)
  local out = {}
  for _, value in ipairs(argv or {}) do
    table.insert(out, tostring(value))
  end
  return out
end

local function default_cwd(opts)
  if type(opts.cwd) == "string" and opts.cwd ~= "" then
    return opts.cwd
  end

  local ok, root = pcall(require, "jig.nav.root")
  if ok and type(root.resolve) == "function" then
    local resolved = root.resolve({ path = opts.path })
    if type(resolved) == "table" and type(resolved.root) == "string" and resolved.root ~= "" then
      return resolved.root
    end
  end

  return vim.uv.cwd()
end

local function normalize_argv(argv)
  if type(argv) ~= "table" then
    return false, nil, "argv must be an array"
  end
  if #argv == 0 then
    return false, nil, "argv must contain at least one executable"
  end

  local normalized = {}
  for index, value in ipairs(argv) do
    if value == nil then
      return false, nil, string.format("argv[%d] is nil", index)
    end
    local token = tostring(value)
    if token == "" then
      return false, nil, string.format("argv[%d] is empty", index)
    end
    table.insert(normalized, token)
  end

  return true, normalized, nil
end

local function mk_hint(reason)
  local hints = {
    spawn_error = "Check executable path and run :JigToolHealth for install hints.",
    timeout = "Increase timeout_ms or use :JigTerm for long-running interactive commands.",
    system_wait_nil = "This matches known Neovim wait() edge cases. Retry or increase timeout_ms.",
    system_wait_error = "wait() raised an error. Retry and inspect stderr for platform shell mismatch.",
    exit_nonzero = "Command exited non-zero. Inspect stderr and rerun manually if needed.",
    startup_network_denied = "Startup network policy denied this command. "
      .. "Review trace and allowlist only trusted entries.",
    ["destructive-requires-override"] = "Destructive command blocked. Re-run with :JigExec! only if intentional.",
    ["destructive-denied-non-user"] = "Destructive command denied for non-user actors.",
    destructive_requires_override = "Destructive command blocked. Re-run with :JigExec! only if intentional.",
    destructive_denied_non_user = "Destructive command denied for non-user actors.",
    workspace_boundary_escape = "Target is outside project root. "
      .. "Use explicit outside-root approval token only when required.",
    unicode_trojan_source = "Hidden/bidi unicode was detected in patch payload; inspect and sanitize content.",
    argument_injection_pattern = "Suspicious argument-injection pattern detected; rewrite command as safe argv tokens.",
    prompt_injection_tool_misuse = "Prompt/tool-output matched injection pattern on high-risk action; "
      .. "request explicit review.",
    consent_identity_confusion = "Approval identity mismatch detected; "
      .. "request a fresh approval for this actor/tool pair.",
    pre_hook_error = "Security pre-tool hook failed; inspect hook implementation and retry.",
    pre_hook_denied = "Security pre-tool hook denied this action.",
  }
  return hints[reason] or "Run :JigToolHealth to inspect shell/tool integration status."
end

local function classify_nonzero(result)
  local stderr = (result.stderr or ""):lower()
  if result.code == 124 then
    return "timeout"
  end
  if stderr:find("timed out", 1, true) then
    return "timeout"
  end
  return "exit_nonzero"
end

local function build_result(wait_result, meta)
  local result = {
    ok = false,
    code = -1,
    signal = nil,
    stdout = "",
    stderr = "",
    reason = "spawn_error",
    hint = mk_hint("spawn_error"),
    argv = copy_argv(meta.argv),
    cwd = meta.cwd,
    timeout_ms = meta.timeout_ms,
    started_at = meta.started_at,
    finished_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    duration_ms = now_ms() - meta.started_ms,
    queue_id = meta.queue_id,
    security = meta.security or {},
  }

  if wait_result == nil then
    result.reason = "system_wait_nil"
    result.hint = mk_hint(result.reason)
    result.stderr = "vim.system():wait(timeout_ms) returned nil"
    return result
  end

  if type(wait_result) ~= "table" then
    result.reason = "system_wait_error"
    result.hint = mk_hint(result.reason)
    result.stderr = "vim.system():wait(timeout_ms) returned invalid payload"
    return result
  end

  result.code = wait_result.code or -1
  result.signal = wait_result.signal
  result.stdout = wait_result.stdout or ""
  result.stderr = wait_result.stderr or ""

  if result.code == 0 then
    result.ok = true
    result.reason = nil
    result.hint = ""
    if result.security.exec_safety and result.security.exec_safety.override_used then
      result.override_used = true
      result.override_warning =
        "Warning: destructive command override was used; event recorded in audit log."
    end
    return result
  end

  result.reason = classify_nonzero(result)
  result.hint = mk_hint(result.reason)
  if result.security.exec_safety and result.security.exec_safety.override_used then
    result.override_used = true
    result.override_warning =
      "Warning: destructive command override was used; event recorded in audit log."
  end
  return result
end

local function synthetic_result(meta, reason, stderr, extra)
  local result = {
    ok = false,
    code = -1,
    signal = nil,
    stdout = "",
    stderr = stderr or "",
    reason = reason,
    hint = mk_hint(reason),
    argv = copy_argv(meta.argv),
    cwd = meta.cwd,
    timeout_ms = meta.timeout_ms,
    started_at = meta.started_at,
    finished_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    duration_ms = now_ms() - meta.started_ms,
    queue_id = meta.queue_id,
    security = meta.security or {},
  }
  if type(extra) == "table" then
    for key, value in pairs(extra) do
      result[key] = value
    end
  end
  return result
end

local function build_system_opts(opts, cwd)
  local sys_opts = {
    text = opts.text,
    cwd = cwd,
  }

  if type(opts.env) == "table" then
    sys_opts.env = opts.env
  end

  if opts.clear_env == true then
    sys_opts.clear_env = true
  end

  if opts.stdin ~= nil then
    sys_opts.stdin = opts.stdin
  end

  if opts.detach == true then
    sys_opts.detach = true
  end

  if opts.shell == true then
    sys_opts.shell = true
  end

  return sys_opts
end

local function capture_limit(opts)
  local cfg = defaults()
  local requested = tonumber(opts.capture_concurrency or cfg.capture_concurrency)
    or cfg.capture_concurrency
  requested = math.max(1, math.floor(requested))

  if opts.allow_parallel_capture == true then
    local parallel_default = tonumber(cfg.parallel_capture_concurrency) or 4
    local parallel = tonumber(opts.capture_concurrency) or parallel_default
    return math.max(2, math.floor(parallel))
  end

  return math.min(1, requested)
end

local function should_capture(opts)
  return opts.text == true
end

local function security_gate(argv, opts, meta)
  local actor = opts.actor or "user"
  local origin = opts.origin or "jig.tools.system"
  local task_id = opts.task_id
  local security = {}

  local ok_gate, gate = pcall(require, "jig.security.gate")
  if ok_gate and type(gate.pre_tool_call) == "function" then
    local pre = gate.pre_tool_call({
      actor = actor,
      origin = origin,
      task_id = task_id,
      action = opts.action or "exec.run",
      target = opts.target or argv[1] or "",
      target_path = opts.target_path,
      project_root = opts.project_root,
      argv = argv,
      prompt_text = opts.prompt_text,
      patch_lines = opts.patch_lines,
      approval_id = opts.approval_id,
      approval_actor = opts.approval_actor,
      approval_tool = opts.approval_tool,
      confirmation_token = opts.confirmation_token,
      allow_outside_root = opts.allow_outside_root == true,
      cwd = meta.cwd,
    })
    security.pre_tool_call = pre
    if pre.allowed ~= true then
      meta.security = security
      local blocked = synthetic_result(meta, pre.reason, pre.hint or pre.reason, {
        reason = pre.reason,
        security = security,
      })
      if type(gate.post_tool_call) == "function" then
        gate.post_tool_call(pre, blocked, {
          actor = actor,
          origin = origin,
          task_id = task_id,
          target = opts.target or argv[1] or "",
          subagent = opts.subagent,
          approval_id = opts.approval_id,
        })
      end
      return false, blocked
    end
  end

  local ok_net, net_guard = pcall(require, "jig.security.net_guard")
  if ok_net and type(net_guard.evaluate_argv) == "function" then
    local net_report = net_guard.evaluate_argv(argv, {
      actor = actor,
      origin = origin,
      task_id = task_id,
      allow_network = opts.allow_network == true,
    })
    security.net_guard = net_report
    if net_report.allowed ~= true then
      meta.security = security
      local blocked =
        synthetic_result(meta, "startup_network_denied", net_report.hint or net_report.reason, {
          reason = "startup_network_denied",
          security = security,
        })
      if
        ok_gate
        and type(gate.post_tool_call) == "function"
        and type(security.pre_tool_call) == "table"
      then
        gate.post_tool_call(security.pre_tool_call, blocked, {
          actor = actor,
          origin = origin,
          task_id = task_id,
          target = opts.target or argv[1] or "",
          subagent = opts.subagent,
          approval_id = opts.approval_id,
        })
      end
      return false, blocked
    end
  end

  local ok_exec, exec_safety = pcall(require, "jig.security.exec_safety")
  if ok_exec and type(exec_safety.evaluate) == "function" then
    local exec_report = exec_safety.evaluate(argv, {
      actor = actor,
      origin = origin,
      task_id = task_id,
      override = opts.override_destructive == true,
    })
    security.exec_safety = exec_report
    if exec_report.allowed ~= true then
      meta.security = security
      local blocked =
        synthetic_result(meta, exec_report.reason, exec_report.hint or exec_report.reason, {
          reason = exec_report.reason,
          security = security,
        })
      if
        ok_gate
        and type(gate.post_tool_call) == "function"
        and type(security.pre_tool_call) == "table"
      then
        gate.post_tool_call(security.pre_tool_call, blocked, {
          actor = actor,
          origin = origin,
          task_id = task_id,
          target = opts.target or argv[1] or "",
          subagent = opts.subagent,
          approval_id = opts.approval_id,
        })
      end
      return false, blocked
    end
  end

  meta.security = security
  return true, nil
end

local function dequeue()
  if #queue_state.queue == 0 then
    return nil
  end
  local job = queue_state.queue[1]
  table.remove(queue_state.queue, 1)
  return job
end

local function pump_queue()
  while #queue_state.queue > 0 do
    local job = queue_state.queue[1]
    if job.capture and queue_state.active_capture >= job.capture_limit then
      return
    end

    dequeue()
    if job.capture then
      queue_state.active_capture = queue_state.active_capture + 1
    end

    local ok_spawn, proc_or_err = pcall(vim.system, job.argv, job.system_opts, function(wait_result)
      local result = build_result(wait_result, job.meta)
      local pre = job.meta.security and job.meta.security.pre_tool_call
      if type(pre) == "table" then
        local ok_gate, gate = pcall(require, "jig.security.gate")
        if ok_gate and type(gate.post_tool_call) == "function" then
          gate.post_tool_call(pre, result, job.security_context or {})
        end
      end
      if job.capture then
        queue_state.active_capture = math.max(0, queue_state.active_capture - 1)
      end

      if type(job.on_exit) == "function" then
        local ok_cb, cb_err = pcall(job.on_exit, result)
        if not ok_cb then
          vim.schedule(function()
            vim.notify("Jig system callback failed: " .. tostring(cb_err), vim.log.levels.ERROR)
          end)
        end
      end

      pump_queue()
    end)

    if not ok_spawn then
      local result = synthetic_result(job.meta, "spawn_error", tostring(proc_or_err))
      local pre = job.meta.security and job.meta.security.pre_tool_call
      if type(pre) == "table" then
        local ok_gate, gate = pcall(require, "jig.security.gate")
        if ok_gate and type(gate.post_tool_call) == "function" then
          gate.post_tool_call(pre, result, job.security_context or {})
        end
      end
      if job.capture then
        queue_state.active_capture = math.max(0, queue_state.active_capture - 1)
      end
      if type(job.on_exit) == "function" then
        job.on_exit(result)
      end
      pump_queue()
      return
    end

    job.handle = proc_or_err
  end
end

function M.run(argv, opts)
  opts = opts or {}
  local cfg = defaults()
  local timeout_ms = tonumber(opts.timeout_ms) or cfg.timeout_ms
  timeout_ms = math.max(1, math.floor(timeout_ms))

  local ok_argv, normalized_argv, argv_err = normalize_argv(argv)
  local cwd = default_cwd(opts)
  queue_state.next_id = queue_state.next_id + 1
  local queue_id = queue_state.next_id

  local meta = {
    argv = ok_argv and normalized_argv or copy_argv(argv),
    cwd = cwd,
    timeout_ms = timeout_ms,
    started_ms = now_ms(),
    started_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    queue_id = queue_id,
    security = {},
  }

  if not ok_argv then
    local result = synthetic_result(meta, "spawn_error", argv_err)
    if type(opts.on_exit) == "function" then
      opts.on_exit(result)
    end
    return {
      id = queue_id,
      queued = false,
      capture = false,
      error = argv_err,
      result = result,
    }
  end

  local allowed, blocked = security_gate(normalized_argv, opts, meta)
  if not allowed then
    if type(opts.on_exit) == "function" then
      opts.on_exit(blocked)
    end
    return {
      id = queue_id,
      queued = false,
      capture = false,
      error = blocked.reason,
      result = blocked,
    }
  end

  local run_opts = vim.tbl_deep_extend("force", cfg, opts)
  run_opts.text = opts.text ~= false
  local capture = should_capture(run_opts)
  local limit = capture and capture_limit(run_opts) or 0

  local job = {
    argv = normalized_argv,
    system_opts = build_system_opts(run_opts, cwd),
    on_exit = opts.on_exit,
    capture = capture,
    capture_limit = limit,
    meta = meta,
    security_context = {
      actor = opts.actor or "user",
      origin = opts.origin or "jig.tools.system",
      task_id = opts.task_id,
      subagent = opts.subagent,
      target = opts.target or normalized_argv[1] or "",
      approval_id = opts.approval_id,
      server = opts.server,
    },
  }

  table.insert(queue_state.queue, job)
  pump_queue()

  return {
    id = queue_id,
    queued = #queue_state.queue > 0,
    capture = capture,
    timeout_ms = timeout_ms,
    cwd = cwd,
    argv = copy_argv(normalized_argv),
  }
end

function M.run_sync(argv, opts)
  opts = opts or {}
  local cfg = defaults()
  local timeout_ms = tonumber(opts.timeout_ms) or cfg.timeout_ms
  timeout_ms = math.max(1, math.floor(timeout_ms))

  local ok_argv, normalized_argv, argv_err = normalize_argv(argv)
  local cwd = default_cwd(opts)

  local meta = {
    argv = ok_argv and normalized_argv or copy_argv(argv),
    cwd = cwd,
    timeout_ms = timeout_ms,
    started_ms = now_ms(),
    started_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    queue_id = -1,
    security = {},
  }

  if not ok_argv then
    return synthetic_result(meta, "spawn_error", argv_err)
  end

  local allowed, blocked = security_gate(normalized_argv, opts, meta)
  if not allowed then
    return blocked
  end

  local run_opts = vim.tbl_deep_extend("force", cfg, opts)
  run_opts.text = opts.text ~= false
  local system_opts = build_system_opts(run_opts, cwd)

  local ok_spawn, proc_or_err = pcall(vim.system, normalized_argv, system_opts)
  if not ok_spawn then
    local spawn_result = synthetic_result(meta, "spawn_error", tostring(proc_or_err))
    local pre = meta.security and meta.security.pre_tool_call
    if type(pre) == "table" then
      local ok_gate, gate = pcall(require, "jig.security.gate")
      if ok_gate and type(gate.post_tool_call) == "function" then
        gate.post_tool_call(pre, spawn_result, {
          actor = opts.actor or "user",
          origin = opts.origin or "jig.tools.system",
          task_id = opts.task_id,
          subagent = opts.subagent,
          target = opts.target or normalized_argv[1] or "",
          approval_id = opts.approval_id,
          server = opts.server,
        })
      end
    end
    return spawn_result
  end

  local ok_wait, wait_result = pcall(proc_or_err.wait, proc_or_err, timeout_ms)
  if not ok_wait then
    local wait_error = synthetic_result(meta, "system_wait_error", tostring(wait_result))
    local pre = meta.security and meta.security.pre_tool_call
    if type(pre) == "table" then
      local ok_gate, gate = pcall(require, "jig.security.gate")
      if ok_gate and type(gate.post_tool_call) == "function" then
        gate.post_tool_call(pre, wait_error, {
          actor = opts.actor or "user",
          origin = opts.origin or "jig.tools.system",
          task_id = opts.task_id,
          subagent = opts.subagent,
          target = opts.target or normalized_argv[1] or "",
          approval_id = opts.approval_id,
          server = opts.server,
        })
      end
    end
    return wait_error
  end

  local result = build_result(wait_result, meta)
  if result.reason == "exit_nonzero" and result.duration_ms >= timeout_ms then
    result.reason = "timeout"
    result.hint = mk_hint("timeout")
  end

  local pre = meta.security and meta.security.pre_tool_call
  if type(pre) == "table" then
    local ok_gate, gate = pcall(require, "jig.security.gate")
    if ok_gate and type(gate.post_tool_call) == "function" then
      gate.post_tool_call(pre, result, {
        actor = opts.actor or "user",
        origin = opts.origin or "jig.tools.system",
        task_id = opts.task_id,
        subagent = opts.subagent,
        target = opts.target or normalized_argv[1] or "",
        approval_id = opts.approval_id,
        server = opts.server,
      })
    end
  end

  return result
end

function M.format_result_lines(result)
  local lines = {
    "JigExec Result",
    string.rep("=", 48),
    string.format("ok: %s", tostring(result.ok)),
    string.format("code: %s", tostring(result.code)),
    string.format("reason: %s", result.reason or "none"),
    string.format("duration_ms: %d", tonumber(result.duration_ms) or -1),
    string.format("timeout_ms: %d", tonumber(result.timeout_ms) or -1),
    string.format("cwd: %s", result.cwd or ""),
    string.format("argv: %s", table.concat(result.argv or {}, " ")),
  }

  if type(result.hint) == "string" and result.hint ~= "" then
    table.insert(lines, "hint: " .. result.hint)
  end

  if result.override_warning ~= nil and result.override_warning ~= "" then
    table.insert(lines, "warning: " .. result.override_warning)
  end

  table.insert(lines, "")
  table.insert(lines, "stdout:")
  if result.stdout ~= "" then
    vim.list_extend(lines, vim.split(result.stdout, "\n", { plain = true }))
  else
    table.insert(lines, "<empty>")
  end

  table.insert(lines, "")
  table.insert(lines, "stderr:")
  if result.stderr ~= "" then
    vim.list_extend(lines, vim.split(result.stderr, "\n", { plain = true }))
  else
    table.insert(lines, "<empty>")
  end

  return lines
end

function M.queue_state()
  return {
    queued = #queue_state.queue,
    active_capture = queue_state.active_capture,
  }
end

return M
