local security_config = require("jig.security.config")

local M = {}

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
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

local function normalize_argv(argv)
  local out = {}
  for _, value in ipairs(argv or {}) do
    out[#out + 1] = tostring(value)
  end
  return out
end

local function contains_flag(argv, ...)
  local wanted = {}
  for _, item in ipairs({ ... }) do
    wanted[tostring(item)] = true
  end

  for _, token in ipairs(argv or {}) do
    if wanted[token] then
      return true
    end
  end

  return false
end

local function classify_git(argv)
  local cfg = security_config.get()
  local token2 = normalize_token(argv[2])
  local token3 = normalize_token(argv[3])

  if token2 == "reset" and contains_flag(argv, "--hard") then
    return true, "git-reset-hard", cfg.exec_safety.destructive_git.reset_hard == true
  end

  if token2 == "clean" then
    if contains_flag(argv, "-fd", "-df", "-fxd", "-xdf") then
      return true, "git-clean-force-dirs", cfg.exec_safety.destructive_git.clean_force_dirs == true
    end
    if contains_flag(argv, "-f", "--force") then
      return true, "git-clean-force", cfg.exec_safety.destructive_git.clean_force == true
    end
  end

  if token2 == "push" and contains_flag(argv, "--force", "-f") then
    return true, "git-push-force", cfg.exec_safety.destructive_git.push_force == true
  end

  if token2 == "branch" and contains_flag(argv, "-D") then
    return true,
      "git-branch-delete-force",
      cfg.exec_safety.destructive_git.branch_delete_force == true
  end

  if token2 == "checkout" and contains_flag(argv, "-f", "--force") then
    return true, "git-checkout-force", true
  end

  if token2 == "restore" and contains_flag(argv, "--source", "--staged") then
    return true, "git-restore-destructive", true
  end

  if token2 == "submodule" and token3 == "update" and contains_flag(argv, "--init") then
    return false, "git-submodule-update", false
  end

  return false, "git-safe", false
end

local function classify_shell(argv)
  local cfg = security_config.get()
  local shell_like = {
    sh = true,
    bash = true,
    zsh = true,
    fish = true,
    pwsh = true,
    powershell = true,
    cmd = true,
  }

  local command = normalize_token(argv[1])
  if not shell_like[command] then
    return false, "not-shell"
  end

  local script = table.concat(vim.list_slice(argv, 2), " "):lower()
  for _, pattern in ipairs(cfg.exec_safety.shell_patterns or {}) do
    if script:find(pattern) then
      return true, "shell-destructive-pattern"
    end
  end

  return false, "shell-safe"
end

local function classify_argv(argv)
  local cfg = security_config.get()
  local normalized = normalize_argv(argv)
  local command = normalize_token(normalized[1])

  if command == "" then
    return {
      destructive = false,
      reason = "empty",
      command = command,
    }
  end

  if cfg.exec_safety.destructive_commands[command] == true then
    return {
      destructive = true,
      reason = "direct-destructive-command",
      command = command,
    }
  end

  if command == "mv" and contains_flag(normalized, "-f", "--force", "-n") then
    return {
      destructive = true,
      reason = "mv-overwrite-risk",
      command = command,
    }
  end

  if command == "git" then
    local destructive, reason = classify_git(normalized)
    return {
      destructive = destructive,
      reason = reason,
      command = command,
    }
  end

  local shell_destructive, shell_reason = classify_shell(normalized)
  if shell_destructive then
    return {
      destructive = true,
      reason = shell_reason,
      command = command,
    }
  end

  return {
    destructive = false,
    reason = "not-destructive",
    command = command,
  }
end

local function audit(report)
  local ok_log, agent_log = pcall(require, "jig.agent.log")
  if not ok_log or type(agent_log.record) ~= "function" then
    return
  end

  agent_log.record({
    event = "security_exec_safety",
    task_id = report.task_id,
    tool = report.origin,
    request = {
      actor = report.actor,
      argv = report.argv,
      destructive = report.classification.destructive,
      override_requested = report.override_requested,
    },
    policy_decision = report.decision,
    result = {
      allowed = report.allowed,
      reason = report.reason,
      override_used = report.override_used,
    },
    error_path = report.hint,
  })
end

function M.evaluate(argv, ctx)
  ctx = ctx or {}
  local normalized = normalize_argv(argv)
  local classification = classify_argv(normalized)

  local report = {
    timestamp = now_iso(),
    actor = ctx.actor or "user",
    origin = ctx.origin or "unknown",
    task_id = ctx.task_id,
    argv = normalized,
    classification = classification,
    override_requested = ctx.override == true,
    override_used = false,
    decision = "allow",
    allowed = true,
    reason = "allowed",
    hint = "",
  }

  if not classification.destructive then
    return report
  end

  if report.actor ~= "user" then
    report.allowed = false
    report.decision = "deny"
    report.reason = "destructive-denied-non-user"
    report.hint = "Destructive execution denied for non-user actors."
    audit(report)
    return report
  end

  if report.override_requested then
    report.allowed = true
    report.decision = "allow"
    report.reason = "destructive-override"
    report.override_used = true
    report.hint = "Destructive override accepted (user)."
    audit(report)
    return report
  end

  report.allowed = false
  report.decision = "deny"
  report.reason = "destructive-requires-override"
  report.hint = "Destructive command blocked. Re-run with :JigExec! only if intentional."
  audit(report)
  return report
end

function M.classify(argv)
  return classify_argv(argv)
end

return M
