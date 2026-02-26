local security_config = require("jig.security.config")

local M = {}

local HIDDEN_CODEPOINTS = {
  [0x200B] = true,
  [0x200C] = true,
  [0x200D] = true,
  [0x200E] = true,
  [0x200F] = true,
  [0x061C] = true,
  [0x2060] = true,
  [0xFEFF] = true,
  [0x00AD] = true,
}

local HIDDEN_RANGES = {
  { 0x202A, 0x202E },
  { 0x2066, 0x2069 },
}

local HIGH_RISK_CAPABILITIES = {
  ["fs.write"] = true,
  ["fs.delete"] = true,
  ["exec.run"] = true,
  ["net.http"] = true,
  ["vcs.git"] = true,
  ["editor.patch_apply"] = true,
}

local SHELL_LIKE = {
  sh = true,
  bash = true,
  zsh = true,
  fish = true,
  pwsh = true,
  powershell = true,
  cmd = true,
}

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function normalize_slashes(path)
  local token = tostring(path or ""):gsub("\\", "/")
  token = token:gsub("/+$", "")
  if token == "" then
    return "/"
  end
  return token
end

local function parent_path(path)
  local parent = vim.fn.fnamemodify(path, ":h")
  if parent == path then
    return nil
  end
  return parent
end

local function normalize_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  local expanded = vim.fn.fnamemodify(path, ":p")
  local real = vim.uv.fs_realpath(expanded)
  if real then
    return normalize_slashes(real)
  end

  local suffix = {}
  local probe = expanded
  while type(probe) == "string" and probe ~= "" do
    local resolved = vim.uv.fs_realpath(probe)
    if resolved then
      local base = normalize_slashes(resolved)
      if #suffix == 0 then
        return base
      end

      local tail = {}
      for index = #suffix, 1, -1 do
        tail[#tail + 1] = suffix[index]
      end

      return normalize_slashes(base .. "/" .. table.concat(tail, "/"))
    end

    local tail = vim.fn.fnamemodify(probe, ":t")
    if tail ~= nil and tail ~= "" and tail ~= "." then
      suffix[#suffix + 1] = tail
    end

    local parent = parent_path(probe)
    if parent == nil then
      break
    end
    probe = parent
  end

  return normalize_slashes(expanded)
end

local function path_within_root(path, root)
  if type(path) ~= "string" or type(root) ~= "string" then
    return false
  end
  if path == root then
    return true
  end
  return path:sub(1, #root + 1) == (root .. "/")
end

local function resolve_root(spec)
  local candidate = normalize_path(spec.project_root or "")
  if candidate ~= nil then
    return candidate
  end

  local ok_root, root = pcall(require, "jig.nav.root")
  if ok_root and type(root.resolve) == "function" then
    local resolved = root.resolve({
      path = spec.target_path or spec.cwd,
    })
    if type(resolved) == "table" and type(resolved.root) == "string" then
      return normalize_path(resolved.root)
    end
  end

  if type(spec.cwd) == "string" and spec.cwd ~= "" then
    return normalize_path(spec.cwd)
  end

  return normalize_path(vim.uv.cwd())
end

local function codepoint_hidden(codepoint)
  if HIDDEN_CODEPOINTS[codepoint] == true then
    return true
  end
  for _, range in ipairs(HIDDEN_RANGES) do
    if codepoint >= range[1] and codepoint <= range[2] then
      return true
    end
  end
  return false
end

local function hidden_in_line(line)
  local ok, values = pcall(vim.fn.str2list, tostring(line or ""), 1)
  if not ok or type(values) ~= "table" then
    return false, nil
  end

  for _, codepoint in ipairs(values) do
    if codepoint_hidden(codepoint) then
      return true, codepoint
    end
  end

  return false, nil
end

local function find_hidden_unicode(lines)
  for index, line in ipairs(lines or {}) do
    local hidden, codepoint = hidden_in_line(tostring(line or ""))
    if hidden then
      return {
        line = index,
        codepoint = codepoint,
      }
    end
  end
  return nil
end

local function capability_for_action(action)
  local token = tostring(action or ""):lower()
  local map = {
    read = "fs.read",
    write = "fs.write",
    delete = "fs.delete",
    shell = "exec.run",
    net = "net.http",
    git = "vcs.git",
    patch_apply = "editor.patch_apply",
    ["fs.read"] = "fs.read",
    ["fs.write"] = "fs.write",
    ["fs.delete"] = "fs.delete",
    ["exec.run"] = "exec.run",
    ["net.http"] = "net.http",
    ["vcs.git"] = "vcs.git",
    ["editor.patch_apply"] = "editor.patch_apply",
  }
  return map[token] or token
end

local function normalize_token(value)
  local token = tostring(value or "")
  token = token:gsub("^%s+", ""):gsub("%s+$", "")
  token = token:gsub("^['\"]", ""):gsub("['\"]$", "")
  token = token:gsub("\\", "/")
  token = token:match("([^/]+)$") or token
  token = token:lower():gsub("%.exe$", "")
  return token
end

local function detect_argument_injection(argv)
  if type(argv) ~= "table" or #argv == 0 then
    return false, ""
  end

  local command = normalize_token(argv[1])
  local joined = table.concat(argv, " ")
  local patterns = { "&&", "||", ";", "`", "$(", "|", "\n" }

  if SHELL_LIKE[command] then
    for _, pattern in ipairs(patterns) do
      if joined:find(pattern, 1, true) ~= nil then
        return true, pattern
      end
    end
  end

  for _, token in ipairs(argv) do
    local current = tostring(token)
    if current:find("&&", 1, true) ~= nil or current:find("||", 1, true) ~= nil then
      return true, current
    end
    if current:find(";", 1, true) ~= nil then
      return true, current
    end
  end

  return false, ""
end

local function prompt_patterns(cfg)
  local configured = cfg.gate and cfg.gate.prompt_injection_patterns or {}
  if type(configured) == "table" and #configured > 0 then
    return configured
  end

  return {
    "ignore previous instructions",
    "ignore all previous instructions",
    "system prompt",
    "developer prompt",
    "call tool",
    "execute command",
    "run shell",
    "curl ",
    "wget ",
    "exfiltrate",
    "send secrets",
  }
end

local function detect_prompt_injection(text, cfg)
  local lowered = tostring(text or ""):lower()
  if lowered == "" then
    return false, ""
  end

  for _, pattern in ipairs(prompt_patterns(cfg)) do
    local token = tostring(pattern):lower()
    if token ~= "" and lowered:find(token, 1, true) ~= nil then
      return true, token
    end
  end

  return false, ""
end

local function apply_pre_hook(report, spec, cfg)
  local hook = cfg.gate and cfg.gate.pre_tool_hook or nil
  if type(hook) ~= "function" then
    return report
  end

  local ok_hook, verdict = pcall(hook, vim.deepcopy(report), vim.deepcopy(spec or {}))
  if not ok_hook then
    report.allowed = false
    report.decision = "deny"
    report.reason = "pre_hook_error"
    report.hint = "Security pre-tool hook failed: " .. tostring(verdict)
    return report
  end

  if type(verdict) == "table" then
    if verdict.allowed == false then
      report.allowed = false
      report.decision = tostring(verdict.decision or "deny")
      report.reason = tostring(verdict.reason or "pre_hook_denied")
      report.hint = tostring(verdict.hint or "Security pre-tool hook denied request.")
    elseif verdict.allowed == true then
      report.allowed = true
      report.decision = tostring(verdict.decision or report.decision)
      report.reason = tostring(verdict.reason or report.reason)
      if type(verdict.hint) == "string" and verdict.hint ~= "" then
        report.hint = verdict.hint
      end
    end
  end

  return report
end

local function audit_pre(report)
  local ok_log, agent_log = pcall(require, "jig.agent.log")
  if not ok_log or type(agent_log.record) ~= "function" then
    return
  end

  local payload = {
    event = "security_pre_tool_call",
    task_id = report.task_id,
    tool = report.origin,
    request = {
      actor = report.actor,
      capability = report.capability,
      action = report.action,
      target = report.target,
      normalized_target = report.normalized_target,
      project_root = report.project_root,
      approval_id = report.approval_id,
      outside_root = report.outside_root == true,
    },
    policy_decision = report.decision,
    result = {
      allowed = report.allowed,
      reason = report.reason,
      override_used = report.override_used == true,
    },
    error_path = report.allowed and "" or report.hint,
  }

  if vim.in_fast_event() then
    vim.schedule(function()
      pcall(agent_log.record, payload)
    end)
    return
  end

  agent_log.record(payload)
end

function M.pre_tool_call(spec)
  spec = spec or {}
  local cfg = security_config.get()

  local report = {
    timestamp = now_iso(),
    actor = tostring(spec.actor or "unknown"),
    origin = tostring(spec.origin or "unknown"),
    task_id = tostring(spec.task_id or ""),
    action = tostring(spec.action or "unknown"),
    capability = capability_for_action(spec.action),
    target = tostring(spec.target or spec.target_path or ""),
    normalized_target = "",
    project_root = "",
    approval_id = tostring(spec.approval_id or ""),
    approval_actor = tostring(spec.approval_actor or ""),
    approval_tool = tostring(spec.approval_tool or ""),
    outside_root = false,
    override_used = false,
    allowed = true,
    decision = "allow",
    reason = "allowed",
    hint = "",
  }

  if cfg.gate and cfg.gate.enabled == false then
    report.allowed = true
    report.decision = "allow"
    report.reason = "security_gate_disabled"
    audit_pre(report)
    return report
  end

  if
    report.approval_id ~= ""
    and report.approval_actor ~= ""
    and report.approval_actor ~= report.actor
  then
    report.allowed = false
    report.decision = "deny"
    report.reason = "consent_identity_confusion"
    report.hint = "Approval actor mismatch for requested action."
  end

  if
    report.allowed
    and report.approval_id ~= ""
    and report.approval_tool ~= ""
    and report.approval_tool ~= report.origin
  then
    report.allowed = false
    report.decision = "deny"
    report.reason = "consent_identity_confusion"
    report.hint = "Approval tool mismatch for requested action."
  end

  local target = nil
  if type(spec.target_path) == "string" and spec.target_path ~= "" then
    target = normalize_path(spec.target_path)
  end
  if target ~= nil then
    report.normalized_target = target
  end

  local path_sensitive_capability = report.capability == "fs.write"
    or report.capability == "fs.delete"
    or report.capability == "editor.patch_apply"

  if report.allowed and path_sensitive_capability and target ~= nil then
    local root = resolve_root(spec)
    report.project_root = root or ""

    if root ~= nil and not path_within_root(target, root) then
      report.outside_root = true
      local expected = tostring(cfg.gate and cfg.gate.outside_root_confirmation or "")
      local token = tostring(spec.confirmation_token or "")
      local override = report.actor == "user"
        and spec.allow_outside_root == true
        and expected ~= ""
        and token == expected

      if override then
        report.allowed = true
        report.decision = "allow"
        report.reason = "workspace_boundary_override"
        report.hint = "Outside-root override accepted with explicit confirmation."
        report.override_used = true
      else
        report.allowed = false
        report.decision = "deny"
        report.reason = "workspace_boundary_escape"
        report.hint = "Target is outside project root. Denied by workspace boundary policy."
      end
    end
  end

  if report.allowed and report.capability == "exec.run" then
    local injected, token = detect_argument_injection(spec.argv or {})
    if injected and report.actor ~= "user" then
      report.allowed = false
      report.decision = "deny"
      report.reason = "argument_injection_pattern"
      report.hint = "Suspicious argument-injection pattern detected: " .. token
    end
  end

  if report.allowed and HIGH_RISK_CAPABILITIES[report.capability] == true then
    local injected, pattern = detect_prompt_injection(spec.prompt_text, cfg)
    if injected and report.actor ~= "user" then
      report.allowed = false
      report.decision = "deny"
      report.reason = "prompt_injection_tool_misuse"
      report.hint = "Prompt/tool-output text matched injection pattern: " .. pattern
    end
  end

  if report.allowed and report.capability == "editor.patch_apply" then
    local finding = find_hidden_unicode(spec.patch_lines or {})
    if finding ~= nil then
      report.allowed = false
      report.decision = "deny"
      report.reason = "unicode_trojan_source"
      report.hint = string.format(
        "Hidden/bidi unicode detected in patch line %d (U+%04X).",
        finding.line,
        finding.codepoint
      )
    end
  end

  report = apply_pre_hook(report, spec, cfg)
  audit_pre(report)
  return report
end

function M.post_tool_call(pre_report, result, extra)
  extra = extra or {}
  local report = pre_report
    or {
      actor = tostring(extra.actor or "unknown"),
      origin = tostring(extra.origin or "unknown"),
      task_id = tostring(extra.task_id or ""),
      capability = capability_for_action(extra.action),
      action = tostring(extra.action or "unknown"),
      decision = "allow",
      allowed = true,
      reason = "allowed",
      approval_id = tostring(extra.approval_id or ""),
      target = tostring(extra.target or ""),
      normalized_target = tostring(extra.normalized_target or ""),
      project_root = tostring(extra.project_root or ""),
    }

  local ok_log, agent_log = pcall(require, "jig.agent.log")
  if not ok_log or type(agent_log.record) ~= "function" then
    return false
  end

  local cfg = security_config.get()
  local hook = cfg.gate and cfg.gate.post_tool_hook or nil
  local payload = {
    event = "security_post_tool_call",
    task_id = tostring(extra.task_id or report.task_id or ""),
    tool = tostring(extra.origin or report.origin or ""),
    request = {
      actor = tostring(extra.actor or report.actor or ""),
      subagent = tostring(extra.subagent or ""),
      capability = tostring(report.capability or ""),
      action = tostring(report.action or ""),
      target = tostring(report.target or ""),
      normalized_target = tostring(report.normalized_target or ""),
      project_root = tostring(report.project_root or ""),
      approval_id = tostring(extra.approval_id or report.approval_id or ""),
      server = tostring(extra.server or ""),
    },
    policy_decision = tostring(report.decision or ""),
    result = {
      ok = type(result) == "table" and result.ok == true or false,
      code = type(result) == "table" and result.code or nil,
      reason = type(result) == "table" and result.reason or "",
      allowed = report.allowed == true,
    },
    error_path = type(result) == "table" and tostring(result.hint or "") or "",
  }

  local function emit()
    if type(hook) == "function" then
      pcall(hook, vim.deepcopy(report), vim.deepcopy(result), vim.deepcopy(extra))
    end
    pcall(agent_log.record, payload)
  end

  if vim.in_fast_event() then
    vim.schedule(emit)
    return true
  end

  emit()

  return true
end

function M.contains_hidden_unicode(lines)
  return find_hidden_unicode(lines or {}) ~= nil
end

return M
