local approvals = require("jig.agent.approvals")
local config = require("jig.agent.config")
local log = require("jig.agent.log")
local state = require("jig.agent.state")

local M = {}

local valid_decision = {
  allow = true,
  ask = true,
  deny = true,
}

local valid_scope = {
  global = true,
  project = true,
  task = true,
}

local function policy_file()
  local cfg = config.get()
  return cfg.policy.persistence_file
end

local function default_store()
  return {
    version = 1,
    next_id = 1,
    rules = {},
  }
end

local function load_store()
  local payload = state.read_json(policy_file(), default_store())
  if type(payload.rules) ~= "table" then
    payload.rules = {}
  end
  if type(payload.next_id) ~= "number" then
    payload.next_id = 1
  end
  return payload
end

local function save_store(store)
  return state.write_json(policy_file(), store)
end

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function normalize_path(path)
  return config.normalize_path(path)
end

local function task_ancestors(task_id)
  if type(task_id) ~= "string" or task_id == "" then
    return {}
  end

  local ok, task = pcall(require, "jig.agent.task")
  if not ok or type(task.ancestors) ~= "function" then
    return {}
  end

  local ok_ancestors, ancestors = pcall(task.ancestors, task_id)
  if not ok_ancestors or type(ancestors) ~= "table" then
    return {}
  end

  return ancestors
end

local function normalize_subject(subject)
  subject = subject or {}
  local cfg = config.get()
  local action_class = tostring(subject.action_class or "unknown")
  if action_class == "" then
    action_class = "unknown"
  end

  local destructive = cfg.policy.destructive_classes[action_class] == true
  local project_root = normalize_path(subject.project_root or cfg.root)
  local task_id = subject.task_id

  local ancestors = {}
  if type(subject.ancestor_task_ids) == "table" then
    for _, item in ipairs(subject.ancestor_task_ids) do
      if type(item) == "string" and item ~= "" then
        table.insert(ancestors, item)
      end
    end
  else
    ancestors = task_ancestors(task_id)
  end

  return {
    tool = tostring(subject.tool or ""),
    action_class = action_class,
    target = tostring(subject.target or "*"),
    project_root = project_root,
    task_id = type(task_id) == "string" and task_id or nil,
    ancestor_task_ids = ancestors,
    destructive = destructive,
  }
end

local function field_match(rule_value, subject_value)
  if rule_value == nil or rule_value == "*" or rule_value == "" then
    return true
  end
  return tostring(rule_value) == tostring(subject_value)
end

local function scope_match(rule, subject)
  if rule.scope == "global" then
    return true
  end

  if rule.scope == "project" then
    if type(rule.project_root) ~= "string" or rule.project_root == "" then
      return false
    end
    return normalize_path(rule.project_root) == subject.project_root
  end

  if rule.scope == "task" then
    if type(rule.task_id) ~= "string" or rule.task_id == "" then
      return false
    end

    if subject.task_id == rule.task_id then
      return true
    end

    if rule.inherit ~= false then
      for _, ancestor in ipairs(subject.ancestor_task_ids or {}) do
        if ancestor == rule.task_id then
          return true
        end
      end
    end
  end

  return false
end

local function specificity(rule)
  local score = 0
  if rule.scope == "task" then
    score = score + 30
  elseif rule.scope == "project" then
    score = score + 20
  else
    score = score + 10
  end

  if rule.tool and rule.tool ~= "*" and rule.tool ~= "" then
    score = score + 3
  end
  if rule.action_class and rule.action_class ~= "*" and rule.action_class ~= "" then
    score = score + 3
  end
  if rule.target and rule.target ~= "*" and rule.target ~= "" then
    score = score + 3
  end

  return score
end

local function pick_rule(rules, decision)
  local best = nil
  local best_score = -1

  for _, rule in ipairs(rules) do
    if rule.decision == decision then
      local score = specificity(rule)
      if score > best_score then
        best = rule
        best_score = score
      end
    end
  end

  return best
end

local function matching_rules(subject)
  local store = load_store()
  local out = {}

  for _, rule in ipairs(store.rules) do
    local matches = scope_match(rule, subject)
      and field_match(rule.tool, subject.tool)
      and field_match(rule.action_class, subject.action_class)
      and field_match(rule.target, subject.target)

    if matches then
      table.insert(out, rule)
    end
  end

  return out
end

local function default_decision(action_class)
  local cfg = config.get()
  local map = cfg.policy.default_decisions or {}
  return map[action_class] or map.unknown or "ask"
end

local function build_hint(report)
  if report.decision == "allow" then
    return "allowed"
  end

  if report.decision == "deny" then
    return "Denied by policy. Use :JigAgentPolicyList and :JigAgentPolicyRevoke if needed."
  end

  return "Approval required. Use :JigAgentPolicyGrant allow <tool> <action_class> <target> <scope> [scope_value]."
