local backend = require("jig.nav.backend")
local fabric = require("jig.tests.fabric")
local nav_fixture = require("jig.tests.fixtures.nav_repo")

local M = {}

local function repo_root()
  if type(_G.__jig_repo_root) == "string" and _G.__jig_repo_root ~= "" then
    return _G.__jig_repo_root
  end
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h:h:h:h")
end

local function snapshot_path(opts)
  return fabric.snapshot_path(opts, vim.fn.stdpath("state") .. "/jig/perf-harness-snapshot.json")
end

local function budget_path()
  return repo_root() .. "/tests/perf/budgets.json"
end

local function load_budgets()
  local decoded = fabric.load_json(budget_path())
  assert(type(decoded) == "table", "perf budgets JSON is invalid")
  return decoded
end

local function elapsed_ms(started)
  return math.floor((vim.uv.hrtime() - started) / 1000000)
end

local function ensure_under(value, limit, label)
  assert(type(value) == "number", label .. " missing")
  assert(type(limit) == "number", label .. " limit missing")
  assert(value <= limit, string.format("%s exceeded (%d > %d)", label, value, limit))
end

local function probe_first_diagnostic(limit)
  local bufnr = vim.api.nvim_create_buf(true, true)
  local ns = vim.api.nvim_create_namespace("jig.tests.perf")
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1" })

  local observed = nil
  local started = vim.uv.hrtime()

  local augroup = vim.api.nvim_create_augroup("JigPerfDiagnostic", { clear = true })
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = augroup,
    buffer = bufnr,
    once = true,
    callback = function()
      observed = elapsed_ms(started)
    end,
  })

  vim.defer_fn(function()
    vim.diagnostic.set(ns, bufnr, {
      {
        lnum = 0,
        col = 0,
        end_lnum = 0,
        end_col = 5,
        message = "perf diagnostic",
        severity = vim.diagnostic.severity.WARN,
      },
    })
  end, 20)

  local done = vim.wait(2000, function()
    return observed ~= nil
  end, 10)

  vim.api.nvim_del_augroup_by_id(augroup)
  vim.diagnostic.reset(ns, bufnr)
  vim.api.nvim_buf_delete(bufnr, { force = true })

  assert(done == true and observed ~= nil, "first diagnostic event not observed")
  ensure_under(observed, limit, "first-diagnostic-ms")
  return observed
end

local function probe_first_completion(limit)
  local words = {}
  for i = 1, 2000 do
    words[#words + 1] = string.format("token_%04d", i)
  end

  local started = vim.uv.hrtime()
  local matches = vim.fn.matchfuzzy(words, "token_19")
  local observed = elapsed_ms(started)

  assert(type(matches) == "table" and #matches > 0, "completion fallback returned no matches")
  ensure_under(observed, limit, "first-completion-ms")
  return observed
end

local function probe_picker_tier(tier, limit)
  local generated = nav_fixture.generate({
    tier = tier,
    base_dir = repo_root() .. "/tests/fixtures/generated/nav_perf",
  })

  local started = vim.uv.hrtime()
  local result = backend.files({ root = generated.root }, {
    select = false,
    candidate_cap = 100,
    cap = 100,
    ignore_globs = { "node_modules/**", "build/**" },
  })
  local observed = elapsed_ms(started)

  assert(type(result) == "table", "picker result missing")
  assert(type(result.count) == "number" and result.count > 0, "picker returned no candidates")
  assert(result.count <= 100, "picker exceeded cap")
  ensure_under(observed, limit, "picker-first-ms:" .. tier)

  return {
    elapsed_ms = observed,
    count = result.count,
    fixture_files = generated.files,
    fixture_reused = generated.reused,
  }
end

local function probe_all()
  local budgets = load_budgets()
  local picker_limits = budgets.picker_first_ms or {}

  local diagnostics_ms = probe_first_diagnostic(tonumber(budgets.diagnostic_first_ms) or 800)
  local completion_ms = probe_first_completion(tonumber(budgets.completion_first_ms) or 400)

  local picker = {
    small = probe_picker_tier("small", tonumber(picker_limits.small) or 800),
    medium = probe_picker_tier("medium", tonumber(picker_limits.medium) or 1600),
    large = probe_picker_tier("large", tonumber(picker_limits.large) or 2600),
  }

  return {
    budgets = budgets,
    probes = {
      time_to_first_diagnostic_ms = diagnostics_ms,
      time_to_first_completion_ms = completion_ms,
      time_to_first_picker_ms = picker,
    },
  }
end

function M.run(opts)
  local cached = probe_all()

  local report = fabric.run_cases({
    {
      id = "time-to-first-diagnostic",
      run = function()
        return {
          diagnostic_ms = cached.probes.time_to_first_diagnostic_ms,
          budget_ms = cached.budgets.diagnostic_first_ms,
        }
      end,
    },
    {
      id = "time-to-first-completion-menu",
      run = function()
        return {
          completion_ms = cached.probes.time_to_first_completion_ms,
          mode = "fallback-confirmation",
          budget_ms = cached.budgets.completion_first_ms,
        }
      end,
    },
    {
      id = "time-to-first-picker-results",
      run = function()
        return {
          picker = cached.probes.time_to_first_picker_ms,
          budgets = cached.budgets.picker_first_ms,
        }
      end,
    },
  }, {
    harness = "headless-child-perf",
  })

  report.metrics = cached.probes
  report.budgets = cached.budgets

  local path = snapshot_path(opts)
  fabric.finalize(report, {
    snapshot_path = path,
    fail_label = "perf harness",
  })
  print("perf-harness snapshot written: " .. path)
end

return M
