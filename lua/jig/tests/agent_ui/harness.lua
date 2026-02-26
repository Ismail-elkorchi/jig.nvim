local fabric = require("jig.tests.fabric")

local M = {}

local function repo_root()
  if type(_G.__jig_repo_root) == "string" and _G.__jig_repo_root ~= "" then
    return _G.__jig_repo_root
  end
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h:h:h:h")
end

local function snapshot_path(opts)
  return fabric.snapshot_path(
    opts,
    vim.fn.stdpath("state") .. "/jig/agent-ui-harness-snapshot.json"
  )
end

local function safe_env()
  local env = vim.fn.environ()
  env.NVIM_APPNAME = "jig-safe"
  return env
end

local function enable_agent()
  vim.g.jig_agent = {
    enabled = true,
  }
  local status = require("jig.agent").setup()
  assert(status.enabled == true, "agent module should be enabled")
end

local function reset_state()
  require("jig.agent.approvals").reset_for_test()
  require("jig.agent.patch").reset_for_test()
  require("jig.agent.policy").reset_for_test()
  require("jig.agent.instructions").reset_for_test()
  require("jig.agent.observability").reset()
end

local function write_file(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(lines, path)
end

local function read_file(path)
  if vim.fn.filereadable(path) ~= 1 then
    return {}
  end
  return vim.fn.readfile(path)
end

local function ascii_only(lines)
  local icons = require("jig.ui.icons")
  for _, line in ipairs(lines or {}) do
    if not icons.ascii_only(tostring(line)) then
      return false
    end
  end
  return true
end

local cases = {
  {
    id = "approval-notification-visible",
    run = function()
      reset_state()
      enable_agent()

      local approvals = require("jig.agent.approvals")
      local policy = require("jig.agent.policy")
      local chrome = require("jig.ui.chrome")

      local report = policy.authorize({
        tool = "agent.exec.test",
        action_class = "write",
        target = "fixture",
      }, {
        origin = "agent-ui-test",
      })

      assert(report.decision == "ask", "expected ask decision")
      assert(type(report.pending_id) == "string" and report.pending_id ~= "", "pending id missing")

      local pending = approvals.list({ status = "pending" })
      assert(#pending == 1, "pending approval queue should contain one item")

      local statusline = chrome.render_statusline(true, vim.api.nvim_get_current_buf())
      assert(statusline:find("approvals:1", 1, true) ~= nil, "statusline indicator missing")

      vim.cmd("JigAgentApprovals")
      assert(vim.g.jig_agent_last_report.title == "JigAgentApprovals", "queue report not rendered")

      local ok_resolve = approvals.resolve(report.pending_id, "deny_once")
      assert(ok_resolve == true, "approval resolution failed")
      assert(approvals.pending_count() == 0, "pending approvals should clear after resolution")

      local cleared = chrome.render_statusline(true, vim.api.nvim_get_current_buf())
      assert(cleared:find("approvals:", 1, true) == nil, "statusline indicator did not clear")

      local rows = require("jig.agent.log").tail(20)
      local saw_pending = false
      local saw_resolved = false
      for _, row in ipairs(rows) do
        if row.event == "approval_pending" then
          saw_pending = true
        elseif row.event == "approval_resolved" then
          saw_resolved = true
        end
      end

      assert(saw_pending == true, "approval_pending event missing")
      assert(saw_resolved == true, "approval_resolved event missing")

      return true,
        {
          pending_id = report.pending_id,
          pending_count = #pending,
        }
    end,
  },
  {
    id = "policy-persistence-reload",
    run = function()
      reset_state()
      enable_agent()

      local policy = require("jig.agent.policy")
      local ok_grant, rule = policy.grant({
        decision = "allow",
        tool = "persist.tool",
        action_class = "write",
        target = "persist-target",
        scope = "project",
      })
      assert(ok_grant == true, "grant failed")
      assert(type(rule.id) == "string" and rule.id ~= "", "rule id missing")
      assert(vim.fn.filereadable(policy.path()) == 1, "policy persistence file missing")

      package.loaded["jig.agent.policy"] = nil
      local policy_reloaded = require("jig.agent.policy")
      local report = policy_reloaded.authorize({
        tool = "persist.tool",
        action_class = "write",
        target = "persist-target",
      }, {
        queue = false,
      })

      assert(report.allowed == true and report.decision == "allow", "persisted rule not loaded")

      return true,
        {
          policy_path = policy_reloaded.path(),
          decision = report.decision,
        }
    end,
  },
  {
    id = "patch-pipeline-multifile-hunk-apply",
    run = function()
      reset_state()
      enable_agent()

      local patch = require("jig.agent.patch")
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")

      local file_one = tmp .. "/one.txt"
      local file_two = tmp .. "/two.txt"
      write_file(file_one, { "a", "b", "c", "d" })
      write_file(file_two, { "q", "r", "s" })

      local ok_create, session = patch.create({
        intent = "agent_patch_candidate",
        summary = "apply selected hunks",
        files = {
          {
            path = file_one,
            hunks = {
              {
                start_line = 2,
                end_line = 2,
                replacement = { "B2" },
                summary = "replace line 2",
              },
              {
                start_line = 4,
                end_line = 4,
                replacement = { "D2" },
                summary = "replace line 4",
              },
            },
          },
          {
            path = file_two,
            hunks = {
              {
                start_line = 1,
                end_line = 1,
                replacement = { "Q2" },
                summary = "replace first line",
              },
            },
          },
        },
      })

      assert(ok_create == true, "patch session creation failed")
      assert(patch.accept_hunk(session.id, 1, 1))
      assert(patch.reject_hunk(session.id, 1, 2))
      assert(patch.accept_hunk(session.id, 2, 1))

      local ok_apply = patch.apply(session.id)
      assert(ok_apply == true, "patch apply failed")

      local after_one = read_file(file_one)
      local after_two = read_file(file_two)
      assert(vim.deep_equal(after_one, { "a", "B2", "c", "d" }), "file one mismatch")
      assert(vim.deep_equal(after_two, { "Q2", "r", "s" }), "file two mismatch")

      return true,
        {
          session_id = session.id,
          file_one = after_one,
          file_two = after_two,
        }
    end,
  },
  {
    id = "patch-rollback-checkpoint",
    run = function()
      reset_state()
      enable_agent()

      local patch = require("jig.agent.patch")
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")

      local target = tmp .. "/rollback.txt"
      write_file(target, { "alpha", "beta", "gamma" })

      local ok_create, session = patch.create({
        intent = "rollback_check",
        summary = "checkpoint should restore",
        files = {
          {
            path = target,
            hunks = {
              {
                start_line = 2,
                end_line = 2,
                replacement = { "BETA2" },
                summary = "mutate line",
              },
            },
          },
        },
      })

      assert(ok_create == true, "patch create failed")
      assert(patch.apply_all(session.id))
      assert(patch.apply(session.id))

      local changed = read_file(target)
      assert(vim.deep_equal(changed, { "alpha", "BETA2", "gamma" }), "apply mismatch")

      local ok_rollback = patch.rollback(session.id)
      assert(ok_rollback == true, "rollback failed")

      local restored = read_file(target)
      assert(vim.deep_equal(restored, { "alpha", "beta", "gamma" }), "rollback mismatch")

      return true, {
        session_id = session.id,
        restored = restored,
      }
    end,
  },
  {
    id = "patch-direct-write-blocked-and-logged",
    run = function()
      reset_state()
      enable_agent()

      local patch = require("jig.agent.patch")
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")

      local target = tmp .. "/direct-write.txt"
      write_file(target, { "safe", "content" })

      local result = patch.write_direct(target, { "unsafe", "overwrite" }, {
        task_id = "t-direct",
      })

      assert(result.ok == false, "direct write should be blocked")
      assert(result.reason == "patch_pipeline_required", "unexpected denial reason")
      assert(vim.deep_equal(read_file(target), { "safe", "content" }), "file changed unexpectedly")

      local rows = require("jig.agent.log").tail(20)
      local saw_denied = false
      for _, row in ipairs(rows) do
        if row.event == "patch_direct_write_denied" then
          saw_denied = true
          break
        end
      end
      assert(saw_denied == true, "missing patch_direct_write_denied event")

      return true, {
        reason = result.reason,
      }
    end,
  },
  {
    id = "diff-legibility-and-drilldown-ascii",
    run = function()
      reset_state()
      enable_agent()

      local icons = require("jig.ui.icons")
      local previous_mode = icons.mode()
      icons.set_mode("ascii")

      local patch = require("jig.agent.patch")
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")
      local target = tmp .. "/legible.txt"
      write_file(target, { "one", "two", "three" })

      local ok_create, session = patch.create({
        intent = "legibility",
        summary = "review metadata and range rendering",
        files = {
          {
            path = target,
            hunks = {
              {
                start_line = 2,
                end_line = 2,
                replacement = { "TWO2" },
                summary = "replace middle line",
              },
            },
          },
        },
      })
      assert(ok_create == true, "patch create failed")

      local ok_review, review_view = patch.open_review(session.id)
      assert(ok_review == true, "review view failed")
      assert(review_view.headless == true, "headless review expected")

      local review_lines = vim.g.jig_patch_last_report.lines
      local joined_review = table.concat(review_lines, "\n")
      assert(joined_review:find("files:", 1, true) ~= nil, "missing files section")
      assert(joined_review:find("range=2-2", 1, true) ~= nil, "missing line range")
      assert(joined_review:find("summary", 1, true) ~= nil, "missing summary")
      assert(ascii_only(review_lines) == true, "review lines must remain ASCII")

      local ok_hunk, hunk_view = patch.open_hunk(session.id, 1, 1)
      assert(ok_hunk == true, "hunk view failed")
      assert(hunk_view.headless == true, "headless hunk expected")
      local hunk_lines = vim.g.jig_patch_last_hunk.lines
      local joined_hunk = table.concat(hunk_lines, "\n")
      assert(joined_hunk:find("--- " .. target, 1, true) ~= nil, "missing hunk file header")
      assert(joined_hunk:find("@@", 1, true) ~= nil, "missing hunk marker")

      icons.set_mode(previous_mode)

      return true,
        {
          session_id = session.id,
          review_lines = #review_lines,
          hunk_lines = #hunk_lines,
        }
    end,
  },
  {
    id = "context-ledger-add-remove-budget-reset",
    run = function()
      reset_state()
      enable_agent()

      local observability = require("jig.agent.observability")
      local opts = {
        user = {
          enabled = true,
          observability = {
            budget_bytes = 10,
            warning_ratio = 0.5,
          },
        },
      }

      local ok_add_one = observability.add_source({
        id = "session:a",
        kind = "fixture",
        label = "A",
        bytes = 6,
        chars = 6,
      }, opts)
      assert(ok_add_one == true, "first source add failed")

      local ok_add_two, err_add_two = observability.add_source({
        id = "session:b",
        kind = "fixture",
        label = "B",
        bytes = 6,
        chars = 6,
      }, opts)
      assert(ok_add_two == false, "second source add should exceed budget")
      assert(type(err_add_two) == "string" and err_add_two ~= "", "missing budget error")

      local listed = observability.list_session_sources()
      assert(#listed == 1 and listed[1].id == "session:a", "session source list mismatch")

      assert(observability.remove_source("session:a") == true)
      assert(observability.add_source({
        id = "session:b",
        kind = "fixture",
        label = "B",
        bytes = 6,
        chars = 6,
      }, opts) == true)

      local report = observability.capture(opts)
      assert(type(report.sources) == "table" and #report.sources >= 1, "missing ledger sources")

      observability.reset()
      assert(#observability.list_session_sources() == 0, "reset should clear sources")

      return true, {
        warnings = report.warnings,
        totals = report.totals,
      }
    end,
  },
  {
    id = "instruction-precedence-disable-persist-revoke",
    run = function()
      reset_state()
      enable_agent()

      local instructions = require("jig.agent.instructions")
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")

      local project_file = tmp .. "/AGENTS.md"
      local user_file = tmp .. "/USER_INSTRUCTIONS.md"
      local global_file = tmp .. "/GLOBAL_INSTRUCTIONS.md"

      write_file(project_file, { "project-rule" })
      write_file(user_file, { "user-rule" })
      write_file(global_file, { "global-rule" })

      local opts = {
        root = tmp,
        user = {
          enabled = true,
          instructions = {
            precedence = { "project", "user", "global" },
            project_files = { "AGENTS.md" },
            user_paths = { user_file },
            global_paths = { global_file },
          },
        },
      }

      local merged = instructions.merge(opts)
      assert(
        merged.merged_text:find("project%-rule", 1, false) ~= nil
          and merged.merged_text:find("user%-rule", 1, false) ~= nil
          and merged.merged_text:find("global%-rule", 1, false) ~= nil,
        "initial merge missing sources"
      )

      local report = instructions.collect(opts)
      local user_source_id = nil
      for _, source in ipairs(report.sources) do
        if source.scope == "user" then
          user_source_id = source.id
          break
        end
      end
      assert(type(user_source_id) == "string" and user_source_id ~= "", "user source id not found")

      local ok_disable = instructions.disable(user_source_id, opts)
      assert(ok_disable == true, "disable failed")

      local merged_disabled = instructions.merge(opts)
      assert(
        merged_disabled.merged_text:find("user%-rule", 1, false) == nil,
        "disabled user source still present"
      )
      assert(merged_disabled.disabled_count >= 1, "disabled count missing")

      package.loaded["jig.agent.instructions"] = nil
      local instructions_reloaded = require("jig.agent.instructions")
      local merged_reloaded = instructions_reloaded.merge(opts)
      assert(
        merged_reloaded.merged_text:find("user%-rule", 1, false) == nil,
        "disabled source not persisted after reload"
      )

      local ok_enable = instructions_reloaded.enable(user_source_id, opts)
      assert(ok_enable == true, "enable failed")
      local merged_enabled = instructions_reloaded.merge(opts)
      assert(
        merged_enabled.merged_text:find("user%-rule", 1, false) ~= nil,
        "enabled source not restored"
      )

      local rows = require("jig.agent.log").tail(40)
      local saw_disable = false
      local saw_enable = false
      for _, row in ipairs(rows) do
        if row.event == "instruction_source_disabled" then
          saw_disable = true
        elseif row.event == "instruction_source_enabled" then
          saw_enable = true
        end
      end
      assert(saw_disable == true, "missing instruction_source_disabled event")
      assert(saw_enable == true, "missing instruction_source_enabled event")

      return true, {
        user_source_id = user_source_id,
      }
    end,
  },
  {
    id = "safe-profile-wp17-command-isolation",
    run = function()
      local root = repo_root()
      local result = vim
        .system({
          "nvim",
          "--headless",
          "-u",
          root .. "/init.lua",
          [[+lua local names={'JigAgentApprovals','JigAgentApprovalResolve','JigPatchCreate','JigPatchReview','JigPatchApply','JigPatchRollback','JigAgentInstructionDisable','JigAgentInstructionEnable','JigAgentContextAdd','JigAgentContextRemove'}; for _,name in ipairs(names) do assert(vim.fn.exists(':'..name)==0,name) end; assert(package.loaded['jig.agent']==nil)]],
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
      return true, {
        code = result.code,
      }
    end,
  },
}

function M.run(opts)
  local report = fabric.run_cases(cases, {
    harness = "headless-child-agent-ui",
    retry_defaults = {
      timing_sensitive_retries = 3,
      timing_sensitive_delay_ms = 80,
    },
  })

  local path = snapshot_path(opts)
  fabric.finalize(report, {
    snapshot_path = path,
    fail_label = "agent-ui harness",
  })

  print("agent-ui-harness snapshot written: " .. path)
end

return M
