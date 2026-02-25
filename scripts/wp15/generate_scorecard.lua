#!/usr/bin/env -S nvim --headless -u NONE -l

local source = debug.getinfo(1, "S").source:sub(2)
local script_dir = vim.fn.fnamemodify(source, ":p:h")
local common = dofile(script_dir .. "/common.lua")

local ROOT = common.repo_root()
package.path = string.format("%s/lua/?.lua;%s/lua/?/init.lua;", ROOT, ROOT) .. package.path

local function coerce_string(value)
  if value == vim.NIL then
    return ""
  end
  return tostring(value or "")
end

local function as_boolean(value)
  return value == true
end

local function resolve_path(env_key, fallback)
  local value = vim.env[env_key]
  if type(value) == "string" and value ~= "" then
    if value:match("^/") then
      return value
    end
    return common.join(ROOT, value)
  end
  return common.join(ROOT, fallback)
end

local function load_snapshot_meta(path)
  local meta = common.parse_yaml_map(path)
  local snapshot_date = coerce_string(meta.snapshot_date)
  assert(snapshot_date:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil, "invalid snapshot_date in " .. path)
  local days = common.date_to_epoch_days(snapshot_date)
  assert(type(days) == "number", "unparseable snapshot_date in " .. path)
  return {
    date = snapshot_date,
    epoch_days = days,
  }
end

local function load_freshness_policy(path)
  local rows = common.parse_yaml_list(path)
  local policy = {}
  for _, row in ipairs(rows) do
    local tier = coerce_string(row.quality_tier)
    if tier ~= "" then
      if row.max_age_days ~= nil and row.max_age_days ~= vim.NIL then
        policy[tier] = tonumber(row.max_age_days)
      else
        policy[tier] = nil
      end
    end
  end
  return policy
end

