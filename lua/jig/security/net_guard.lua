local security_config = require("jig.security.config")
local startup_phase = require("jig.security.startup_phase")

local M = {}

local hooks_installed = false
local original_vim_system = nil
local original_fn_system = nil

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function parse_bool_env(name)
  local value = vim.env[name]
  if type(value) ~= "string" then
    return false
  end
  local lowered = value:lower()
  return lowered == "1" or lowered == "true" or lowered == "yes" or lowered == "on"
end

local function trace_path()
  if
    type(vim.env.JIG_STARTUP_NET_TRACE_PATH) == "string"
    and vim.env.JIG_STARTUP_NET_TRACE_PATH ~= ""
  then
    return vim.env.JIG_STARTUP_NET_TRACE_PATH
  end

  local cfg = security_config.get()
  return security_config.path(cfg.startup.trace_file)
end

local function append_trace(entry)
  local path = trace_path()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  pcall(vim.fn.writefile, { vim.json.encode(entry) }, path, "a")
end

local function normalize_token(value)
  local token = tostring(value or "")
  token = token:gsub("^%s+", ""):gsub("%s+$", "")
  token = token:gsub("^['\"]", ""):gsub("['\"]$", "")
  token = token:gsub("\\", "/")
  token = token:match("([^/]+)$") or token
  token = token:lower():gsub("%.exe$", "")
  token = token:gsub("_", "-")
  return token
end

