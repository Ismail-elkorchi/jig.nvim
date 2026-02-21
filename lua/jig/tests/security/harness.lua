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
  return vim.fn.stdpath("state") .. "/jig/security-harness-snapshot.json"
end

local function write_snapshot(path, payload)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(payload) }, path)
end

local function command_exists(name)
  return vim.fn.exists(":" .. name) == 2
end

local function base_env(appname)
  local env = vim.fn.environ()
  env.NVIM_APPNAME = appname
  return env
end

local function read_jsonl(path)
  if vim.fn.filereadable(path) ~= 1 then
    return {}
  end

  local rows = {}
  for _, line in ipairs(vim.fn.readfile(path)) do
    local ok, decoded = pcall(vim.json.decode, line)
    if ok and type(decoded) == "table" then
      rows[#rows + 1] = decoded
    end
  end
  return rows
end

local function run_nested(env)
  local root = repo_root()
  local init_cmd = string.format(
    "lua package.path='%s/lua/?.lua;%s/lua/?/init.lua;'..package.path; vim.opt.rtp:prepend('%s'); require('jig')",
    root,
    root,
    root
  )
  local result = vim
    .system({ "nvim", "--headless", "-u", "NONE", "+" .. init_cmd, "+qa" }, {
      env = env,
      text = true,
    })
    :wait(15000)

  assert(
    result and result.code == 0,
    (result and result.stderr or "") .. (result and result.stdout or "")
  )
  return result
end

local function run_safe_assertions()
  local root = repo_root()
  local init_cmd = string.format(
    "lua package.path='%s/lua/?.lua;%s/lua/?/init.lua;'..package.path; vim.opt.rtp:prepend('%s'); require('jig')",
    root,
    root,
    root
  )
  local result = vim
    .system({
      "nvim",
      "--headless",
      "-u",
      "NONE",
      "+" .. init_cmd,
      "+lua assert(vim.fn.exists(':JigMcpTrust')==0)",
      "+lua assert(vim.fn.exists(':JigExec')==0)",
      "+lua assert(vim.fn.exists(':JigTerm')==0)",
      "+lua assert(package.loaded['jig.security']==nil)",
      "+qa",
    }, {
      env = base_env("jig-safe"),
      text = true,
    })
    :wait(15000)

  assert(
    result and result.code == 0,
    (result and result.stderr or "") .. (result and result.stdout or "")
  )
  return {
    code = result.code,
  }
end

local function fixture_paths()
  local root = repo_root()
  return {
    mcp_server = root .. "/tests/fixtures/mcp/fake_mcp_server.sh",
  }
end

local function setup_mcp_fixture_root()
  local path = fixture_paths().mcp_server
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")

  local payload = {
    mcpServers = {
      secure_server = {
        command = path,
        args = { "ok" },
        timeout_ms = 1200,
        tools = {
          echo = {
            action_class = "read",
            target = "secure_server",
          },
        },
      },
    },
  }

  vim.fn.writefile({ vim.json.encode(payload) }, root .. "/.mcp.json")
  return root
end

local cases = {
  {
    id = "default-command-surface",
    run = function()
      assert(command_exists("JigExec"), "JigExec should exist in default profile")
      assert(command_exists("JigTerm"), "JigTerm should exist in default profile")
      assert(
        command_exists("JigMcpTrust") == false,
        "JigMcpTrust should be absent unless agent enabled"
      )
      return {
        JigExec = true,
        JigTerm = true,
        JigMcpTrust = false,
      }
    end,
  },
  {
    id = "startup-network-trace-clean",
    run = function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")
      local trace_path = tmp .. "/startup-clean.jsonl"

      local env = base_env("jig-net-clean")
      env.XDG_STATE_HOME = tmp .. "/state"
      env.XDG_DATA_HOME = tmp .. "/data"
      env.XDG_CACHE_HOME = tmp .. "/cache"
      env.JIG_TRACE_STARTUP_NET = "1"
      env.JIG_STRICT_STARTUP_NET = "1"
      env.JIG_STARTUP_NET_TRACE_PATH = trace_path
      env.JIG_TEST_STARTUP_NET_ATTEMPT = nil

      run_nested(env)

      local entries = read_jsonl(trace_path)
      local denied = 0
      local networkish = 0
      for _, row in ipairs(entries) do
        if row.decision == "deny" then
          denied = denied + 1
        end
        if row.classification and row.classification.networkish == true then
          networkish = networkish + 1
        end
      end

      assert(denied == 0, "clean startup should not deny network attempts")
      assert(networkish == 0, "clean startup should not attempt network-ish commands")

      return {
        entries = #entries,
        denied = denied,
        networkish = networkish,
      }
    end,
  },
  {
    id = "startup-network-trace-fixture",
    run = function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")
      local trace_path = tmp .. "/startup-fixture.jsonl"

      local env = base_env("jig-net-fixture")
      env.XDG_STATE_HOME = tmp .. "/state"
      env.XDG_DATA_HOME = tmp .. "/data"
      env.XDG_CACHE_HOME = tmp .. "/cache"
      env.JIG_TRACE_STARTUP_NET = "1"
      env.JIG_STRICT_STARTUP_NET = "1"
      env.JIG_STARTUP_NET_TRACE_PATH = trace_path
      env.JIG_TEST_STARTUP_NET_ATTEMPT = "1"

      run_nested(env)

      local entries = read_jsonl(trace_path)
      local blocked = 0
      for _, row in ipairs(entries) do
        if row.decision == "deny" and row.reason == "startup-network-denied" then
          blocked = blocked + 1
        end
      end

      assert(blocked >= 1, "fixture startup network attempt should be blocked and traced")

      return {
        entries = #entries,
        blocked = blocked,
      }
    end,
  },
  {
    id = "mcp-trust-enforcement",
    run = function()
      vim.g.jig_agent = { enabled = true }
      local agent = require("jig.agent")
      local setup = agent.setup()
      assert(setup.enabled == true, "agent setup must be enabled")

      local root_policy = require("jig.nav.root")
      local mcp = require("jig.agent.mcp.client")
      local trust = require("jig.security.mcp_trust")

      trust.reset_for_test()
      mcp.reset_for_test()

      local fixture_root = setup_mcp_fixture_root()
      local ok_root, err_root = root_policy.set(fixture_root)
      assert(ok_root == true, tostring(err_root))

      local denied_start = mcp.start("secure_server", { actor = "user" })
      assert(
        denied_start.ok == false and denied_start.reason == "blocked_by_trust",
        "untrusted server must be blocked"
      )

      local server, _ = mcp.discovery().servers["secure_server"], mcp.discovery()
      assert(server ~= nil, "fixture server missing")

      local ok_set = trust.set_state(server, "allow")
      assert(ok_set == true, "trust allow update failed")

      local started = mcp.start("secure_server", { actor = "user" })
      assert(started.ok == true, "trusted server should start")

      local blocked_tool = mcp.call("secure_server", "danger", {}, { actor = "user" })
      assert(
        blocked_tool.ok == false and blocked_tool.reason == "blocked_by_trust",
        "undeclared capability tool call should be blocked"
      )

      local allowed_tool = mcp.call("secure_server", "echo", { message = "ok" }, { actor = "user" })
      assert(allowed_tool.ok == true, "declared read capability should pass")

      root_policy.reset()

      return {
        denied_reason = denied_start.reason,
        blocked_tool_reason = blocked_tool.reason,
      }
    end,
  },
  {
    id = "exec-safety-override-logging",
    run = function()
      local temp = vim.fn.tempname()
      vim.fn.writefile({ "safety" }, temp)
      assert(vim.fn.filereadable(temp) == 1, "temp file setup failed")

      vim.cmd("JigExec rm -f " .. vim.fn.fnameescape(temp))
      local blocked = vim.g.jig_exec_last and vim.g.jig_exec_last.result
      assert(type(blocked) == "table", "JigExec blocked result missing")
      assert(
        blocked.reason == "destructive-requires-override",
        "destructive command must require override"
      )
      assert(vim.fn.filereadable(temp) == 1, "file should remain after blocked destructive command")

      vim.cmd("JigExec! rm -f " .. vim.fn.fnameescape(temp))
      local allowed = vim.g.jig_exec_last and vim.g.jig_exec_last.result
      assert(type(allowed) == "table" and allowed.ok == true, "override destructive command failed")
      assert(vim.fn.filereadable(temp) == 0, "file should be removed after override")

      local lines = vim.g.jig_exec_last and vim.g.jig_exec_last.lines or {}
      local has_warning = false
      for _, line in ipairs(lines) do
        if tostring(line):find("override", 1, true) then
          has_warning = true
          break
        end
      end
      assert(has_warning, "override warning must be visible in output")

      local log = require("jig.agent.log")
      local events = log.tail(200)
      local override_events = 0
      for _, event in ipairs(events) do
        if
          event.event == "security_exec_safety"
          and type(event.result) == "table"
          and event.result.override_used == true
        then
          override_events = override_events + 1
        end
      end
      assert(override_events >= 1, "override event must be logged")

      return {
        override_events = override_events,
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
    harness = "headless-child-security",
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    cases = {},
  }

  local failed = {}
  for _, case in ipairs(cases) do
    local ok, details = pcall(case.run)
    report.cases[case.id] = {
      ok = ok,
      labels = case.labels or {},
      details = ok and details or { error = details },
    }

    if not ok then
      failed[#failed + 1] = case.id
    end
  end

  report.summary = {
    passed = #failed == 0,
    failed_cases = failed,
  }

  local path = snapshot_path(opts)
  write_snapshot(path, report)
  print("security-harness snapshot written: " .. path)

  if #failed > 0 then
    error("security harness failed: " .. table.concat(failed, ", "))
  end
end

return M
