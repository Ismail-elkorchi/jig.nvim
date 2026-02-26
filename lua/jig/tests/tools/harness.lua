local health = require("jig.tools.health")
local platform = require("jig.platform")
local registry = require("jig.tools.registry")
local system = require("jig.tools.system")
local toolchain = require("jig.tools.toolchain")

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
      "+lua assert(vim.fn.exists(':JigToolchainInstall')==0)",
      "+lua assert(vim.fn.exists(':JigToolchainUpdate')==0)",
      "+lua assert(vim.fn.exists(':JigToolchainRestore')==0)",
      "+lua assert(vim.fn.exists(':JigToolchainRollback')==0)",
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

local function read_json(path)
  local lines = vim.fn.readfile(path)
  return vim.json.decode(table.concat(lines, "\n"))
end

local function write_json(path, payload)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(payload) }, path)
end

local function fake_tool_name(base)
  if platform.os.is_windows() then
    return base .. ".cmd"
  end
  return base
end

local function write_fake_tool(path, version)
  local lines
  if platform.os.is_windows() then
    lines = {
      "@echo off",
      "echo fakefmt " .. tostring(version),
    }
  else
    lines = {
      "#!/usr/bin/env sh",
      "echo fakefmt " .. tostring(version),
    }
  end

  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(lines, path)
  if not platform.os.is_windows() then
    vim.uv.fs_chmod(path, 493) -- 0755
  end
end

local function make_toolchain_fixture()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")

  local source = root .. "/source/" .. fake_tool_name("fakefmt")
  local manifest = root .. "/manifest.json"
  local lockfile = root .. "/lock.json"
  local rollback = root .. "/rollback.json"
  local install_root = root .. "/install/bin"

  write_fake_tool(source, "1.0.0")

  local manifest_doc = {
    schema = "jig-toolchain-manifest-v1",
    install_root = install_root,
    tools = {
      {
        name = "fakefmt",
        mode = "managed",
        executable = fake_tool_name("fakefmt"),
        source = "fixture-local",
        source_path = source,
        version = "1.0.0",
        platform = "any",
        probe_args = { "--version" },
      },
    },
  }
  write_json(manifest, manifest_doc)

  local function cleanup()
    vim.fn.delete(root, "rf")
  end

  return {
    root = root,
    source = source,
    manifest = manifest,
    lockfile = lockfile,
    rollback = rollback,
    install_root = install_root,
    executable = install_root .. "/" .. fake_tool_name("fakefmt"),
    cleanup = cleanup,
  }
end

local function toolchain_opts(paths)
  return {
    manifest_path = paths.manifest,
    lockfile_path = paths.lockfile,
    rollback_path = paths.rollback,
    install_root = paths.install_root,
    timeout_ms = 2000,
    actor = "user",
    origin = "tests.toolchain",
  }
end