local function summarize_staleness(evidence, snapshot, freshness_policy)
  local stale_ids = {}
  local by_type = {}

  for _, item in ipairs(evidence) do
    local id = coerce_string(item.id)
    local evidence_type = coerce_string(item.type)
    local tier = coerce_string(item.quality_tier)
    local max_age = freshness_policy[tier]
    local retrieved_at = coerce_string(item.retrieved_at)
    local retrieved_days = common.date_to_epoch_days(retrieved_at)

    local is_stale = false
    if retrieved_days and retrieved_days > snapshot.epoch_days then
      is_stale = true
    elseif
      type(max_age) == "number"
      and retrieved_days
      and snapshot.epoch_days >= retrieved_days
    then
      local age = snapshot.epoch_days - retrieved_days
      if age > max_age then
        is_stale = true
      end
    end

    if is_stale then
      stale_ids[#stale_ids + 1] = id
      by_type[evidence_type] = by_type[evidence_type] or {}
      by_type[evidence_type][#by_type[evidence_type] + 1] = id
    end
  end

  table.sort(stale_ids)
  for _, ids in pairs(by_type) do
    table.sort(ids)
  end

  return {
    count = #stale_ids,
    ids = stale_ids,
    by_type = by_type,
  }
end

local function load_inputs()
  local paths = {
    baselines = resolve_path("WP15_BASELINES_PATH", "data/wp15/baselines.yaml"),
    evidence = resolve_path("WP15_EVIDENCE_PATH", "data/wp15/evidence.jsonl"),
    budgets = resolve_path("WP15_ERROR_BUDGETS_PATH", "data/wp15/error_budgets.json"),
    tests = resolve_path("WP15_TEST_SUMMARY_PATH", "data/wp15/test_snapshot_summary.json"),
    tasks = resolve_path("WP15_AGENT_TASKS_PATH", "data/wp15/agent_workflow_tasks.yaml"),
    gaps = resolve_path("WP15_GAPS_PATH", "data/wp15/gaps.yaml"),
    issues = resolve_path("WP15_ISSUES_SNAPSHOT_PATH", "data/wp15/issues_snapshot.json"),
    snapshot_meta = resolve_path("WP15_SNAPSHOT_META_PATH", "data/wp15/snapshot_meta.yaml"),
    freshness_policy = resolve_path(
      "WP15_FRESHNESS_POLICY_PATH",
      "data/wp15/freshness_policy.yaml"
    ),
    out = resolve_path("WP15_SCORECARD_OUT_PATH", "docs/roadmap/SCORECARD.md"),
  }

  if vim.fn.filereadable(paths.issues) ~= 1 then
    error("missing required issues snapshot: " .. paths.issues)
  end
  if vim.fn.filereadable(paths.tests) ~= 1 then
    error("missing required test summary snapshot: " .. paths.tests)
  end

  local requirements = require("jig.spec.requirements")
  local requirements_ok, requirement_errors = requirements.validate()

  local baselines = common.parse_yaml_list(paths.baselines)
  local evidence = common.parse_jsonl(paths.evidence)
  local budgets = common.parse_json(paths.budgets)
  local tasks = common.parse_yaml_list(paths.tasks)
  local gaps = common.parse_yaml_list(paths.gaps)
  local tests = common.parse_json(paths.tests)
  local issues = common.parse_json(paths.issues)
  local snapshot = load_snapshot_meta(paths.snapshot_meta)
  local freshness_policy = load_freshness_policy(paths.freshness_policy)
  local staleness = summarize_staleness(evidence, snapshot, freshness_policy)

  return {
    paths = paths,
    requirements_ok = requirements_ok,
    requirement_errors = requirement_errors,
    baselines = baselines,
    evidence = evidence,
    budgets = budgets,
    tests = tests,
    tasks = tasks,
    gaps = gaps,
    issues = issues,
    snapshot = snapshot,
    freshness_policy = freshness_policy,
    staleness = staleness,
  }
end

local function baseline_sort(a, b)
  return coerce_string(a.id) < coerce_string(b.id)
end

local function task_sort(a, b)
  return coerce_string(a.id) < coerce_string(b.id)
end

local severity_order = {
  sev0 = 0,
  sev1 = 1,
  sev2 = 2,
  sev3 = 3,
}

local function gap_sort(a, b)
  local left = severity_order[coerce_string(a.severity)] or 99
  local right = severity_order[coerce_string(b.severity)] or 99
  if left ~= right then
    return left < right
  end
  return coerce_string(a.id) < coerce_string(b.id)
end

local function bool_icon(value)
  return value and "pass" or "fail"
end

local function percent(value)
  return string.format("%.2f%%", tonumber(value) or 0)
end

local function classify_latency(value, limit)
  if type(value) ~= "number" or type(limit) ~= "number" then
    return "pending"
  end
  if value > limit then
    return "fail"
  end
  if value >= limit * 0.9 then
    return "near"
  end
  return "pass"
end

local function count_evidence_by_id(evidence)
  local map = {}
  for _, item in ipairs(evidence) do
    local key = coerce_string(item.baseline_id)
    if key ~= "" then
      map[key] = (map[key] or 0) + 1
    end
  end
  return map
end

local function unresolved_high_severity(gaps)
  local out = {}
  for _, gap in ipairs(gaps) do
    local sev = coerce_string(gap.severity)
    local status = coerce_string(gap.status)
    if (sev == "sev0" or sev == "sev1") and status ~= "done" then
      out[#out + 1] = gap
    end
  end
  table.sort(out, gap_sort)
  return out
end

local function non_adoption_rows(gaps)
  local rows = {}
  for _, gap in ipairs(gaps) do
    local rationale = coerce_string(gap.rationale):lower()
    if rationale:find("non%-adoption", 1, false) ~= nil then
      rows[#rows + 1] = gap
    end
  end
  table.sort(rows, gap_sort)
  return rows
end

local function regression_escape_summary(issues, budget_by_lane)
  local by_lane = {}
  local labeled = 0

  for _, issue in ipairs(issues.issues or {}) do
    local labels = issue.labels or {}
    local lane = nil
    local escaped = false
    for _, label in ipairs(labels) do
      local l = tostring(label)
      local captured = l:match("^lane:(.+)$")
      if captured then
        lane = captured
      end
      if l == "regression-escape" or l:match("^escape:") then
        escaped = true
      end
    end

    if lane ~= nil then
      labeled = labeled + 1
      by_lane[lane] = by_lane[lane] or { total = 0, escaped = 0 }
      by_lane[lane].total = by_lane[lane].total + 1
      if escaped then
        by_lane[lane].escaped = by_lane[lane].escaped + 1
      end
    end
  end

  local rows = {}
  local any_data = false
  for lane, target in pairs(budget_by_lane or {}) do
    local bucket = by_lane[lane]
    local observed = nil
    local status = "insufficient-data"
    if bucket and bucket.total > 0 then
      any_data = true
      observed = bucket.escaped / bucket.total
      status = observed <= tonumber(target) and "pass" or "fail"
    end
    rows[#rows + 1] = {
      lane = lane,
      target = tonumber(target) or 0,
      observed = observed,
      status = status,
      sample = bucket and bucket.total or 0,
    }
  end
  table.sort(rows, function(a, b)
    return a.lane < b.lane
  end)

  return {
    rows = rows,
    labeled_issues = labeled,
    has_data = any_data,
  }
end

local function render(data)
  table.sort(data.baselines, baseline_sort)
  table.sort(data.tasks, task_sort)
  table.sort(data.gaps, gap_sort)

  local evidence_count = count_evidence_by_id(data.evidence)
  local unresolved = unresolved_high_severity(data.gaps)
  local non_adopt = non_adoption_rows(data.gaps)

  local startup_info = data.tests.startup or {}
  local startup_ok = as_boolean(startup_info.passed)
  local startup_sample = tonumber(startup_info.sample_size) or 1
  local crash_rate = startup_ok and 100.0 or 0.0
  local crash_target = tonumber(data.budgets.crash_free_startup_target_percent) or 99.0
  local crash_status = crash_rate >= crash_target and "pass" or "fail"
  local startup_rate_min_sample = 30

  local perf_block = data.tests.perf or {}
  local perf_metrics = perf_block.metrics or {}
  local picker = perf_metrics.time_to_first_picker_ms or {}

  local nav_budgets = (data.budgets.p95_latency_budgets or {}).nav or {}
  local nav_rows = {
    {
      command = "JigFiles",
      observed = tonumber(picker.medium and picker.medium.elapsed_ms),
      budget = tonumber(nav_budgets.JigFiles_ms),
    },
    {
      command = "JigSymbols",
      observed = tonumber(picker.large and picker.large.elapsed_ms),
      budget = tonumber(nav_budgets.JigSymbols_ms),
    },
    {
      command = "JigDiagnostics",
      observed = tonumber(perf_metrics.time_to_first_diagnostic_ms),
      budget = tonumber(nav_budgets.JigDiagnostics_ms),
    },
  }
  for _, row in ipairs(nav_rows) do
    row.status = classify_latency(row.observed, row.budget)
  end

  local regression = regression_escape_summary(
    data.issues,
    data.budgets.regression_escape_rate_target_per_lane or {}
  )

  local discoverability = data.tests.discoverability or {}
  local security = data.tests.security or {}
  local platform_ok = as_boolean((data.tests.platform or {}).passed)

  local lines = {
    "# SCORECARD",
    "",
    "Generated deterministically from committed WP-15 artifacts.",
    "",
    string.format(
      "This scorecard is an offline snapshot as of `%s`.",
      coerce_string(data.snapshot.date)
    ),
    "",
    "Inputs:",
    "- `data/wp15/baselines.yaml`",
    "- `data/wp15/evidence.jsonl`",
    "- `data/wp15/error_budgets.json`",
    "- `data/wp15/test_snapshot_summary.json`",
    "- `data/wp15/agent_workflow_tasks.yaml`",
    "- `data/wp15/gaps.yaml`",
    "- `data/wp15/issues_snapshot.json`",
    "- `data/wp15/snapshot_meta.yaml`",
    "- `data/wp15/freshness_policy.yaml`",
    "",
    string.format("Issue snapshot retrieved at: `%s`", coerce_string(data.issues.retrieved_at)),
    string.format("Test summary retrieved at: `%s`", coerce_string(data.tests.retrieved_at)),
    "",
    "## Baseline set (pinned)",
    "",
    "| ID | Name | Category | Pinned version | Qualitative only | Evidence items |",
    "|---|---|---|---|---:|---:|",
  }

  for _, baseline in ipairs(data.baselines) do
    lines[#lines + 1] = string.format(
      "| `%s` | %s | `%s` | `%s` | %s | %d |",
      coerce_string(baseline.id),
      coerce_string(baseline.name),
      coerce_string(baseline.category),
      coerce_string(baseline.pinned_version),
      baseline.qualitative_only == true and "yes" or "no",
      evidence_count[coerce_string(baseline.id)] or 0
    )
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Universal Spec conformance"
  lines[#lines + 1] = ""
  lines[#lines + 1] = string.format(
    "- Jig contract registry validation: **%s**",
    data.requirements_ok and "pass" or "fail"
  )
  lines[#lines + 1] =
    string.format("- Startup smoke (default profile): **%s**", bool_icon(startup_ok))
  lines[#lines + 1] =
    string.format("- Startup evidence source: `%s`", coerce_string(startup_info.source))
  lines[#lines + 1] =
    "- Baseline conformance is qualitative-only from evidence register; no numeric baseline score is claimed."
  if not data.requirements_ok then
    lines[#lines + 1] = "- Requirement validation errors:"
    for _, err in ipairs(data.requirement_errors or {}) do
      lines[#lines + 1] = string.format("  - %s", coerce_string(err))
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Reliability metrics"
  lines[#lines + 1] = ""
  if startup_sample < startup_rate_min_sample then
    lines[#lines + 1] = string.format(
      "- Startup smoke check: **%s** (sample size: `%d`; crash-free rate reporting begins at sample size >= `%d`)",
      bool_icon(startup_ok),
      startup_sample,
      startup_rate_min_sample
    )
    lines[#lines + 1] = "- Crash-free startup rate: `insufficient-data`"
  else
    lines[#lines + 1] = string.format(
      "- Crash-free startup rate: `%s` (target `%s`) -> **%s** (sample size: `%d`)",
      percent(crash_rate),
      percent(crash_target),
      crash_status,
      startup_sample
    )
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "### Regression escape rate per lane"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "| Lane | Target | Observed | Sample | Status |"
  lines[#lines + 1] = "|---|---:|---:|---:|---|"
  for _, row in ipairs(regression.rows) do
    local observed = row.observed and percent(row.observed * 100) or "n/a"
    lines[#lines + 1] = string.format(
      "| `%s` | `%s` | `%s` | `%d` | %s |",
      row.lane,
      percent(row.target * 100),
      observed,
      row.sample,
      row.status
    )
  end
  if not regression.has_data then
    lines[#lines + 1] = ""
    lines[#lines + 1] =
      "- Boundary: issue snapshot currently has no lane labels; regression escape rate is tracked as insufficient data."
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "### P95 latency budgets"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "| Surface | Probe | Observed ms | Budget ms | Status |"
  lines[#lines + 1] = "|---|---|---:|---:|---|"
  for _, row in ipairs(nav_rows) do
    lines[#lines + 1] = string.format(
      "| navigation | `%s` | `%s` | `%s` | %s |",
      row.command,
      row.observed and tostring(row.observed) or "n/a",
      row.budget and tostring(row.budget) or "n/a",
      row.status
    )
  end
  local agent_ui = (data.budgets.p95_latency_budgets or {}).agent_ui or {}
  for _, name in ipairs(common.sorted_keys(agent_ui)) do
    local config = agent_ui[name]
    if type(config) == "table" and config.status == "pending" then
      lines[#lines + 1] = string.format(
        "| agent_ui | `%s` | `n/a` | `n/a` | pending (%s) |",
        name,
        coerce_string(config.blocking_wp)
      )
    else
      lines[#lines + 1] = string.format(
        "| agent_ui | `%s` | `%s` | `%s` | %s |",
        name,
        "n/a",
        tostring(config),
        "pending"
      )
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Snapshot semantics"
  lines[#lines + 1] = ""
  lines[#lines + 1] = string.format("- Snapshot date: `%s`", coerce_string(data.snapshot.date))
  lines[#lines + 1] =
    "- Refreshing `snapshot_date` without refreshing evidence metadata is invalid and should fail research gates."
  lines[#lines + 1] = ""
  lines[#lines + 1] = "### Stale evidence by type"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "| Evidence type | Stale count | Stale ids |"
  lines[#lines + 1] = "|---|---:|---|"
  if data.staleness.count == 0 then
    lines[#lines + 1] = "| `none` | `0` | - |"
  else
    local types = common.sorted_keys(data.staleness.by_type or {})
    for _, evidence_type in ipairs(types) do
      local ids = data.staleness.by_type[evidence_type] or {}
      lines[#lines + 1] =
        string.format("| `%s` | `%d` | `%s` |", evidence_type, #ids, table.concat(ids, ", "))
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Discoverability metrics"
  lines[#lines + 1] = ""
  lines[#lines + 1] = string.format(
    "- Command-to-doc cross-reference gate: **%s**",
    bool_icon(as_boolean(discoverability.command_doc_cross_reference))
  )
  lines[#lines + 1] = string.format(
    "- Keymap docs sync gate: **%s**",
    bool_icon(as_boolean(discoverability.keymap_docs_sync))
  )
  lines[#lines + 1] = string.format(
    "- Help entrypoint health (`:help jig`): **%s**",
    bool_icon(as_boolean(discoverability.help_entrypoint))
  )

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Security controls"
  lines[#lines + 1] = ""
  lines[#lines + 1] = string.format(
    "- Startup network trace clean: **%s**",
    bool_icon(as_boolean(security.startup_network_trace_clean))
  )
  lines[#lines + 1] = string.format(
    "- MCP trust enforcement: **%s**",
    bool_icon(as_boolean(security.mcp_trust_enforcement))
  )
  lines[#lines + 1] = string.format(
    "- Exec safety override logging: **%s**",
    bool_icon(as_boolean(security.exec_safety_override_logging))
  )

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Platform consistency"
  lines[#lines + 1] = ""
  lines[#lines + 1] = string.format("- Platform harness summary: **%s**", bool_icon(platform_ok))
  lines[#lines + 1] = "- WSL remains best-effort in hosted CI per WP-11 constraints."

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Agent workflow comparative gates"
  lines[#lines + 1] = ""
  lines[#lines + 1] =
    "| Task ID | Status | Blocking WP | Failure surfaces | Success criteria | Oracle |"
  lines[#lines + 1] = "|---|---|---|---|---|---|"
  for _, task in ipairs(data.tasks) do
    local surfaces = coerce_string(task.failure_surfaces)
    if type(task.failure_surfaces) == "table" then
      surfaces = table.concat(task.failure_surfaces, ", ")
    end
    lines[#lines + 1] = string.format(
      "| `%s` | `%s` | `%s` | `%s` | %s | `%s` |",
      coerce_string(task.id),
      coerce_string(task.current_status),
      coerce_string(task.blocking_wp),
      surfaces,
      coerce_string(task.success_criteria),
      coerce_string(task.test_oracle)
    )
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Gap register summary"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "| Gap | Severity | Surface | Owner | Status | Test plan |"
  lines[#lines + 1] = "|---|---|---|---|---|---|"
  for _, gap in ipairs(data.gaps) do
    lines[#lines + 1] = string.format(
      "| `%s` | `%s` | `%s` | `%s` | `%s` | %s |",
      coerce_string(gap.id),
      coerce_string(gap.severity),
      coerce_string(gap.failure_surface),
      coerce_string(gap.owner),
      coerce_string(gap.status),
      coerce_string(gap.test_plan)
    )
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] =
    string.format("Unresolved high-severity gaps (`sev0/sev1` and not done): **%d**", #unresolved)
  for _, gap in ipairs(unresolved) do
    lines[#lines + 1] = string.format(
      "- `%s` -> owner `%s`, issue: %s",
      coerce_string(gap.id),
      coerce_string(gap.owner),
      coerce_string(gap.related_issue)
    )
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Explicit non-adoption rationale"
  lines[#lines + 1] = ""
  if #non_adopt == 0 then
    lines[#lines + 1] = "- None recorded."
  else
    for _, gap in ipairs(non_adopt) do
      lines[#lines + 1] =
        string.format("- `%s`: %s", coerce_string(gap.id), coerce_string(gap.rationale))
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Interpretation and Fair Use"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "- This scorecard is not a ranking or leaderboard."
  lines[#lines + 1] =
    "- Baselines are pinned snapshots for reproducibility at retrieval time, not universal tool judgments."
  lines[#lines + 1] =
    "- Evidence is curated and fallible; corrections and counter-evidence should be submitted through PRs."
  lines[#lines + 1] =
    "- Any metric with insufficient sample size must be interpreted as `insufficient-data`, not as proof of advantage."

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Boundaries"
  lines[#lines + 1] = ""
  lines[#lines + 1] =
    "- Quantitative baseline comparisons are limited to pinned, reproducible artifacts."
  lines[#lines + 1] = "- Baselines marked `qualitative_only` are excluded from numeric scoring."
  lines[#lines + 1] =
    "- Agent transactional edit workflow remains pending until WP-17; current scorecard reports this as open high-severity gaps."
  lines[#lines + 1] = ""

  return table.concat(lines, "\n")
end

local function main()
  local data = load_inputs()
  local markdown = render(data)
  common.write_text(data.paths.out, markdown)
  print("wp15 scorecard generated: " .. data.paths.out)
  vim.cmd("qa")
end

local ok, err = pcall(main)
if not ok then
  vim.api.nvim_err_writeln("wp15 scorecard generation failed: " .. tostring(err))
  vim.cmd("cquit 1")
end
