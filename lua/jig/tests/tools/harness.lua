local health = require("jig.tools.health")
local platform = require("jig.platform")
local registry = require("jig.tools.registry")
local system = require("jig.tools.system")

local M = {}

local function repo_root()
  if type(_G.__jig_repo_root) == "string" and _G.__jig_repo_root ~= "" then
    return _G.__jig_repo_root
  end
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h:h:h:h")
end

local function snapshot_path(opts)
  if opts and opts.snapshot_path and opts.snapshot_path ~= "" then
    return opts.snapshot_path
  end
  return vim.fn.stdpath("state") .. "/jig/tools-harness-snapshot.json"
end

local function write_snapshot(path, payload)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(payload) }, path)
end

local function command_exists(name)
  return vim.fn.exists(":" .. name) == 2
end

local function safe_env()
  local env = vim.fn.environ()
  env.NVIM_APPNAME = "jig-safe"
  return env
end

local function run_safe_assertions()
  local root = repo_root()
  local result = vim
    .system({
      "nvim",
      "--headless",
      "-u",
      root .. "/init.lua",
      "+lua assert(vim.fn.exists(':JigExec')==0)",
      "+lua assert(vim.fn.exists(':JigToolHealth')==0)",
      "+lua assert(vim.fn.exists(':JigTerm')==0)",
      "+lua assert(package.loaded['jig.tools']==nil)",
      "+qa",
    }, {
      env = safe_env(),
      text = true,
    })
    :wait(10000)

  assert(
    result and result.code == 0,
    (result and result.stderr or "") .. (result and result.stdout or "")
  )
  return { code = result.code }
end

local function shell_smoke_matrix()
  local detected = platform.detect()
  local specs = {
    bash = { argv = { "bash", "-lc", "printf shell-smoke" } },
    zsh = { argv = { "zsh", "-lc", "printf shell-smoke" } },
    fish = { argv = { "fish", "-c", "printf shell-smoke" } },
    pwsh = {
      argv = { "pwsh", "-NoProfile", "-NonInteractive", "-Command", "Write-Output shell-smoke" },
    },
    powershell = {
      argv = {
        "powershell",
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "Write-Output shell-smoke",
      },
    },
    cmd = { argv = { "cmd", "/d", "/s", "/c", "echo shell-smoke" } },
  }

  local checks = {}
  local succeeded = 0
  for kind, spec in pairs(specs) do
    local shell = detected.shells[kind]
    if shell and shell.available then
      local result = system.run_sync(spec.argv, { timeout_ms = 10000, cwd = vim.uv.cwd() })
      local token_ok = result.stdout:lower():find("shell%-smoke", 1, false) ~= nil
      local ok = result.ok and token_ok
      if ok then
        succeeded = succeeded + 1
      end
      checks[kind] = {
        ok = ok,
        code = result.code,
        reason = result.reason,
        stderr = result.stderr,
      }
    else
      checks[kind] = { ok = true, skipped = "shell unavailable" }
    end
  end

  local configured_kind = detected.shell.kind
  local configured_shell = detected.shells[configured_kind]
  if configured_shell and configured_shell.available then
    local configured_check = checks[configured_kind]
    assert(
      configured_check and configured_check.ok == true,
      string.format("configured shell smoke failed (%s)", configured_kind)
    )
  else
    assert(succeeded >= 1, "no available shell class passed smoke execution")
  end

  return checks
end

local function long_running_argv()
  local detected = platform.detect()
  if detected.shells.bash and detected.shells.bash.available then
    return { "bash", "-lc", "sleep 1" }, "bash"
  end
  if detected.shells.zsh and detected.shells.zsh.available then
    return { "zsh", "-lc", "sleep 1" }, "zsh"
  end
  if detected.shells.fish and detected.shells.fish.available then
    return { "fish", "-c", "sleep 1" }, "fish"
  end
  if detected.shells.pwsh and detected.shells.pwsh.available then
    return {
      "pwsh",
      "-NoProfile",
      "-NonInteractive",
      "-Command",
      "Start-Sleep -Seconds 1",
    },
      "pwsh"
  end
  if detected.shells.powershell and detected.shells.powershell.available then
    return {
      "powershell",
      "-NoProfile",
      "-NonInteractive",
      "-Command",
      "Start-Sleep -Seconds 1",
    },
      "powershell"
  end
  if detected.shells.cmd and detected.shells.cmd.available then
    return { "cmd", "/d", "/s", "/c", "ping 127.0.0.1 -n 2 > NUL" }, "cmd"
  end
  return nil, "none"
end

local function timeout_reason(reason)
  return reason == "timeout" or reason == "system_wait_nil" or reason == "system_wait_error"
end

local function run_case(case)
  local attempts = case.retries or 1
  local delay = case.retry_delay_ms or 0
  local last_details = {}

  for attempt = 1, attempts do
    local ok, passed, details = pcall(case.run)
    if ok and passed then
      return true,
        {
          attempts = attempt,
          labels = case.labels or {},
          details = details or {},
        }
    end

    last_details = details or { error = passed }
    if attempt < attempts and delay > 0 then
      vim.wait(delay)
    end
  end

  return false,
    {
      attempts = attempts,
      labels = case.labels or {},
      details = last_details,
    }
end

