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

local function fixture_path(rel)
  return repo_root() .. "/tests/fixtures/" .. rel
end

local function read_json(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  if not ok or type(decoded) ~= "table" then
    return nil
  end
  return decoded
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
  local root_lua = string.format("%q", root)
  local init_cmd = string.format(
    "lua local root=%s; "
      .. "package.path=root..'/lua/?.lua;'..root..'/lua/?/init.lua;'..package.path; "
      .. "vim.opt.rtp:prepend(root); require('jig')",
    root_lua
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
  local root_lua = string.format("%q", root)
  local init_cmd = string.format(
    "lua local root=%s; "
      .. "package.path=root..'/lua/?.lua;'..root..'/lua/?/init.lua;'..package.path; "
      .. "vim.opt.rtp:prepend(root); require('jig')",
    root_lua
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
  return {
    mcp_server = fixture_path("mcp/fake_mcp_server.sh"),
    argv = fixture_path("security/argv_injection_samples.json"),
    prompt = fixture_path("security/prompt_injection_sample.txt"),
    unicode = fixture_path("security/unicode_patch_fixture.json"),
    workspace_root = fixture_path("security/workspace/root"),
  }
end

local function destructive_exec_commands(file_path)
  local is_windows = require("jig.platform.os").is_windows()
  if is_windows then
    local quoted = string.format("\"%s\"", file_path:gsub("\"", "\\\""))
    local argv = "cmd /d /s /c del /f /q " .. vim.fn.fnameescape(quoted)
    return argv, argv
  end

  local argv = "rm -f " .. vim.fn.fnameescape(file_path)
  return argv, argv
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

local function last_log_event(event_name)
  local log = require("jig.agent.log")
  local rows = log.tail(200)
  for index = #rows, 1, -1 do
    local row = rows[index]
    if row.event == event_name then
      return row
    end
  end
  return nil
end

local function workspace_escape_symlink()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  local root = tmp .. "/workspace"
  local outside_dir = tmp .. "/outside"
  vim.fn.mkdir(root, "p")
  vim.fn.mkdir(outside_dir, "p")
  vim.fn.mkdir(root .. "/.git", "p")
  vim.fn.writefile({ "ref: refs/heads/main" }, root .. "/.git/HEAD")

  local outside_file = outside_dir .. "/secrets.txt"
  vim.fn.writefile({ "secret" }, outside_file)
  local link_path = root .. "/escape_link.txt"
  vim.fn.delete(link_path)

  local ok_symlink, symlink_err = pcall(vim.uv.fs_symlink, outside_file, link_path, {})
  return {
    ok = ok_symlink == true,
    error = symlink_err,
    root = root,
    outside = outside_file,
    link = link_path,
  }
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

      local server = mcp.discovery().servers["secure_server"]
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

      local deny_cmd, allow_cmd = destructive_exec_commands(temp)

      vim.cmd("JigExec " .. deny_cmd)
      local blocked = vim.g.jig_exec_last and vim.g.jig_exec_last.result
      assert(type(blocked) == "table", "JigExec blocked result missing")
      assert(
        blocked.reason == "destructive-requires-override",
        "destructive command must require override"
      )
      assert(vim.fn.filereadable(temp) == 1, "file should remain after blocked destructive command")

      vim.cmd("JigExec! " .. allow_cmd)
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
    id = "workspace-boundary-path-traversal",
    run = function()
      local gate = require("jig.security.gate")
      local root = fixture_paths().workspace_root
      local outside = vim.fn.tempname()
      vim.fn.writefile({ "outside" }, outside)

      local report = gate.pre_tool_call({
        actor = "agent",
        origin = "security.harness",
        action = "editor.patch_apply",
        target_path = outside,
        project_root = root,
        patch_lines = { "payload" },
      })

      assert(report.allowed == false, "workspace escape should be denied")
      assert(report.reason == "workspace_boundary_escape", "unexpected boundary deny reason")

      return {
        reason = report.reason,
        root = root,
      }
    end,
  },
  {
    id = "workspace-boundary-symlink-escape",
    run = function()
      local gate = require("jig.security.gate")
      local symlink_case = workspace_escape_symlink()

      if symlink_case.ok ~= true then
        return {
          skipped = true,
          reason = "symlink-not-supported",
          detail = tostring(symlink_case.error),
        }
      end

      local report = gate.pre_tool_call({
        actor = "agent",
        origin = "security.harness",
        action = "editor.patch_apply",
        target_path = symlink_case.link,
        project_root = symlink_case.root,
        patch_lines = { "payload" },
      })

      assert(report.allowed == false, "symlink escape should be denied")
      assert(report.reason == "workspace_boundary_escape", "unexpected symlink deny reason")

      return {
        reason = report.reason,
      }
    end,
  },
  {
    id = "argv-injection-blocked",
    run = function()
      local gate = require("jig.security.gate")
      local samples = read_json(fixture_paths().argv)
      assert(type(samples) == "table", "argv fixture missing")

      local report_shell = gate.pre_tool_call({
        actor = "agent",
        origin = "security.harness",
        action = "exec.run",
        argv = samples.shell_like,
      })
      assert(report_shell.allowed == false, "shell argv injection must be denied")
      assert(
        report_shell.reason == "argument_injection_pattern",
        "unexpected shell injection reason"
      )

      local report_tokens = gate.pre_tool_call({
        actor = "agent",
        origin = "security.harness",
        action = "exec.run",
        argv = samples.token_injection,
      })
      assert(report_tokens.allowed == false, "token argv injection must be denied")
      assert(
        report_tokens.reason == "argument_injection_pattern",
        "unexpected token injection reason"
      )

      return {
        shell_reason = report_shell.reason,
        token_reason = report_tokens.reason,
      }
    end,
  },
  {
    id = "consent-identity-confusion-blocked",
    run = function()
      local gate = require("jig.security.gate")
      local report = gate.pre_tool_call({
        actor = "agent",
        origin = "mcp.call",
        action = "write",
        target = "secure_server:write_tool",
        approval_id = "a-identity",
        approval_actor = "user",
        approval_tool = "mcp.tools",
      })

      assert(report.allowed == false, "approval identity confusion should be denied")
      assert(report.reason == "consent_identity_confusion", "unexpected consent mismatch reason")
      return {
        reason = report.reason,
      }
    end,
  },
  {
    id = "prompt-injection-tool-misuse-blocked",
    run = function()
      local gate = require("jig.security.gate")
      local prompt = table.concat(vim.fn.readfile(fixture_paths().prompt), "\n")

      local report = gate.pre_tool_call({
        actor = "agent",
        origin = "mcp.call",
        action = "net.http",
        target = "secure_server:dangerous_tool",
        prompt_text = prompt,
      })

      assert(report.allowed == false, "prompt-injection tool misuse should be denied")
      assert(report.reason == "prompt_injection_tool_misuse", "unexpected prompt injection reason")
      return {
        reason = report.reason,
      }
    end,
  },
  {
    id = "unicode-bidi-patch-blocked",
    run = function()
      local gate = require("jig.security.gate")
      local fixture = read_json(fixture_paths().unicode)
      assert(type(fixture) == "table", "unicode fixture missing")
      local codepoint = tonumber(fixture.codepoint, 16)
      assert(type(codepoint) == "number", "unicode fixture codepoint missing")

      local payload = "prefix-" .. vim.fn.nr2char(codepoint) .. "-payload"
      local report = gate.pre_tool_call({
        actor = "agent",
        origin = "agent.patch.apply",
        action = "editor.patch_apply",
        target_path = vim.fn.tempname(),
        project_root = vim.fn.fnamemodify(vim.fn.tempname(), ":h"),
        patch_lines = { "safe", payload },
      })

      assert(report.allowed == false, "unicode bidi patch must be denied")
      assert(report.reason == "unicode_trojan_source", "unexpected unicode deny reason")
      return {
        reason = report.reason,
      }
    end,
  },
  {
    id = "patch-pipeline-workspace-boundary-denied",
    run = function()
      vim.g.jig_agent = { enabled = true }
      local agent = require("jig.agent")
      local setup = agent.setup()
      assert(setup.enabled == true, "agent should enable")

      local patch = require("jig.agent.patch")
      patch.reset_for_test()

      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")
      local root = tmp .. "/workspace"
      local outside = tmp .. "/outside.txt"
      vim.fn.mkdir(root .. "/.git", "p")
      vim.fn.writefile({ "ref: refs/heads/main" }, root .. "/.git/HEAD")
      vim.fn.writefile({ "outside" }, outside)

      local ok_create, err_or_session = patch.create({
        actor = "agent",
        origin = "security.harness.patch",
        project_root = root,
        files = {
          {
            path = outside,
            hunks = {
              {
                start_line = 1,
                end_line = 1,
                replacement = { "mutated" },
              },
            },
          },
        },
      })

      assert(ok_create == false, "outside-root patch session should be denied")
      assert(
        tostring(err_or_session):find("outside project root", 1, true) ~= nil,
        "outside-root denial hint missing"
      )

      local denied = last_log_event("patch_session_denied")
      assert(type(denied) == "table", "patch_session_denied log missing")
      assert(
        type(denied.result) == "table" and denied.result.reason == "workspace_boundary_escape",
        "patch_session_denied log reason mismatch"
      )

      return {
        reason = denied.result.reason,
      }
    end,
  },
  {
    id = "security-post-call-audit-attribution",
    run = function()
      local gate = require("jig.security.gate")
      local pre = gate.pre_tool_call({
        actor = "agent",
        origin = "security.harness",
        action = "read",
        target = "fixture-target",
      })
      assert(pre.allowed == true, "pre-report expected allow for read fixture")

      local ok_post = gate.post_tool_call(pre, {
        ok = false,
        code = -1,
        reason = "fixture_denied",
        hint = "fixture_hint",
      }, {
        actor = "agent",
        origin = "security.harness",
        task_id = "task-sec-post",
        subagent = "subagent-a",
        server = "local-server",
        approval_id = "a-post",
        target = "fixture-target",
      })
      assert(ok_post == true, "post-tool audit should succeed")

      local event = last_log_event("security_post_tool_call")
      assert(type(event) == "table", "security_post_tool_call event missing")
      assert(type(event.request) == "table", "security_post_tool_call request missing")
      assert(event.request.subagent == "subagent-a", "subagent attribution missing")
      assert(event.request.server == "local-server", "server attribution missing")
      assert(event.request.approval_id == "a-post", "approval id attribution missing")

      return {
        event = event.event,
        policy_decision = event.policy_decision,
      }
    end,
  },
  {
    id = "threat-model-data-coverage",
    run = function()
      local model = read_json(repo_root() .. "/data/wp18/threat_model.json")
      local manifest = read_json(repo_root() .. "/data/wp18/fixtures_manifest.json")
      assert(type(model) == "table", "data/wp18/threat_model.json missing or invalid")
      assert(type(manifest) == "table", "data/wp18/fixtures_manifest.json missing or invalid")

      local required = {
        workspace_boundary_escape = false,
        argument_injection_patterns = false,
        consent_identity_confusion = false,
        prompt_injection_tool_misuse = false,
        unicode_trojan_source = false,
      }

      for _, class in ipairs(model.classes or {}) do
        if required[class.id] ~= nil then
          required[class.id] = true
        end
        assert(type(class.regression_tests) == "table", "threat class missing regression tests")
        assert(
          #(class.regression_tests or {}) >= 1,
          "threat class requires at least one regression test"
        )
      end

      for id, present in pairs(required) do
        assert(present == true, "missing threat model class: " .. id)
      end

      assert(
        type(manifest.fixtures) == "table" and #manifest.fixtures >= 5,
        "fixture manifest incomplete"
      )

      local evidence_path = repo_root() .. "/data/wp18/evidence.jsonl"
      local rows = read_jsonl(evidence_path)
      assert(#rows >= 6, "wp18 evidence index requires at least 6 entries")

      return {
        threat_classes = vim.tbl_count(required),
        fixtures = #manifest.fixtures,
        evidence_items = #rows,
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
