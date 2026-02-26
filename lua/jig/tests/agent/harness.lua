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
  return vim.fn.stdpath("state") .. "/jig/agent-harness-snapshot.json"
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
      [[+lua local names={'JigMcpList','JigMcpStart','JigMcpStop','JigMcpTools','JigMcpCall','JigAgentContext','JigAgentApprovals','JigAgentApprovalResolve','JigPatchCreate','JigPatchReview','JigPatchApply','JigPatchRollback','JigAgentInstructionDisable','JigAgentInstructionEnable','JigAgentContextAdd','JigAgentContextRemove'}; for _,name in ipairs(names) do assert(vim.fn.exists(':'..name)==0,name) end; assert(package.loaded['jig.agent']==nil)]],
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
  return {
    code = result.code,
  }
end

local function fixture_paths()
  local root = repo_root()
  return {
    mcp_server = root .. "/tests/fixtures/mcp/fake_mcp_server.sh",
    acp_agent = root .. "/tests/fixtures/agent/fake_acp_agent.sh",
  }
end

local function setup_mcp_fixture_root()
  local paths = fixture_paths()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")

  local payload = {
    mcpServers = {
      ok = {
        command = paths.mcp_server,
        args = { "ok" },
        timeout_ms = 1200,
        tools = {
          echo = {
            action_class = "net",
            target = "ok",
          },
        },
      },
      early = {
        command = paths.mcp_server,
        args = { "early_exit" },
        timeout_ms = 1200,
      },
      timeout = {
        command = paths.mcp_server,
        args = { "timeout" },
        timeout_ms = 10,
      },
      malformed = {
        command = paths.mcp_server,
        args = { "malformed" },
        timeout_ms = 1200,
      },
      tool_missing = {
        command = paths.mcp_server,
        args = { "tool_not_found" },
        timeout_ms = 1200,
        tools = {
          unknown = {
            action_class = "net",
            target = "tool_missing",
          },
        },
      },
      misdeclared = {
        command = paths.mcp_server,
        args = { "ok" },
        timeout_ms = 1200,
        tools = {
          echo = {
            action_class = "read",
            target = "misdeclared",
          },
        },
      },
      missing = {
        command = "__jig_missing_mcp_binary__",
        args = {},
      },
    },
  }

  vim.fn.writefile({ vim.json.encode(payload) }, root .. "/.mcp.json")
  return root
end

local function reset_state()
  require("jig.agent.policy").reset_for_test()
  require("jig.agent.task").reset_for_test()
  require("jig.agent.mcp.client").reset_for_test()
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