local cases = {
  {
    id = "default-command-surface",
    run = function()
      assert(command_exists("JigExec"), "JigExec missing")
      assert(command_exists("JigToolHealth"), "JigToolHealth missing")
      assert(command_exists("JigTerm"), "JigTerm missing")
      assert(command_exists("JigToolchainInstall"), "JigToolchainInstall missing")
      assert(command_exists("JigToolchainUpdate"), "JigToolchainUpdate missing")
      assert(command_exists("JigToolchainRestore"), "JigToolchainRestore missing")
      assert(command_exists("JigToolchainRollback"), "JigToolchainRollback missing")
      return {
        JigExec = true,
        JigToolHealth = true,
        JigTerm = true,
        JigToolchainInstall = true,
        JigToolchainUpdate = true,
        JigToolchainRestore = true,
        JigToolchainRollback = true,
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
    id = "toolchain-install-restore-version-equality",
    run = function()
      local fixture = make_toolchain_fixture()
      local opts = toolchain_opts(fixture)

      local installed = toolchain.install(opts)
      assert(
        installed.ok == true,
        "toolchain install failed: " .. table.concat(installed.errors or {}, "; ")
      )

      local lock1 = read_json(fixture.lockfile)
      local before = lock1.tools[1]
      assert(before.version == "1.0.0", "unexpected initial locked version")

      write_fake_tool(fixture.executable, "9.9.9")
      local drift = toolchain.health_report(opts)
      assert(drift.lockfile_present == true, "toolchain lockfile should be present")
      assert(tonumber(drift.drift_count) == 1, "drift_count should be 1 after mutation")

      local restored = toolchain.restore(opts)
      assert(
        restored.ok == true,
        "toolchain restore failed: " .. table.concat(restored.errors or {}, "; ")
      )

      local probe = system.run_sync({ fixture.executable, "--version" }, { timeout_ms = 2000 })
      assert(probe.ok == true, "probe after restore failed")
      assert(probe.stdout:find("1.0.0", 1, true) ~= nil, "restore did not recover expected version")

      fixture.cleanup()
      return {
        locked_version = before.version,
        drift_count = drift.drift_count,
        restored_version = "1.0.0",
      }
    end,
  },
  {
    id = "toolchain-rollback-restores-previous-lock",
    run = function()
      local fixture = make_toolchain_fixture()
      local opts = toolchain_opts(fixture)

      local first = toolchain.install(opts)
      assert(first.ok == true, "initial install failed")

      local manifest = read_json(fixture.manifest)
      manifest.tools[1].version = "2.0.0"
      write_json(fixture.manifest, manifest)
      write_fake_tool(fixture.source, "2.0.0")

      local updated = toolchain.update(opts)
      assert(updated.ok == true, "update failed: " .. table.concat(updated.errors or {}, "; "))

      local lock_updated = read_json(fixture.lockfile)
      assert(lock_updated.tools[1].version == "2.0.0", "update lock version mismatch")

      local rolled = toolchain.rollback(opts)
      assert(rolled.ok == true, "rollback failed: " .. table.concat(rolled.errors or {}, "; "))

      local lock_rolled = read_json(fixture.lockfile)
      assert(
        lock_rolled.tools[1].version == "1.0.0",
        "rollback lockfile did not restore previous version"
      )

      local probe = system.run_sync({ fixture.executable, "--version" }, { timeout_ms = 2000 })
      assert(probe.ok == true, "probe after rollback failed")
      assert(
        probe.stdout:find("1.0.0", 1, true) ~= nil,
        "rollback did not restore tool binary version"
      )

      fixture.cleanup()
      return {
        before = "1.0.0",
        updated = "2.0.0",
        rolled_back = "1.0.0",
      }
    end,
  },
  {
    id = "toolchain-drift-visible-in-health",
    run = function()
      local fixture = make_toolchain_fixture()
      local opts = toolchain_opts(fixture)

      local installed = toolchain.install(opts)
      assert(installed.ok == true, "toolchain install failed")

      write_fake_tool(fixture.executable, "7.7.7")
      local previous = vim.g.jig_toolchain
      vim.g.jig_toolchain = {
        manifest_path = fixture.manifest,
        lockfile_path = fixture.lockfile,
        rollback_path = fixture.rollback,
        install_root = fixture.install_root,
        timeout_ms = 2000,
      }

      vim.cmd("JigToolHealth")
      local state = vim.g.jig_tool_health_last
      assert(type(state) == "table" and type(state.lines) == "table", "JigToolHealth state missing")
      local joined = table.concat(state.lines, "\n")
      local report = state.report
      assert(
        report.toolchain and report.toolchain.drift_count == 1,
        "JigToolHealth drift_count mismatch"
      )
      assert(
        joined:lower():find("drift", 1, true) ~= nil,
        "health output should include drift wording"
      )
      vim.g.jig_toolchain = previous

      fixture.cleanup()
      return {
        drift_count = report.toolchain.drift_count,
      }
    end,
  },
  {
    id = "toolchain-drift-warning-via-jighealth",
    run = function()
      local fixture = make_toolchain_fixture()
      local opts = toolchain_opts(fixture)

      local installed = toolchain.install(opts)
      assert(installed.ok == true, "toolchain install failed")
      write_fake_tool(fixture.executable, "5.5.5")

      local previous_toolchain = vim.g.jig_toolchain
      vim.g.jig_toolchain = {
        manifest_path = fixture.manifest,
        lockfile_path = fixture.lockfile,
        rollback_path = fixture.rollback,
        install_root = fixture.install_root,
        timeout_ms = 2000,
      }

      local captured = {}
      local original_health = {
        start = vim.health.start,
        ok = vim.health.ok,
        warn = vim.health.warn,
        info = vim.health.info,
        error = vim.health.error,
      }

      vim.health.start = function(msg)
        captured[#captured + 1] = "start:" .. tostring(msg)
      end
      vim.health.ok = function(msg)
        captured[#captured + 1] = "ok:" .. tostring(msg)
      end
      vim.health.warn = function(msg)
        captured[#captured + 1] = "warn:" .. tostring(msg)
      end
      vim.health.info = function(msg)
        captured[#captured + 1] = "info:" .. tostring(msg)
      end
      vim.health.error = function(msg)
        captured[#captured + 1] = "error:" .. tostring(msg)
      end

      local core_health = require("jig.core.health")
      core_health.check()

      vim.health.start = original_health.start
      vim.health.ok = original_health.ok
      vim.health.warn = original_health.warn
      vim.health.info = original_health.info
      vim.health.error = original_health.error
      vim.g.jig_toolchain = previous_toolchain

      fixture.cleanup()

      local joined = table.concat(captured, "\n"):lower()
      assert(
        joined:find("toolchain drift detected", 1, true) ~= nil,
        "JigHealth check did not surface toolchain drift warning"
      )

      return {
        warning = "toolchain drift detected",
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
