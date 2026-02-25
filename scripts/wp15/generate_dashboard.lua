#!/usr/bin/env -S nvim --headless -u NONE -l

local source = debug.getinfo(1, "S").source:sub(2)
local script_dir = vim.fn.fnamemodify(source, ":p:h")
local common = dofile(script_dir .. "/common.lua")

local ROOT = common.repo_root()

local function coerce_string(value)
  if value == vim.NIL then
    return ""
  end
  return tostring(value or "")
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

local function increment(map, key)
  if key == nil or key == "" then
    return
  end
  map[key] = (map[key] or 0) + 1
end

local function to_ordered_pairs(map)
  local keys = common.sorted_keys(map)
  local out = {}
  for _, key in ipairs(keys) do
    out[#out + 1] = { key = key, value = map[key] }
  end
  return out
end

local function surface_for_suite_case(suite, case_id)
  local joined = string.format("%s:%s", coerce_string(suite), coerce_string(case_id)):lower()
  if joined:find("cmdline", 1, true) then
    return "cmdline"
  end

  local map = {
    startup = "startup",
    completion = "completion",
    lsp = "lsp",
    ui = "ui",
    perf = "performance",
    platform = "platform",
    nav = "integration",
    tools = "integration",
    docs = "docs",
    security = "security",
    agent = "agent",
    keymaps = "ui",
    ops = "ops",
    pending = "agent",
  }
  return map[coerce_string(suite)] or "unknown"
end

local function perf_summary(perf)
  local metrics = perf.metrics or {}
  local budgets = perf.budgets or {}
  local picker = metrics.time_to_first_picker_ms or {}
  local picker_limits = budgets.picker_first_ms or {}

  local rows = {
    {
      name = "time-to-first-diagnostic",
      value = tonumber(metrics.time_to_first_diagnostic_ms),
      limit = tonumber(budgets.diagnostic_first_ms),
    },
    {
      name = "time-to-first-completion-menu",
      value = tonumber(metrics.time_to_first_completion_ms),
      limit = tonumber(budgets.completion_first_ms),
    },
    {
      name = "time-to-first-picker-small",
      value = tonumber(picker.small and picker.small.elapsed_ms),
      limit = tonumber(picker_limits.small),
    },
    {
      name = "time-to-first-picker-medium",
      value = tonumber(picker.medium and picker.medium.elapsed_ms),
      limit = tonumber(picker_limits.medium),
    },
    {
      name = "time-to-first-picker-large",
      value = tonumber(picker.large and picker.large.elapsed_ms),
      limit = tonumber(picker_limits.large),
    },
  }

  local counts = {
    pass = 0,
    near = 0,
    fail = 0,
    pending = 0,
  }

  for _, row in ipairs(rows) do
    row.status = classify_latency(row.value, row.limit)
    counts[row.status] = (counts[row.status] or 0) + 1
  end

  return rows, counts
end

local function load_inputs()
  local paths = {
    quarantine = common.join(ROOT, "tests/quarantine.json"),
    pending = common.join(ROOT, "tests/pending_tests.json"),
    tests = common.join(ROOT, "data/wp15/test_snapshot_summary.json"),
    gaps = common.join(ROOT, "data/wp15/gaps.yaml"),
    issues = common.join(ROOT, "data/wp15/issues_snapshot.json"),
    dashboard_json = common.join(ROOT, "data/wp15/dashboard_snapshot.json"),
    dashboard_md = common.join(ROOT, "docs/roadmap/REGRESSION_DASHBOARD.md"),
  }

  if vim.fn.filereadable(paths.issues) ~= 1 then
    error("missing required issues snapshot: " .. paths.issues)
  end
  if vim.fn.filereadable(paths.tests) ~= 1 then
    error("missing required test summary snapshot: " .. paths.tests)
  end

  return {
    paths = paths,
    quarantine = common.parse_json(paths.quarantine),
    pending = common.parse_json(paths.pending),
    tests = common.parse_json(paths.tests),
    gaps = common.parse_yaml_list(paths.gaps),
    issues = common.parse_json(paths.issues),
  }
end

local function build_snapshot(data)
  local quarantine_by_surface = {}
  for key, _ in pairs((data.quarantine.timing_sensitive_allowlist or {})) do
    local suite, case_id = tostring(key):match("^([^:]+):(.+)$")
    local surface = surface_for_suite_case(suite or "", case_id or "")
    increment(quarantine_by_surface, surface)
  end

  local pending_by_surface = {}
  for key, _ in pairs((data.pending.allowed_pending or {})) do
    local suite, case_id = tostring(key):match("^([^:]+):(.+)$")
    local surface = surface_for_suite_case(suite or "", case_id or "")
    increment(pending_by_surface, surface)
  end

  local open_gaps_by_surface = {}
  for _, gap in ipairs(data.gaps) do
    local status = coerce_string(gap.status)
    if status ~= "done" then
      increment(open_gaps_by_surface, coerce_string(gap.failure_surface))
    end
  end

  local perf_rows, perf_counts = perf_summary((data.tests or {}).perf or {})

  local label_counts = {}
  local severity_counts = {
    sev0 = 0,
    sev1 = 0,
    sev2 = 0,
    sev3 = 0,
  }
  for _, issue in ipairs(data.issues.issues or {}) do
    for _, label in ipairs(issue.labels or {}) do
      local l = tostring(label)
      increment(label_counts, l)
      if severity_counts[l] ~= nil then
        severity_counts[l] = severity_counts[l] + 1
      end
    end
  end

  local snapshot = {
    schema = "wp15-dashboard-v1",
    repo = coerce_string(data.issues.repo),
    source_retrieved_at = coerce_string(data.issues.retrieved_at),
    series = {
      {
        id = coerce_string(data.issues.retrieved_at),
        quarantine_by_surface = quarantine_by_surface,
        pending_by_surface = pending_by_surface,
        perf_budget_status = {
          counts = perf_counts,
          probes = perf_rows,
        },
        open_gaps_by_surface = open_gaps_by_surface,
        issue_label_counts = label_counts,
        severity_label_counts = severity_counts,
      },
    },
  }

  return snapshot
end

local function render_markdown(snapshot)
  local point = snapshot.series[1] or {}
  local lines = {
    "# REGRESSION_DASHBOARD",
    "",
    "Generated deterministically from committed artifacts.",
    "",
    string.format("- Source issues snapshot: `%s`", coerce_string(snapshot.source_retrieved_at)),
    "",
    "## Quarantine entries by failure surface",
    "",
    "| Surface | Count |",
    "|---|---:|",
  }

  for _, pair in ipairs(to_ordered_pairs(point.quarantine_by_surface or {})) do
    lines[#lines + 1] = string.format("| `%s` | `%d` |", pair.key, pair.value)
  end
  if next(point.quarantine_by_surface or {}) == nil then
    lines[#lines + 1] = "| `none` | `0` |"
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Pending tests by failure surface"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "| Surface | Count |"
  lines[#lines + 1] = "|---|---:|"
  for _, pair in ipairs(to_ordered_pairs(point.pending_by_surface or {})) do
    lines[#lines + 1] = string.format("| `%s` | `%d` |", pair.key, pair.value)
  end
  if next(point.pending_by_surface or {}) == nil then
    lines[#lines + 1] = "| `none` | `0` |"
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Perf budget status"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "| Probe | Observed ms | Budget ms | Status |"
  lines[#lines + 1] = "|---|---:|---:|---|"
  for _, probe in ipairs((point.perf_budget_status or {}).probes or {}) do
    lines[#lines + 1] = string.format(
      "| `%s` | `%s` | `%s` | %s |",
      coerce_string(probe.name),
      probe.value and tostring(probe.value) or "n/a",
      probe.limit and tostring(probe.limit) or "n/a",
      coerce_string(probe.status)
    )
  end

  lines[#lines + 1] = ""
  local perf_counts = (point.perf_budget_status or {}).counts or {}
  lines[#lines + 1] = string.format(
    "- Summary: pass=`%d`, near=`%d`, fail=`%d`, pending=`%d`",
    tonumber(perf_counts.pass) or 0,
    tonumber(perf_counts.near) or 0,
    tonumber(perf_counts.fail) or 0,
    tonumber(perf_counts.pending) or 0
  )

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Open gaps by failure surface"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "| Surface | Open gaps |"
  lines[#lines + 1] = "|---|---:|"
  for _, pair in ipairs(to_ordered_pairs(point.open_gaps_by_surface or {})) do
    lines[#lines + 1] = string.format("| `%s` | `%d` |", pair.key, pair.value)
  end
  if next(point.open_gaps_by_surface or {}) == nil then
    lines[#lines + 1] = "| `none` | `0` |"
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Issue labels snapshot"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "| Label | Count |"
  lines[#lines + 1] = "|---|---:|"
  for _, pair in ipairs(to_ordered_pairs(point.issue_label_counts or {})) do
    lines[#lines + 1] = string.format("| `%s` | `%d` |", pair.key, pair.value)
  end
  if next(point.issue_label_counts or {}) == nil then
    lines[#lines + 1] = "| `none` | `0` |"
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Boundaries"
  lines[#lines + 1] = ""
  lines[#lines + 1] =
    "- Trend history is append-based: keep prior snapshots in `data/wp15/dashboard_snapshot.json` when adopting periodic updates."
  lines[#lines + 1] =
    "- Label-driven metrics require consistent issue labeling discipline; low label density reduces interpretability."
  lines[#lines + 1] = ""

  return table.concat(lines, "\n")
end

local function encode_json_sorted(value)
  if value == vim.NIL then
    return "null"
  end

  local value_type = type(value)
  if value_type ~= "table" then
    return vim.json.encode(value)
  end

  if vim.islist(value) then
    local parts = {}
    for _, item in ipairs(value) do
      parts[#parts + 1] = encode_json_sorted(item)
    end
    return "[" .. table.concat(parts, ",") .. "]"
  end

  local parts = {}
  for _, key in ipairs(common.sorted_keys(value)) do
    parts[#parts + 1] = string.format("%s:%s", vim.json.encode(key), encode_json_sorted(value[key]))
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function write_json(path, payload)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ encode_json_sorted(payload) }, path)
end

local function main()
  local data = load_inputs()
  local snapshot = build_snapshot(data)
  local markdown = render_markdown(snapshot)

  write_json(data.paths.dashboard_json, snapshot)
  common.write_text(data.paths.dashboard_md, markdown)

  print("wp15 dashboard generated: " .. data.paths.dashboard_md)
  print("wp15 dashboard snapshot generated: " .. data.paths.dashboard_json)
  vim.cmd("qa")
end

local ok, err = pcall(main)
if not ok then
  vim.api.nvim_err_writeln("wp15 dashboard generation failed: " .. tostring(err))
  vim.cmd("cquit 1")
end