local cases = {
  {
    id = "default-profile-agent-disabled",
    run = function()
      assert(command_exists("JigMcpList") == false, "JigMcpList should be absent by default")
      assert(command_exists("JigMcpStart") == false, "JigMcpStart should be absent by default")
      assert(package.loaded["jig.agent"] == nil, "agent module should not autoload")
      return {
        commands_absent = true,
      }
    end,
  },
  {
    id = "explicit-enable-command-surface",
    run = function()
      vim.g.jig_agent = {
        enabled = true,
      }
      local status = require("jig.agent").setup()
      assert(status.enabled == true, "agent setup should enable module")
      assert(command_exists("JigMcpList"), "JigMcpList missing")
      assert(command_exists("JigMcpStart"), "JigMcpStart missing")
      assert(command_exists("JigMcpStop"), "JigMcpStop missing")
      assert(command_exists("JigMcpTools"), "JigMcpTools missing")
      assert(command_exists("JigMcpCall"), "JigMcpCall missing")
      assert(command_exists("JigAgentContext"), "JigAgentContext missing")
      assert(command_exists("JigAgentApprovals"), "JigAgentApprovals missing")
      assert(command_exists("JigAgentApprovalResolve"), "JigAgentApprovalResolve missing")
      assert(command_exists("JigPatchCreate"), "JigPatchCreate missing")
      assert(command_exists("JigPatchReview"), "JigPatchReview missing")
      assert(command_exists("JigPatchApply"), "JigPatchApply missing")
      assert(command_exists("JigPatchRollback"), "JigPatchRollback missing")
      assert(command_exists("JigAgentInstructionDisable"), "JigAgentInstructionDisable missing")
      assert(command_exists("JigAgentInstructionEnable"), "JigAgentInstructionEnable missing")
      assert(command_exists("JigAgentContextAdd"), "JigAgentContextAdd missing")
      assert(command_exists("JigAgentContextRemove"), "JigAgentContextRemove missing")
      return {
        enabled = status.enabled,
      }
    end,
  },
  {
    id = "permission-policy-unit",
    run = function()
      reset_state()
      local policy = require("jig.agent.policy")
      local task = require("jig.agent.task")

      local read_allow = policy.authorize({
        tool = "read.tool",
        action_class = "read",
        target = "*",
      })
      assert(
        read_allow.allowed == true and read_allow.decision == "allow",
        "read must default allow"
      )

      local net_ask = policy.authorize({
        tool = "net.tool",
        action_class = "net",
        target = "svc",
      })
      assert(net_ask.allowed == false and net_ask.decision == "ask", "net must default ask")

      local parent = task.start({ title = "parent" })
      local child = task.start({ title = "child", parent_task_id = parent.id })

      local ok_grant, rule = policy.grant({
        decision = "allow",
        tool = "net.tool",
        action_class = "net",
        target = "svc",
        scope = "task",
        task_id = parent.id,
        inherit = true,
      })
      assert(ok_grant == true, "task scope grant failed")

      local inherited = policy.authorize({
        tool = "net.tool",
        action_class = "net",
        target = "svc",
        task_id = child.id,
      })
      assert(inherited.allowed == true, "subagent inheritance must preserve grant")

      local ok_deny = policy.grant({
        decision = "deny",
        tool = "net.tool",
        action_class = "net",
        target = "svc",
        scope = "global",
      })
      assert(ok_deny == true, "deny grant failed")

      local denied = policy.authorize({
        tool = "net.tool",
        action_class = "net",
        target = "svc",
        task_id = child.id,
      })
      assert(denied.allowed == false and denied.decision == "deny", "deny must take precedence")

      local ok_revoke, revoked = policy.revoke(rule.id)
      assert(ok_revoke == true and revoked.id == rule.id, "revocation failed")

      return {
        inherited_decision = inherited.decision,
        denied_decision = denied.decision,
      }
    end,
  },
  {
    id = "task-cancel-resume",
    labels = { "timing-sensitive" },
    retries = 3,
    retry_delay_ms = 80,
    run = function()
      reset_state()
      local task = require("jig.agent.task")

      local item = task.start({
        title = "long-run",
        kind = "harness",
        run = function(ctx)
          vim.wait(400, function()
            return ctx.is_cancelled()
          end, 20)
          if ctx.is_cancelled() then
            return {
              cancelled = true,
            }
          end
          return {
            completed = true,
          }
        end,
      })

      local ok_cancel = task.cancel(item.id, "harness_cancel")
      assert(ok_cancel == true, "cancel should succeed")

      local cancelled = task.get(item.id)
      assert(cancelled.status == "cancelled", "task should be cancelled")

      local ok_resume, resumed = task.resume(item.id, {
        run = function()
          return {
            resumed = true,
          }
        end,
      })
      assert(ok_resume == true, "resume should succeed")
      assert(resumed.evidence_events >= 1, "resume should inspect evidence log")

      local finished = vim.wait(3000, function()
        local current = task.get(item.id)
        return current and current.status == "completed"
      end, 20)
      assert(finished == true, "resumed task did not complete")

      local completed = task.get(item.id)
      return {
        status = completed.status,
        resume_count = completed.resume_count,
      }
    end,
  },
  {
    id = "mcp-failure-injection",
    run = function()
      reset_state()
      local policy = require("jig.agent.policy")
      local mcp = require("jig.agent.mcp.client")
      local mcp_trust = require("jig.security.mcp_trust")
      local security = require("jig.security")
      local root = require("jig.nav.root")

      security.mark_startup_done("agent-harness-mcp")

      mcp_trust.reset_for_test()
      local fixture_root = setup_mcp_fixture_root()
      local ok_set, err_set = root.set(fixture_root)
      assert(ok_set == true, tostring(err_set))

      local listing = mcp.list()
      assert(#listing.servers >= 7, "fixture MCP servers missing")

      local discovered = mcp.discovery()
      for _, server in pairs(discovered.servers or {}) do
        local ok_trust = mcp_trust.set_state(server, "allow")
        assert(ok_trust == true, "trust allow failed for " .. tostring(server.name))
      end

      local ok_shell_allow = policy.grant({
        decision = "allow",
        tool = "*",
        action_class = "shell",
        target = "*",
        scope = "global",
      })
      assert(ok_shell_allow == true, "shell allow grant failed")

      local missing = mcp.start("missing", { actor = "user" })
      assert(
        missing.ok == false and missing.reason == "missing_binary",
        "missing binary path failed"
      )

      local early = mcp.start("early", { actor = "user" })
      assert(early.ok == false, "early-exit path must fail")

      local timeout = mcp.start("timeout", { actor = "user" })
      assert(timeout.ok == false and timeout.reason == "timeout", "timeout path must fail")

      local malformed = mcp.start("malformed", { actor = "user" })
      assert(
        malformed.ok == false and malformed.reason == "malformed_response",
        "malformed path must fail"
      )

      local started = mcp.start("ok", { actor = "user" })
      assert(started.ok == true, "ok server should start")

      local tools = mcp.tools("ok", { actor = "user" })
      assert(tools.ok == true, "tools/list should pass")

      local blocked = mcp.call("ok", "echo", {
        message = "hello",
      }, { actor = "user" })
      assert(
        blocked.ok == false and blocked.reason == "blocked_by_policy",
        "mcp.call must route through policy ask/deny"
      )

      local ok_allow = policy.grant({
        decision = "allow",
        tool = "mcp.call.echo",
        action_class = "net",
        target = "ok",
        scope = "global",
      })
      assert(ok_allow == true, "allow grant failed")

      local allowed = mcp.call("ok", "echo", {
        message = "hello",
      }, { actor = "user" })
      assert(allowed.ok == true, "allowed call should pass")

      local tool_missing_start = mcp.start("tool_missing", { actor = "user" })
      assert(tool_missing_start.ok == true, "tool_missing server should start")

      local ok_allow_unknown = policy.grant({
        decision = "allow",
        tool = "mcp.call.unknown",
        action_class = "net",
        target = "tool_missing",
        scope = "global",
      })
      assert(ok_allow_unknown == true, "allow grant for unknown tool failed")

      local tool_missing = mcp.call("tool_missing", "unknown", {}, { actor = "user" })
      assert(
        tool_missing.ok == false and tool_missing.reason == "tool_not_found",
        "tool not found path should be explicit"
      )

      local misdeclared_start = mcp.start("misdeclared", { actor = "user" })
      assert(misdeclared_start.ok == true, "misdeclared server should start")

      local misdeclared_server = discovered.servers["misdeclared"]
      local misdeclared = mcp_trust.authorize_tool(misdeclared_server, "echo", {
        action_class = "net",
      })
      assert(
        misdeclared.allowed == false and misdeclared.reason == "capability-action-mismatch",
        "misdeclared capability mismatch must be denied"
      )

      local stopped = mcp.stop("ok")
      assert(stopped.ok == true, "stop should succeed")

      local cancelled = mcp.call("ok", "echo", {
        message = "post-stop",
      }, { actor = "user" })
      assert(
        cancelled.ok == false and cancelled.reason == "not_started",
        "post-stop call should be interrupted with not_started"
      )

      root.reset()

      return {
        listing_servers = #listing.servers,
        early_reason = early.reason,
        timeout_reason = timeout.reason,
        malformed_reason = malformed.reason,
        misdeclared_reason = misdeclared.reason,
        cancelled_reason = cancelled.reason,
      }
    end,
  },
  {
    id = "acp-bridge-hook",
    run = function()
      reset_state()
      local backends = require("jig.agent.backends")
      local policy = require("jig.agent.policy")
      local paths = fixture_paths()

      local spec = {
        name = "fixture-acp",
        command = paths.acp_agent,
        args = { "ok" },
        timeout_ms = 1200,
      }

      local ok_shell_allow = policy.grant({
        decision = "allow",
        tool = "acp.handshake",
        action_class = "shell",
        target = "fixture-acp",
        scope = "global",
      })
      assert(ok_shell_allow == true, "acp handshake allow grant failed")

      local handshake = backends.handshake("acp-stdio", spec, {})
      assert(handshake.ok == true, "acp handshake should pass")

      local prompt = backends.prompt("acp-stdio", spec, "hello", {})
      assert(prompt.ok == true, "acp prompt should pass")
      assert(prompt.result.type == "candidate", "acp prompt must return candidate type")

      local ok_deny = policy.grant({
        decision = "deny",
        tool = "acp.prompt",
        action_class = "read",
        target = "fixture-acp",
        scope = "global",
      })
      assert(ok_deny == true, "deny grant for acp failed")

      local blocked = backends.prompt("acp-stdio", spec, "hello", {})
      assert(
        blocked.ok == false and blocked.reason == "blocked_by_policy",
        "acp tool calls must route through policy"
      )

      return {
        handshake_ok = handshake.ok,
        prompt_type = prompt.result.type,
      }
    end,
  },
  {
    id = "context-ledger-token-budget",
    run = function()
      reset_state()
      vim.g.jig_agent = {
        enabled = true,
      }
      local status = require("jig.agent").setup()
      assert(status.enabled == true, "agent setup should be enabled")

      local observability = require("jig.agent.observability")
      observability.reset()

      local report = observability.capture({
        user = {
          enabled = true,
          observability = {
            budget_bytes = 80,
            warning_ratio = 0.5,
          },
        },
        sources = {
          {
            id = "test.extra.large",
            kind = "fixture",
            label = "fixture-large",
            bytes = 120,
            chars = 120,
          },
        },
      })

      assert(type(report) == "table", "context ledger report missing")
      assert(type(report.sources) == "table" and #report.sources >= 2, "context sources missing")
      assert(type(report.warnings) == "table" and #report.warnings >= 1, "budget warning expected")
      assert(report.totals.bytes >= 120, "ledger totals bytes mismatch")

      return {
        warnings = report.warnings,
        totals = report.totals,
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
    harness = "headless-child-agent",
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
  print("agent-harness snapshot written: " .. path)

  if #failed > 0 then
    error("agent harness failed: " .. table.concat(failed, ", "))
  end
end

return M
