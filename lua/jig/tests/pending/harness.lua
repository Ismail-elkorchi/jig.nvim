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
  return fabric.snapshot_path(opts, vim.fn.stdpath("state") .. "/jig/pending-harness-snapshot.json")
end

local function allowlist_path()
  return repo_root() .. "/tests/pending_tests.json"
end

local function load_allowlist()
  local payload = fabric.load_json(allowlist_path()) or {}
  local allowed = payload.allowed_pending or {}
  if vim.islist(allowed) then
    local map = {}
    for _, id in ipairs(allowed) do
      map[tostring(id)] = ""
    end
    return map
  end
  if type(allowed) == "table" then
    return allowed
  end
  return {}
end

local function has_feature(command_name, module_name)
  if
    type(command_name) == "string"
    and command_name ~= ""
    and vim.fn.exists(":" .. command_name) == 2
  then
    return true
  end
  if type(module_name) == "string" and module_name ~= "" then
    local ok = pcall(require, module_name)
    if ok then
      return true
    end
  end
  return false
end

local probes = {
  {
    id = "agent:approval-notification-visible",
    labels = { "future-work" },
    pending_reason = "WP-17 approval queue UI not implemented",
    implemented = function()
      return has_feature("JigAgentApprovals", "jig.agent.approvals")
    end,
  },
  {
    id = "agent:patch-diff-hunk-apply",
    labels = { "future-work" },
    pending_reason = "WP-17 transactional patch/diff pipeline not implemented",
    implemented = function()
      return has_feature("JigPatchReview", "jig.agent.patch")
    end,
  },
}

function M.run(opts)
  local allowlist = load_allowlist()

  local report = {
    harness = "headless-child-pending",
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    cases = {},
  }

  local pending = {}
  for _, probe in ipairs(probes) do
    local implemented = probe.implemented()
    local status = implemented and "implemented" or "pending"

    if not implemented then
      assert(allowlist[probe.id] ~= nil, "pending test not in allowlist: " .. probe.id)
      pending[#pending + 1] = probe.id
    end

    report.cases[probe.id] = {
      ok = true,
      status = status,
      labels = probe.labels,
      pending_reason = implemented and "" or probe.pending_reason,
      details = {
        implemented = implemented,
      },
    }
  end

  local pending_set = {}
  for _, id in ipairs(pending) do
    pending_set[id] = true
  end
  for id, _ in pairs(allowlist) do
    assert(pending_set[id] == true, "stale pending allowlist entry: " .. id)
  end

  table.sort(pending)
  report.summary = {
    passed = true,
    failed_cases = {},
    pending_cases = pending,
    failed_count = 0,
    pending_count = #pending,
  }

  local path = snapshot_path(opts)
  fabric.write_snapshot(path, report)
  print("pending-harness snapshot written: " .. path)
end

return M