local function capture_guard_argv()
  local detected = platform.detect()
  if detected.shells.bash and detected.shells.bash.available then
    return { "bash", "-lc", "sleep 0.2; printf first" }, { "bash", "-lc", "printf second" }, "bash"
  end
  if detected.shells.zsh and detected.shells.zsh.available then
    return { "zsh", "-lc", "sleep 0.2; printf first" }, { "zsh", "-lc", "printf second" }, "zsh"
  end
  if detected.shells.fish and detected.shells.fish.available then
    return { "fish", "-c", "sleep 0.2; printf first" }, { "fish", "-c", "printf second" }, "fish"
  end
  if detected.shells.pwsh and detected.shells.pwsh.available then
    return {
      "pwsh",
      "-NoProfile",
      "-NonInteractive",
      "-Command",
      "Start-Sleep -Milliseconds 200; Write-Output first",
    },
      {
        "pwsh",
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "Write-Output second",
      },
      "pwsh"
  end
  if detected.shells.powershell and detected.shells.powershell.available then
    return {
      "powershell",
      "-NoProfile",
      "-NonInteractive",
      "-Command",
      "Start-Sleep -Milliseconds 200; Write-Output first",
    },
      {
        "powershell",
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "Write-Output second",
      },
      "powershell"
  end
  return nil, nil, "none"
end

local cases = {
  {
    id = "default-command-surface",
    run = function()
      assert(command_exists("JigExec"), "JigExec missing")
      assert(command_exists("JigToolHealth"), "JigToolHealth missing")
      assert(command_exists("JigTerm"), "JigTerm missing")
      return {
        JigExec = true,
        JigToolHealth = true,
        JigTerm = true,
      }
    end,
  },
  {
    id = "provider-health-tests",
    run = function()
      local lines, report = health.lines()
      assert(type(lines) == "table" and #lines > 0, "health lines empty")
      assert(type(report.providers) == "table" and #report.providers >= 3, "provider list missing")

      local missing_provider_has_hint = false
      for _, provider in ipairs(report.providers) do
        if provider.enabled == false and provider.hint ~= "" then
          missing_provider_has_hint = true
          break
        end
      end

      return {
        providers = #report.providers,
        missing_provider_has_hint = missing_provider_has_hint,
      }
    end,
  },
  {
    id = "command-execution-smoke",
    run = function()
      local git_available = registry.is_available("git")
      if not git_available then
        return {
          skipped = "git unavailable",
        }
      end

      local result = system.run_sync({ "git", "--version" }, { timeout_ms = 2000 })
      assert(result.ok == true, "git --version failed")
      assert(result.stdout:lower():find("git", 1, true) ~= nil, "git stdout missing token")

      vim.cmd("JigExec git --version")
      assert(type(vim.g.jig_exec_last) == "table", "JigExec state missing")
      assert(vim.g.jig_exec_last.result.ok == true, "JigExec result unexpected")

      return {
        code = result.code,
        duration_ms = result.duration_ms,
      }
    end,
  },
  {
    id = "shell-class-smokes",
    run = function()
      return shell_smoke_matrix()
    end,
  },
  {
    id = "capture-concurrency-guard",
    labels = { "timing-sensitive" },
    retries = 3,
    retry_delay_ms = 80,
    run = function()
      local first_argv, second_argv, shell = capture_guard_argv()
      if not first_argv then
        return {
          skipped = "no shell available for async capture guard",
        }
      end

      local done = {}
      system.run(first_argv, {
        timeout_ms = 3000,
        on_exit = function(result)
          done.first = result
        end,
      })
      system.run(second_argv, {
        timeout_ms = 3000,
        on_exit = function(result)
          done.second = result
        end,
      })

      local queued_state = system.queue_state()
      assert(queued_state.active_capture >= 1, "capture guard did not mark active capture")
      assert(queued_state.queued >= 1, "capture guard did not queue second capture job")

      local completed = vim.wait(5000, function()
        return done.first ~= nil and done.second ~= nil
      end, 20)
      assert(completed == true, "capture guard jobs did not complete in timeout")
      assert(done.first.ok == true, "first capture job failed")
      assert(done.second.ok == true, "second capture job failed")

      return {
        shell = shell,
        queued = queued_state.queued,
        active_capture = queued_state.active_capture,
      }
    end,
  },
  {
    id = "missing-binary-nonfatal",
    run = function()
      local result = system.run_sync({ "__jig_missing_tool__", "--version" }, { timeout_ms = 500 })
      assert(result.ok == false, "missing binary should fail")
      assert(
        result.reason == "spawn_error" or result.reason == "system_wait_error",
        "unexpected reason"
      )
      assert(result.hint:find("JigToolHealth", 1, true) ~= nil, "hint must reference JigToolHealth")

      return {
        reason = result.reason,
        hint = result.hint,
      }
    end,
  },
  {
    id = "timeout-or-nil-path",
    run = function()
      local argv, shell = long_running_argv()
      if not argv then
        return {
          skipped = "no shell available for timeout test",
        }
      end

      local result = system.run_sync(argv, { timeout_ms = 1 })
      assert(result.ok == false, "timeout test must not be ok")
      assert(
        timeout_reason(result.reason),
        "unexpected timeout reason: " .. tostring(result.reason)
      )
      assert(type(result.hint) == "string" and result.hint ~= "", "timeout hint missing")

      return {
        shell = shell,
        reason = result.reason,
        stderr = result.stderr,
      }
    end,
  },
  {
    id = "safe-profile-isolation",
    run = function()
      return run_safe_assertions()
    end,
  },
}

function M.run(opts)
  local report = {
    harness = "headless-child-tools",
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    cases = {},
  }

  local failed = {}
  for _, case in ipairs(cases) do
    local ok, case_result = run_case(case)
    report.cases[case.id] = {
      ok = ok,
      labels = case_result.labels,
      attempts = case_result.attempts,
      details = case_result.details,
    }
    if not ok then
      table.insert(failed, case.id)
    end
  end

  report.summary = {
    passed = #failed == 0,
    failed_cases = failed,
  }

  local path = snapshot_path(opts)
  write_snapshot(path, report)
  print("tools-harness snapshot written: " .. path)

  if #failed > 0 then
    error("tools harness failed: " .. table.concat(failed, ", "))
  end
end

return M