end

function M.evaluate(subject)
  local normalized = normalize_subject(subject)
  if approvals.consume_once_allowance(normalized) then
    local report = {
      allowed = true,
      decision = "allow",
      rule = nil,
      source = "approval_once",
      subject = normalized,
      destructive = normalized.destructive,
      hint = "allowed (once)",
    }
    return report
  end

  local matches = matching_rules(normalized)

  local rule = pick_rule(matches, "deny")
    or pick_rule(matches, "ask")
    or pick_rule(matches, "allow")

  local decision = rule and rule.decision or default_decision(normalized.action_class)
  local allowed = decision == "allow"

  local report = {
    allowed = allowed,
    decision = decision,
    rule = rule,
    source = rule and "rule" or "default",
    subject = normalized,
    destructive = normalized.destructive,
  }
  report.hint = build_hint(report)
  return report
end

function M.authorize(subject, opts)
  opts = opts or {}
  local report = M.evaluate(subject)

  if report.decision == "ask" and opts.queue ~= false then
    local pending, _ = approvals.enqueue(report.subject, {
      decision = report.decision,
      reason = tostring(opts.reason or "policy_ask"),
      hint = report.hint,
      origin = tostring(opts.origin or "policy"),
      summary = tostring(opts.summary or ""),
      notify = opts.notify ~= false,
    })
    report.pending = pending
    report.pending_id = pending and pending.id or nil
  end

  if opts.log ~= false then
    local policy_source = report.source or (report.rule and "rule" or "default")
    log.record({
      event = "policy_decision",
      task_id = report.subject.task_id,
      tool = report.subject.tool,
      request = {
        action_class = report.subject.action_class,
        target = report.subject.target,
      },
      policy_decision = report.decision,
      result = {
        allowed = report.allowed,
        source = policy_source,
      },
      error_path = report.allowed and "" or report.hint,
    })
  end

  return report
end

function M.grant(spec)
  spec = spec or {}
  local decision = tostring(spec.decision or "")
  if not valid_decision[decision] then
    return false, "invalid decision: " .. decision
  end

  local scope = tostring(spec.scope or "global")
  if not valid_scope[scope] then
    return false, "invalid scope: " .. scope
  end

  local store = load_store()
  local id = string.format("p-%06d", store.next_id)
  store.next_id = store.next_id + 1

  local cfg = config.get()
  local project_root = normalize_path(spec.project_root or cfg.root)

  local rule = {
    id = id,
    decision = decision,
    tool = tostring(spec.tool or "*"),
    action_class = tostring(spec.action_class or "*"),
    target = tostring(spec.target or "*"),
    scope = scope,
    project_root = scope == "project" and project_root or nil,
    task_id = scope == "task" and tostring(spec.task_id or "") or nil,
    inherit = spec.inherit ~= false,
    note = tostring(spec.note or ""),
    created_at = now_iso(),
    updated_at = now_iso(),
  }

  if scope == "project" and (rule.project_root == nil or rule.project_root == "") then
    return false, "project scope requires project_root"
  end

  if scope == "task" and (rule.task_id == nil or rule.task_id == "") then
    return false, "task scope requires task_id"
  end

  table.insert(store.rules, rule)
  save_store(store)

  log.record({
    event = "policy_grant",
    task_id = rule.task_id,
    tool = rule.tool,
    request = {
      scope = rule.scope,
      action_class = rule.action_class,
      target = rule.target,
    },
    policy_decision = rule.decision,
    result = {
      rule_id = rule.id,
    },
  })

  return true, vim.deepcopy(rule)
end

function M.revoke(rule_id)
  local store = load_store()
  local kept = {}
  local revoked = nil

  for _, rule in ipairs(store.rules) do
    if rule.id == rule_id then
      revoked = rule
    else
      table.insert(kept, rule)
    end
  end

  if not revoked then
    return false, "policy rule not found: " .. tostring(rule_id)
  end

  store.rules = kept
  save_store(store)

  log.record({
    event = "policy_revoke",
    task_id = revoked.task_id,
    tool = revoked.tool,
    request = {
      scope = revoked.scope,
      action_class = revoked.action_class,
      target = revoked.target,
    },
    policy_decision = revoked.decision,
    result = {
      rule_id = revoked.id,
    },
  })

  return true, vim.deepcopy(revoked)
end

function M.list()
  local store = load_store()
  local rules = vim.deepcopy(store.rules)
  table.sort(rules, function(a, b)
    return tostring(a.id) < tostring(b.id)
  end)
  return rules
end

function M.classify_action(action_class)
  local normalized = normalize_subject({ action_class = action_class })
  return {
    action_class = normalized.action_class,
    destructive = normalized.destructive,
  }
end

function M.path()
  return state.path(policy_file())
end

function M.reset_for_test()
  state.delete(policy_file())
  approvals.reset_for_test()
end

return M
