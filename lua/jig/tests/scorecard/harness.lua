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
    vim.fn.stdpath("state") .. "/jig/scorecard-harness-snapshot.json"
  )
end

local function run_command(argv, timeout_ms)
  local result = vim
    .system(argv, {
      cwd = repo_root(),
      text = true,
    })
    :wait(timeout_ms or 120000)

  if result == nil then
    return false,
      {
        reason = "wait_nil",
        argv = argv,
        hint = "increase timeout or inspect command runtime",
      }
  end

  if result.code ~= 0 then
    return false,
      {
        reason = "exit_nonzero",
        code = result.code,
        argv = argv,
        stdout = result.stdout,
        stderr = result.stderr,
      }
  end

  return true, {
    code = result.code,
    stdout = result.stdout,
    stderr = result.stderr,
  }
end

function M.run(opts)
  local report = fabric.run_cases({
    {
      id = "wp15-research-done-gate",
      run = function()
        return run_command({ "scripts/wp15/check_research_done.lua" })
      end,
    },
    {
      id = "wp15-gaps-gate",
      run = function()
        return run_command({ "scripts/wp15/check_gaps.lua" })
      end,
    },
    {
      id = "wp15-generate-scorecard",
      run = function()
        return run_command({ "scripts/wp15/generate_scorecard.lua" })
      end,
    },
    {
      id = "wp15-generate-dashboard",
      run = function()
        return run_command({ "scripts/wp15/generate_dashboard.lua" })
      end,
    },
    {
      id = "wp15-generated-sync-clean",
      run = function()
        return run_command({
          "git",
          "diff",
          "--exit-code",
          "--",
          "docs/roadmap/SCORECARD.md",
          "docs/roadmap/REGRESSION_DASHBOARD.md",
          "data/wp15/dashboard_snapshot.json",
        })
      end,
    },
  }, {
    harness = "headless-child-scorecard",
  })

  local path = snapshot_path(opts)
  fabric.finalize(report, {
    snapshot_path = path,
    fail_label = "scorecard harness",
  })
  print("scorecard-harness snapshot written: " .. path)
end

return M
