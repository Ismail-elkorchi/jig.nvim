local M = {}

local function includes(list, needle)
  if type(list) ~= "table" then
    return false
  end
  for _, item in ipairs(list) do
    if item == needle then
      return true
    end
  end
  return false
end

function M.snapshot_path(opts, fallback)
  if opts and type(opts.snapshot_path) == "string" and opts.snapshot_path ~= "" then
    return opts.snapshot_path
  end
  return fallback
end

function M.write_snapshot(path, payload)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(payload) }, path)
end

function M.load_json(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end

  local lines = vim.fn.readfile(path)
  local ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok or type(decoded) ~= "table" then
    return nil
  end

  return decoded
end

function M.retry_count(case, defaults)
  local labels = case.labels or {}
  if tonumber(case.retries) then
    return math.max(1, math.floor(tonumber(case.retries)))
  end

  if includes(labels, "timing-sensitive") then
    local value = tonumber(defaults and defaults.timing_sensitive_retries) or 3
    return math.max(2, math.floor(value))
  end

  return 1
end

function M.retry_delay_ms(case, defaults)
  if tonumber(case.retry_delay_ms) then
    return math.max(0, math.floor(tonumber(case.retry_delay_ms)))
  end

  if includes(case.labels or {}, "timing-sensitive") then
    return math.max(0, math.floor(tonumber(defaults and defaults.timing_sensitive_delay_ms) or 80))
  end

  return 0
end

local function run_case(case, defaults)
  if case.pending == true then
    return {
      ok = true,
      status = "pending",
      attempts = 0,
      labels = case.labels or {},
      reason = tostring(case.pending_reason or "pending"),
      details = {
        pending = true,
      },
    }
  end

  local attempts = M.retry_count(case, defaults)
  local retry_delay_ms = M.retry_delay_ms(case, defaults)

  local last_details = {}
  for attempt = 1, attempts do
    local ok, passed, details = pcall(case.run)
    if ok and passed then
      return {
        ok = true,
        status = "passed",
        attempts = attempt,
        labels = case.labels or {},
        retry_delay_ms = retry_delay_ms,
        details = details or {},
      }
    end

    last_details = details or { error = passed }
    if attempt < attempts and retry_delay_ms > 0 then
      vim.wait(retry_delay_ms)
    end
  end

  return {
    ok = false,
    status = "failed",
    attempts = attempts,
    labels = case.labels or {},
    retry_delay_ms = retry_delay_ms,
    details = last_details,
  }
end

function M.run_cases(cases, opts)
  opts = opts or {}
  local report = {
    harness = tostring(opts.harness or "headless-child-harness"),
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    cases = {},
  }

  local failed = {}
  local pending = {}

  for _, case in ipairs(cases) do
    local result = run_case(case, opts.retry_defaults)
    report.cases[case.id] = {
      ok = result.ok,
      status = result.status,
      labels = result.labels,
      attempts = result.attempts,
      retry_delay_ms = result.retry_delay_ms,
      pending_reason = result.reason,
      details = result.details,
    }

    if result.status == "failed" then
      failed[#failed + 1] = case.id
    elseif result.status == "pending" then
      pending[#pending + 1] = case.id
    end
  end

  report.summary = {
    passed = #failed == 0,
    failed_cases = failed,
    pending_cases = pending,
    failed_count = #failed,
    pending_count = #pending,
  }

  return report
end

function M.finalize(report, opts)
  opts = opts or {}
  M.write_snapshot(opts.snapshot_path, report)

  if report.summary.failed_count > 0 then
    error(
      string.format(
        "%s failed: %s",
        tostring(opts.fail_label or "harness"),
        table.concat(report.summary.failed_cases, ", ")
      )
    )
  end

  if opts.fail_on_pending == true and report.summary.pending_count > 0 then
    error(
      string.format(
        "%s contains pending tests: %s",
        tostring(opts.fail_label or "harness"),
        table.concat(report.summary.pending_cases, ", ")
      )
    )
  end
end

function M.repo_root(depth)
  if type(_G.__jig_repo_root) == "string" and _G.__jig_repo_root ~= "" then
    return _G.__jig_repo_root
  end
  local source = debug.getinfo(1, "S").source:sub(2)
  local hops = depth or 2
  local modifier = ":p"
  for _ = 1, hops do
    modifier = modifier .. ":h"
  end
  return vim.fn.fnamemodify(source, modifier)
end

return M