local function split_cmd(cmd)
  local out = {}
  for token in tostring(cmd or ""):gmatch("%S+") do
    out[#out + 1] = token
  end
  return out
end

local function normalize_argv(cmd)
  if type(cmd) == "table" then
    local out = {}
    for _, value in ipairs(cmd) do
      out[#out + 1] = tostring(value)
    end
    return out
  end
  if type(cmd) == "string" then
    return split_cmd(cmd)
  end
  return {}
end

local function has_url(text)
  local lowered = tostring(text or ""):lower()
  return lowered:find("https://", 1, true) ~= nil
    or lowered:find("http://", 1, true) ~= nil
    or lowered:find("ssh://", 1, true) ~= nil
    or lowered:find("git@", 1, true) ~= nil
end

local function classify_shell_script(argv)
  if #argv < 2 then
    return false, ""
  end
  local script = table.concat(vim.list_slice(argv, 2), " ")
  if has_url(script) then
    return true, "shell-script-url"
  end
  local lowered = script:lower()
  if
    lowered:find("curl ", 1, true)
    or lowered:find("wget ", 1, true)
    or lowered:find("git clone", 1, true)
    or lowered:find("git fetch", 1, true)
    or lowered:find("npm install", 1, true)
  then
    return true, "shell-script-network"
  end
  return false, ""
end

local function classify_argv(argv)
  local cfg = security_config.get()

  if type(argv) ~= "table" or #argv == 0 then
    return {
      networkish = false,
      reason = "empty",
      command = "",
    }
  end

  local command = normalize_token(argv[1])
  local sub = normalize_token(argv[2])

  if has_url(table.concat(argv, " ")) then
    return {
      networkish = true,
      reason = "contains-url",
      command = command,
      subcommand = sub,
    }
  end

  for _, item in ipairs(cfg.startup.network_commands or {}) do
    if command == normalize_token(item) then
      return {
        networkish = true,
        reason = "network-command",
        command = command,
        subcommand = sub,
      }
    end
  end

  if command == "git" then
    local git_network = cfg.startup.git_network_subcommands or {}
    if git_network[sub] then
      return {
        networkish = true,
        reason = "git-network-subcommand",
        command = command,
        subcommand = sub,
      }
    end
  end

  local manager_map = cfg.startup.package_manager_commands or {}
  local manager = manager_map[command]
  if type(manager) == "table" and manager[sub] == true then
    return {
      networkish = true,
      reason = "package-manager-network-subcommand",
      command = command,
      subcommand = sub,
    }
  end

  local shell_like = {
    sh = true,
    bash = true,
    zsh = true,
    fish = true,
    pwsh = true,
    powershell = true,
    cmd = true,
  }
  if shell_like[command] then
    local shell_network, shell_reason = classify_shell_script(argv)
    if shell_network then
      return {
        networkish = true,
        reason = shell_reason,
        command = command,
        subcommand = sub,
      }
    end
  end

  return {
    networkish = false,
    reason = "local-command",
    command = command,
    subcommand = sub,
  }
end

local function allowlisted(argv, ctx)
  local cfg = security_config.get()
  local list = cfg.startup.startup_allowlist or {}
  local command = normalize_token(argv[1])
  local joined = table.concat(argv, " "):lower()

  for _, rule in ipairs(list) do
    if type(rule) == "string" then
      local normalized = rule:lower()
      if normalized == command then
        return true, "allowlist-command"
      end
      if normalized:sub(1, 5) == "argv:" then
        local prefix = normalized:sub(6)
        if joined:find(prefix, 1, true) == 1 then
          return true, "allowlist-argv-prefix"
        end
      elseif normalized:sub(1, 7) == "origin:" then
        local origin = normalized:sub(8)
        if origin == tostring(ctx.origin or "") then
          return true, "allowlist-origin"
        end
      end
    end
  end

  if ctx.allow_network == true then
    return true, "explicit-allow-network"
  end

  return false, ""
end

local function trace_enabled()
  local cfg = security_config.get()
  return parse_bool_env(cfg.startup.trace_env)
end

local function strict_enabled()
  local cfg = security_config.get()
  return parse_bool_env(cfg.startup.strict_env)
end

local function audit_event(report)
  local ok_log, agent_log = pcall(require, "jig.agent.log")
  if not ok_log or type(agent_log.record) ~= "function" then
    return
  end

  agent_log.record({
    event = "security_net_guard",
    task_id = report.task_id,
    tool = report.origin,
    request = {
      argv = report.argv,
      actor = report.actor,
      startup = report.startup,
      classification = report.classification.reason,
    },
    policy_decision = report.decision,
    result = {
      allowed = report.allowed,
      reason = report.reason,
    },
    error_path = report.hint,
  })
end

function M.evaluate_argv(argv, ctx)
  ctx = ctx or {}
  local cfg = security_config.get()

  local normalized = normalize_argv(argv)
  local classification = classify_argv(normalized)
  local startup = startup_phase.is_startup()
  local decision = "allow"
  local reason = "allowed"

  if startup and classification.networkish and cfg.startup.deny_network_by_default == true then
    local allowed, allow_reason = allowlisted(normalized, ctx)
    if allowed then
      decision = "allow"
      reason = allow_reason
    else
      decision = "deny"
      reason = "startup-network-denied"
    end
  end

  local report = {
    timestamp = now_iso(),
    actor = ctx.actor or "system",
    origin = ctx.origin or "unknown",
    task_id = ctx.task_id,
    argv = normalized,
    classification = classification,
    startup = startup,
    decision = decision,
    allowed = decision ~= "deny",
    reason = reason,
    strict = strict_enabled(),
    trace = trace_enabled(),
    hint = decision == "deny"
        and "Network-ish startup execution denied by default. Configure startup_allowlist only for trusted commands."
      or "",
  }

  if report.trace then
    append_trace(report)
  end

  if classification.networkish or report.decision == "deny" then
    audit_event(report)
  end

  return report
end

function M.evaluate_action_class(action_class, ctx)
  ctx = ctx or {}
  local normalized = tostring(action_class or "unknown")
  local networkish = normalized == "net"

  local report = {
    timestamp = now_iso(),
    actor = ctx.actor or "system",
    origin = ctx.origin or "unknown",
    task_id = ctx.task_id,
    action_class = normalized,
    startup = startup_phase.is_startup(),
    decision = "allow",
    allowed = true,
    reason = "allowed",
    trace = trace_enabled(),
    strict = strict_enabled(),
    classification = {
      networkish = networkish,
      reason = networkish and "action-class-net" or "action-class-local",
      command = "",
    },
    argv = {},
  }

  local cfg = security_config.get()
  if report.startup and networkish and cfg.startup.deny_network_by_default == true then
    if ctx.allow_network == true then
      report.decision = "allow"
      report.reason = "explicit-allow-network"
    else
      report.decision = "deny"
      report.allowed = false
      report.reason = "startup-network-capability-denied"
      report.hint = "Net capability denied during startup by default policy."
    end
  end

  if report.trace then
    append_trace(report)
  end
  if networkish or report.decision == "deny" then
    audit_event(report)
  end

  return report
end

local function blocked_process_result(report)
  return {
    code = -1,
    signal = nil,
    stdout = "",
    stderr = "blocked by jig startup network guard: " .. tostring(report.reason),
  }
end

local function blocked_process(report, callback)
  local result = blocked_process_result(report)
  if type(callback) == "function" then
    vim.schedule(function()
      callback(result)
    end)
  end

  return {
    wait = function(_, _)
      return result
    end,
    kill = function()
      return true
    end,
    write = function()
      return true
    end,
  }
end

function M.install_startup_hooks()
  if hooks_installed then
    return
  end

  if not trace_enabled() then
    return
  end

  original_vim_system = vim.system
  original_fn_system = vim.fn.system

  vim.system = function(cmd, opts, on_exit)
    local report = M.evaluate_argv(cmd, {
      actor = "system",
      origin = "vim.system-hook",
    })

    if report.decision == "deny" and report.strict then
      return blocked_process(report, on_exit)
    end

    return original_vim_system(cmd, opts, on_exit)
  end

  vim.fn.system = function(cmd, input)
    local report = M.evaluate_argv(cmd, {
      actor = "system",
      origin = "vim.fn.system-hook",
    })

    if report.decision == "deny" and report.strict then
      return "JIG_BLOCKED_STARTUP_NETWORK"
    end

    return original_fn_system(cmd, input)
  end

  hooks_installed = true
end

function M.uninstall_startup_hooks()
  if not hooks_installed then
    return
  end

  if original_vim_system ~= nil then
    vim.system = original_vim_system
  end
  if original_fn_system ~= nil then
    vim.fn.system = original_fn_system
  end

  hooks_installed = false
end

function M.trace_path()
  return trace_path()
end

function M.trace_entries(limit)
  local path = trace_path()
  if vim.fn.filereadable(path) ~= 1 then
    return {}
  end

  local lines = vim.fn.readfile(path)
  local from = math.max(1, #lines - (limit or 200) + 1)
  local out = {}
  for index = from, #lines do
    local line = lines[index]
    local ok, decoded = pcall(vim.json.decode, line)
    if ok and type(decoded) == "table" then
      out[#out + 1] = decoded
    end
  end
  return out
end

function M.clear_trace()
  local path = trace_path()
  if vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path)
  end
end

function M.simulate_startup_network_attempt()
  local cfg = security_config.get()
  if not parse_bool_env(cfg.startup.fixture_env) then
    return nil
  end

  local proc = vim.system({
    "git",
    "ls-remote",
    "https://example.com/jig-security-fixture.git",
  }, {
    text = true,
  })

  local ok_wait, result = pcall(proc.wait, proc, 200)
  if not ok_wait then
    return {
      ok = false,
      reason = "wait_error",
      detail = tostring(result),
    }
  end

  return {
    ok = result and result.code == 0,
    code = result and result.code or -1,
    stderr = result and result.stderr or "",
  }
end

return M
