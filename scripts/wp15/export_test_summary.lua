#!/usr/bin/env -S nvim --headless -u NONE -l

local source = debug.getinfo(1, "S").source:sub(2)
local script_dir = vim.fn.fnamemodify(source, ":p:h")
local common = dofile(script_dir .. "/common.lua")

local ROOT = common.repo_root()

local function read_json(path)
  return common.parse_json(path)
end

local function case_ok(snapshot, case_id)
  local cases = snapshot.cases or {}
  local row = cases[case_id] or {}
  return row.ok == true
end

local function startup_probe()
  local result = vim
    .system({
      "nvim",
      "--headless",
      "-u",
      "NONE",
      "-l",
      "tests/run_harness.lua",
      "--",
      "--suite",
      "startup",
    }, {
      cwd = ROOT,
      text = true,
    })
    :wait(60000)

  if result == nil then
    return {
      passed = false,
      sample_size = 1,
      source = "startup-suite-smoke",
      reason = "wait_nil",
    }
  end

  return {
    passed = result.code == 0,
    sample_size = 1,
    source = "startup-suite-smoke",
    reason = result.code == 0 and "startup_suite_passed" or "startup_suite_failed",
  }
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

local function main()
  local perf = read_json(common.join(ROOT, "tests/perf/snapshots/latest-headless.json"))
  local docs = read_json(common.join(ROOT, "tests/docs/snapshots/latest-headless.json"))
  local keymaps = read_json(common.join(ROOT, "tests/keymaps/snapshots/latest-headless.json"))
  local security = read_json(common.join(ROOT, "tests/security/snapshots/latest-headless.json"))
  local platform = read_json(common.join(ROOT, "tests/platform/snapshots/latest-headless.json"))
  local startup = startup_probe()

  local summary = {
    retrieved_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    startup = startup,
    perf = {
      metrics = perf.metrics,
      budgets = perf.budgets,
    },
    discoverability = {
      command_doc_cross_reference = case_ok(docs, "command-doc-cross-reference"),
      keymap_docs_sync = case_ok(keymaps, "docs-sync-gate"),
      help_entrypoint = case_ok(docs, "help-entrypoint"),
    },
    security = {
      startup_network_trace_clean = case_ok(security, "startup-network-trace-clean"),
      mcp_trust_enforcement = case_ok(security, "mcp-trust-enforcement"),
      exec_safety_override_logging = case_ok(security, "exec-safety-override-logging"),
    },
    platform = {
      passed = platform.summary and platform.summary.passed == true,
      notes = "WSL remains best-effort in hosted CI per WP-11.",
    },
  }

  local out = common.join(ROOT, "data/wp15/test_snapshot_summary.json")
  vim.fn.mkdir(vim.fn.fnamemodify(out, ":h"), "p")
  vim.fn.writefile({ encode_json_sorted(summary) }, out)
  print("wp15 test summary exported: " .. out)
  vim.cmd("qa")
end

local ok, err = pcall(main)
if not ok then
  vim.api.nvim_err_writeln("wp15 test summary export failed: " .. tostring(err))
  vim.cmd("cquit 1")
end
