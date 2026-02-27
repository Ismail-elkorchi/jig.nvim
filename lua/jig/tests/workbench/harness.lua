local fabric = require("jig.tests.fabric")
local brand = require("jig.core.brand")
local icons = require("jig.ui.icons")
local workbench = require("jig.workbench")

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
    vim.fn.stdpath("state") .. "/jig/workbench-harness-snapshot.json"
  )
end

local function role_counts()
  local out = {
    main = 0,
    nav = 0,
    term = 0,
    agent = 0,
  }

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    local role = tostring(vim.b[bufnr].jig_workbench_role or "")
    if out[role] ~= nil then
      out[role] = out[role] + 1
    end
  end

  return out
end

local function nav_lines(state)
  if
    type(state) ~= "table"
    or type(state.windows) ~= "table"
    or state.windows.nav == nil
    or not vim.api.nvim_win_is_valid(state.windows.nav)
  then
    return {}
  end
  local bufnr = vim.api.nvim_win_get_buf(state.windows.nav)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
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
      "+lua assert(vim.fn.exists(':JigWorkbench')==0)",
      "+lua assert(vim.fn.exists(':JigWorkbenchReset')==0)",
      "+lua assert(vim.fn.exists(':JigWorkbenchHelp')==0)",
      "+lua assert(package.loaded['jig.workbench']==nil)",
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

local cases = {
  {
    id = "research-done-r1-r5-gate",
    run = function()
      local checker = require("jig.workbench.research_check")
      local ok, report = checker.run({ root = repo_root() })
      assert(ok == true, "research gate failed: " .. table.concat(report.errors or {}, ", "))
      return true, {
        checks = report.checks,
      }
    end,
  },
  {
    id = "default-command-surface",
    run = function()
      assert(vim.fn.exists(":JigWorkbench") == 2, "JigWorkbench command missing")
      assert(vim.fn.exists(":JigWorkbenchReset") == 2, "JigWorkbenchReset command missing")
      assert(vim.fn.exists(":JigWorkbenchHelp") == 2, "JigWorkbenchHelp command missing")
      return true, {
        commands = 3,
      }
    end,
  },
  {
    id = "workbench-help-command-surface",
    run = function()
      local ok, err = pcall(vim.cmd, brand.command("WorkbenchHelp"))
      assert(ok == true, "workbench help command failed: " .. tostring(err))

      local marker = type(vim.g.jig_workbench_help_last) == "table"
          and vim.g.jig_workbench_help_last
        or {}
      local is_help = marker.mode == "help"
      local is_docs_fallback = marker.mode == "docs_index_fallback"
      assert(is_help or is_docs_fallback, "workbench help marker missing")
      return true, {
        mode = marker.mode,
        docs_mode = marker.docs_mode,
      }
    end,
  },
  {
    id = "dev-preset-idempotent-layout",
    run = function()
      assert(icons.set_mode("ascii"), "failed to set ascii icon mode")
      local ok, state = workbench._ensure_layout_for_test("dev")
      assert(ok == true, "workbench dev preset failed")
      assert(state.operations.networkish == false, "network-ish command detected in dev preset")

      local first = role_counts()
      assert(first.nav == 1, "dev preset must create one nav pane")
      assert(first.term == 1, "dev preset must create one terminal pane")
      assert(first.agent == 0, "dev preset must not create agent pane")
      assert(first.main >= 1, "dev preset must keep main pane")

      local nav = nav_lines(state)
      for _, line in ipairs(nav) do
        assert(icons.ascii_only(line), "ascii fallback violated in nav line: " .. tostring(line))
      end

      local ok2, state2 = workbench._ensure_layout_for_test("dev")
      assert(ok2 == true, "second dev preset invocation failed")
      assert(state2.operations.networkish == false, "network-ish command on second run")
      local second = role_counts()
      assert(vim.deep_equal(first, second), "layout did not converge on second run")

      local cmdline_ok = require("jig.ui.cmdline").open_close_check()
      assert(cmdline_ok == true, "cmdline open/close regression after workbench")

      return true, {
        first = first,
        second = second,
      }
    end,
  },
  {
    id = "review-preset-git-surface",
    run = function()
      local ok, state = workbench._ensure_layout_for_test("review")
      assert(ok == true, "workbench review preset failed")
      assert(state.operations.networkish == false, "network-ish command detected in review preset")
      assert(state.role_counts.nav == 1, "review preset nav pane missing")
      assert(state.role_counts.term == 1, "review preset terminal pane missing")

      local lines = nav_lines(state)
      local joined = table.concat(lines, "\n")
      assert(joined:find("JigGitChanges", 1, true) ~= nil, "review nav missing git entrypoint")

      return true, {
        nav_lines = #lines,
      }
    end,
  },
  {
    id = "minimal-preset-no-terminal",
    run = function()
      local ok, state = workbench._ensure_layout_for_test("minimal")
      assert(ok == true, "workbench minimal preset failed")
      assert(state.role_counts.nav == 1, "minimal preset nav pane missing")
      assert(state.role_counts.term == 0, "minimal preset must not create terminal")
      assert(state.role_counts.agent == 0, "minimal preset must not create agent pane")
      return true, {
        role_counts = state.role_counts,
      }
    end,
  },
  {
    id = "agent-preset-disabled-fallback",
    run = function()
      local ok, state = workbench._ensure_layout_for_test("agent")
      assert(ok == true, "workbench agent preset failed")
      assert(state.agent_state == "skipped_agent_disabled", "agent-disabled fallback mismatch")
      assert(state.role_counts.agent == 0, "agent pane should not render when module disabled")
      return true, {
        agent_state = state.agent_state,
      }
    end,
  },
  {
    id = "agent-preset-enabled-panel",
    run = function()
      vim.g.jig_agent = { enabled = true }
      local agent_status = require("jig.agent").setup()
      assert(agent_status.enabled == true, "agent setup failed for workbench harness")

      local ok, state = workbench._ensure_layout_for_test("agent")
      assert(ok == true, "workbench agent preset with agent enabled failed")
      assert(state.agent_state == "enabled", "agent pane should be enabled")
      assert(state.role_counts.agent == 1, "agent pane should render once")

      local win = state.windows.agent
      assert(win and vim.api.nvim_win_is_valid(win), "agent pane window invalid")
      local bufnr = vim.api.nvim_win_get_buf(win)
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local joined = table.concat(lines, "\n")
      assert(
        joined:find("JigAgentApprovals", 1, true) ~= nil,
        "agent pane missing approvals entrypoint"
      )
      assert(
        joined:find("JigPatchReview", 1, true) ~= nil,
        "agent pane missing patch review entrypoint"
      )

      return true, {
        agent_lines = #lines,
      }
    end,
  },
  {
    id = "safe-profile-isolation",
    run = function()
      local payload = run_safe_assertions()
      return true, payload
    end,
  },
}

function M.run(opts)
  local report = fabric.run_cases(cases, {
    harness = "headless-child-workbench",
  })

  local path = snapshot_path(opts)
  fabric.finalize(report, {
    snapshot_path = path,
    fail_label = "workbench harness",
  })
  print("workbench-harness snapshot written: " .. path)
end

return M
