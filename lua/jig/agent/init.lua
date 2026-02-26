local approvals = require("jig.agent.approvals")
local backends = require("jig.agent.backends")
local brand = require("jig.core.brand")
local config = require("jig.agent.config")
local instructions = require("jig.agent.instructions")
local log = require("jig.agent.log")
local mcp = require("jig.agent.mcp.client")
local mcp_trust = require("jig.security.mcp_trust")
local observability = require("jig.agent.observability")
local patch = require("jig.agent.patch")
local policy = require("jig.agent.policy")
local task = require("jig.agent.task")

local M = {}

local commands_registered = false

local function open_report(title, lines, payload)
  local output = vim.deepcopy(lines or {})
  if #output == 0 then
    output = { "<empty>" }
  end

  if #vim.api.nvim_list_uis() == 0 then
    vim.g.jig_agent_last_report = {
      title = title,
      lines = output,
      payload = payload,
    }
    print(string.format("%s (%d lines)", title, #output))
    return
  end

  vim.cmd("botright new")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = "jigreport"
  vim.api.nvim_buf_set_name(bufnr, title)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, output)
  vim.bo[bufnr].modifiable = false

  vim.g.jig_agent_last_report = {
    title = title,
    bufnr = bufnr,
    lines = output,
    payload = payload,
  }
end

local function stringify(value)
  if type(value) == "table" then
    return vim.inspect(value)
  end
  return tostring(value)
end

local function parse_json(text)
  if text == nil or text == "" then
    return true, {}
  end

  local ok, decoded = pcall(vim.json.decode, text)
  if not ok then
    return false, tostring(decoded)
  end

  if type(decoded) ~= "table" then
    return false, "json args must decode to an object"
  end

  return true, decoded
end

local function parse_number(value, default_value)
  local parsed = tonumber(value)
  if parsed == nil then
    return default_value
  end
  return math.floor(parsed)
end

local function last_patch_session_id()
  return tostring(vim.g.jig_patch_last_session_id or "")
end

local function set_last_patch_session_id(session_id)
  vim.g.jig_patch_last_session_id = tostring(session_id or "")
end

local function require_session_id(arg)
  local token = tostring(arg or "")
  if token ~= "" then
    return token
  end
  return last_patch_session_id()
end

local function cmd_mcp_list()
  local report = mcp.list()
  local lines = {
    "Jig MCP Servers",
    string.rep("=", 48),
    "root: " .. tostring(report.root),
    "",
    "files:",
  }

  for _, file in ipairs(report.files) do
    local state_value = file.exists and "present" or "missing"
    local suffix = file.error ~= "" and (" error=" .. file.error) or ""
    lines[#lines + 1] =
      string.format("- %s (%s, servers=%d)%s", file.name, state_value, file.server_count, suffix)
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "servers:"
  for _, server in ipairs(report.servers) do
    local status = server.status or "stopped"
    local suffix = server.last_error ~= "" and (" error=" .. server.last_error) or ""
    lines[#lines + 1] = string.format("- %s [%s] %s%s", server.name, status, server.command, suffix)
  end

  open_report("JigMcpList", lines, report)
end

local function cmd_mcp_start(opts)
  local name = opts.args
  if name == "" then
    vim.notify("Usage: :JigMcpStart <server>", vim.log.levels.ERROR)
    return
  end

  local result = mcp.start(name, { actor = "user" })
  local level = result.ok and vim.log.levels.INFO or vim.log.levels.WARN
  vim.notify(
    string.format("JigMcpStart %s: %s (%s)", name, tostring(result.ok), result.reason),
    level
  )
  vim.g.jig_agent_last_mcp = result
end

local function cmd_mcp_stop(opts)
  local target = opts.args ~= "" and opts.args or "all"
  local result = mcp.stop(target)
  local level = result.ok and vim.log.levels.INFO or vim.log.levels.WARN
  vim.notify(
    string.format("JigMcpStop %s: %s (%s)", target, tostring(result.ok), result.reason),
    level
  )
  vim.g.jig_agent_last_mcp = result
end

local function cmd_mcp_tools(opts)
  local name = opts.args
  if name == "" then
    vim.notify("Usage: :JigMcpTools <server>", vim.log.levels.ERROR)
    return
  end

  local result = mcp.tools(name, { actor = "user" })
  local lines = {
    "Jig MCP Tools",
    string.rep("=", 48),
    string.format("server: %s", name),
    string.format("ok: %s", tostring(result.ok)),
    string.format("reason: %s", tostring(result.reason)),
    string.format("hint: %s", tostring(result.hint or "")),
  }

  if result.ok and type(result.payload) == "table" then
    local tools = result.payload.tools or {}
    lines[#lines + 1] = ""
    lines[#lines + 1] = "tools:"
    for _, tool_spec in ipairs(tools) do
      local item = tool_spec.name or stringify(tool_spec)
      lines[#lines + 1] = "- " .. item
    end
  else
    lines[#lines + 1] = ""
    lines[#lines + 1] = "payload:"
    lines[#lines + 1] = stringify(result.payload)
  end

  open_report("JigMcpTools", lines, result)
end

local function cmd_mcp_call(opts)
  if #opts.fargs < 2 then
    vim.notify("Usage: :JigMcpCall <server> <tool> <json_args>", vim.log.levels.ERROR)
    return
  end

  local server = opts.fargs[1]
  local tool_name = opts.fargs[2]
  local args_text = table.concat(vim.list_slice(opts.fargs, 3), " ")
  local ok_json, decoded_or_err = parse_json(args_text)
  if not ok_json then
    vim.notify("JigMcpCall invalid JSON args: " .. decoded_or_err, vim.log.levels.ERROR)
    return
  end

  local result = mcp.call(server, tool_name, decoded_or_err, { actor = "user" })
  local lines = {
    "Jig MCP Call",
    string.rep("=", 48),
    string.format("server: %s", server),
    string.format("tool: %s", tool_name),
    string.format("ok: %s", tostring(result.ok)),
    string.format("reason: %s", tostring(result.reason)),
    string.format("hint: %s", tostring(result.hint or "")),
    "",
    "payload:",
    stringify(result.payload),
  }
  open_report("JigMcpCall", lines, result)
end

local function find_server_spec(name)
  local report = mcp.discovery()
  local server = report.servers and report.servers[name] or nil
  return server, report
end

local function render_capability_pairs(capabilities)
  local chunks = {}
  for tool_name, capability in pairs(capabilities or {}) do
    chunks[#chunks + 1] =
      string.format("%s(%s)", tostring(tool_name), tostring(capability.action_class))
  end
  table.sort(chunks)
  if #chunks == 0 then
    return "<none>"
  end
  return table.concat(chunks, ",")
end

local function cmd_mcp_trust(opts)
  local fargs = opts.fargs or {}
  if #fargs == 0 then
    local report = mcp.list()
    local lines = {
      "Jig MCP Trust",
      string.rep("=", 48),
      "trust_path: " .. mcp_trust.path(),
      "",
    }

    for _, server in ipairs(report.servers or {}) do
      lines[#lines + 1] = string.format(
        "- %s trust=%s source=%s status=%s caps=%s",
        server.name,
        tostring(server.trust or "ask"),
        tostring(server.source_label or "unknown"),
        tostring(server.status or "stopped"),
        render_capability_pairs(server.capabilities)
      )
    end

    open_report("JigMcpTrust", lines, report)
    return
  end

  local operation = tostring(fargs[1] or "")
  local server_name = tostring(fargs[2] or "")
  if server_name == "" then
    vim.notify("Usage: :JigMcpTrust [allow|ask|deny|revoke] <server>", vim.log.levels.ERROR)
    return
  end

  local server, _ = find_server_spec(server_name)
  if server == nil then
    vim.notify("JigMcpTrust server not found: " .. server_name, vim.log.levels.ERROR)
    return
  end

  if operation == "revoke" then
    local ok, payload = mcp_trust.revoke(server, { task_id = nil })
    if not ok then
      vim.notify("JigMcpTrust revoke failed: " .. tostring(payload), vim.log.levels.ERROR)
      return
    end
    vim.notify("JigMcpTrust revoked: " .. tostring(payload.server_name), vim.log.levels.INFO)
    return
  end

  if operation == "allow" or operation == "deny" or operation == "ask" then
    local ok, payload = mcp_trust.set_state(server, operation, { task_id = nil })
    if not ok then
      vim.notify("JigMcpTrust update failed: " .. tostring(payload), vim.log.levels.ERROR)
      return
    end
    vim.notify(
      string.format("JigMcpTrust %s -> %s", payload.server_name, payload.trust),
      vim.log.levels.INFO
    )
    return
  end

  vim.notify("Usage: :JigMcpTrust [allow|ask|deny|revoke] <server>", vim.log.levels.ERROR)
end

local function cmd_policy_list()
  local rules = policy.list()
  local lines = {
    "Jig Agent Policy Rules",
    string.rep("=", 48),
    "path: " .. policy.path(),
  }

  if #rules == 0 then
    lines[#lines + 1] = "<empty>"
  end

  for _, rule in ipairs(rules) do
    local scope_value = ""
    if rule.scope == "project" then
      scope_value = " project=" .. tostring(rule.project_root)
    elseif rule.scope == "task" then
      scope_value = " task=" .. tostring(rule.task_id)
    end

    lines[#lines + 1] = string.format(
      "- %s decision=%s scope=%s tool=%s action=%s target=%s%s",
      rule.id,
      rule.decision,
      rule.scope,
      rule.tool,
      rule.action_class,
      rule.target,
      scope_value
    )
  end

  open_report("JigAgentPolicyList", lines, rules)
end

local function cmd_policy_grant(opts)
  if #opts.fargs < 5 then
    vim.notify(
      "Usage: :JigAgentPolicyGrant <allow|ask|deny> <tool> <action_class> <target> <global|project|task> [scope_value]",
      vim.log.levels.ERROR
    )
    return
  end

  local decision = opts.fargs[1]
  local tool_name = opts.fargs[2]
  local action_class = opts.fargs[3]
  local target = opts.fargs[4]
  local scope = opts.fargs[5]
  local scope_value = opts.fargs[6]

  local spec = {
    decision = decision,
    tool = tool_name,
    action_class = action_class,
    target = target,
    scope = scope,
  }

  if scope == "project" then
    spec.project_root = scope_value ~= nil and scope_value ~= "" and scope_value
      or config.get().root
  elseif scope == "task" then
    spec.task_id = scope_value
  end

  local ok, rule_or_err = policy.grant(spec)
  if not ok then
    vim.notify("JigAgentPolicyGrant failed: " .. tostring(rule_or_err), vim.log.levels.ERROR)
    return
  end

  vim.notify("JigAgentPolicyGrant created: " .. rule_or_err.id, vim.log.levels.INFO)
end

local function cmd_policy_revoke(opts)
  if opts.args == "" then
    vim.notify("Usage: :JigAgentPolicyRevoke <rule_id>", vim.log.levels.ERROR)
    return
  end

  local ok, payload = policy.revoke(opts.args)
  if not ok then
    vim.notify("JigAgentPolicyRevoke failed: " .. tostring(payload), vim.log.levels.ERROR)
    return
  end

  vim.notify("JigAgentPolicyRevoke removed: " .. payload.id, vim.log.levels.INFO)
end

local function cmd_approvals()
  local pending = approvals.list({ status = "pending" })
  local resolved = approvals.list({ status = "resolved" })

  local lines = {
    "Jig Agent Approval Queue",
    string.rep("=", 48),
    "path: " .. approvals.path(),
    "pending: " .. tostring(#pending),
    "resolved: " .. tostring(#resolved),
    "",
    "pending approvals:",
  }

  if #pending == 0 then
    lines[#lines + 1] = "<empty>"
  end

  for _, entry in ipairs(pending) do
    lines[#lines + 1] = string.format(
      "- %s tool=%s action=%s target=%s reason=%s",
      entry.id,
      tostring(entry.subject.tool),
      tostring(entry.subject.action_class),
      tostring(entry.subject.target),
      tostring(entry.hint or entry.reason or "")
    )
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] =
    "resolve: :JigAgentApprovalResolve <approval_id> <allow|deny|allow-always|deny-always> [scope] [scope_value]"

  open_report("JigAgentApprovals", lines, {
    pending = pending,
    resolved = resolved,
  })
end

local function map_resolution(token)
  local value = tostring(token or "")
  if value == "allow" then
    return "allow_once"
  end
  if value == "deny" then
    return "deny_once"
  end
  if value == "allow-once" then
    return "allow_once"
  end
  if value == "deny-once" then
    return "deny_once"
  end
  if value == "allow-always" then
    return "allow_always"
  end
  if value == "deny-always" then
    return "deny_always"
  end
  return ""
end

local function grant_from_approval(entry, decision, scope, scope_value)
  local subject = entry.subject or {}
  local spec = {
    decision = decision,
    tool = subject.tool,
    action_class = subject.action_class,
    target = subject.target,
    scope = scope,
  }

  if scope == "project" then
    spec.project_root = (scope_value and scope_value ~= "" and scope_value)
      or subject.project_root
      or config.get().root
  elseif scope == "task" then
    spec.task_id = (scope_value and scope_value ~= "" and scope_value) or subject.task_id
  end

  return policy.grant(spec)
end

local function cmd_approval_resolve(opts)
  if #opts.fargs < 2 then
    vim.notify(
      "Usage: :JigAgentApprovalResolve <approval_id> <allow|deny|allow-always|deny-always> [global|project|task] [scope_value]",
      vim.log.levels.ERROR
    )
    return
  end

  local approval_id = tostring(opts.fargs[1])
  local resolution = map_resolution(opts.fargs[2])
  if resolution == "" then
    vim.notify("Invalid resolution", vim.log.levels.ERROR)
    return
  end

  local entry = approvals.get(approval_id)
  if not entry then
    vim.notify("Approval not found: " .. approval_id, vim.log.levels.ERROR)
    return
  end

  local rule_id = ""
  if resolution == "allow_always" or resolution == "deny_always" then
    local decision = resolution == "allow_always" and "allow" or "deny"
    local scope = tostring(opts.fargs[3] or "project")
    local scope_value = tostring(opts.fargs[4] or "")

    if scope ~= "global" and scope ~= "project" and scope ~= "task" then
      vim.notify("Invalid scope: " .. scope, vim.log.levels.ERROR)
      return
    end

    local ok_rule, rule_or_err = grant_from_approval(entry, decision, scope, scope_value)
    if not ok_rule then
      vim.notify("Persistent grant failed: " .. tostring(rule_or_err), vim.log.levels.ERROR)
      return
    end
    rule_id = rule_or_err.id
  end

  local ok_resolve, payload = approvals.resolve(approval_id, resolution, {
    rule_id = rule_id,
  })
  if not ok_resolve then
    vim.notify("Resolve failed: " .. tostring(payload), vim.log.levels.ERROR)
    return
  end

  vim.notify(
    string.format("Approval %s resolved as %s", payload.id, payload.resolution),
    vim.log.levels.INFO
  )
end

local function cmd_instructions()
  local lines, report = instructions.describe_lines()
  open_report("JigAgentInstructions", lines, report)
end

local function cmd_instruction_disable(opts)
  if opts.args == "" then
    vim.notify("Usage: :JigAgentInstructionDisable <source_id|path>", vim.log.levels.ERROR)
    return
  end

  local ok, payload = instructions.disable(opts.args)
  if not ok then
    vim.notify("Disable failed: " .. tostring(payload), vim.log.levels.ERROR)
    return
  end

  vim.notify("Instruction source disabled: " .. payload.id, vim.log.levels.INFO)
end

local function cmd_instruction_enable(opts)
  if opts.args == "" then
    vim.notify("Usage: :JigAgentInstructionEnable <source_id|path>", vim.log.levels.ERROR)
    return
  end

  local ok, payload = instructions.enable(opts.args)
  if not ok then
    vim.notify("Enable failed: " .. tostring(payload), vim.log.levels.ERROR)
    return
  end

  vim.notify("Instruction source enabled: " .. payload.id, vim.log.levels.INFO)
end

local function cmd_context()
  observability.show()
end

local function cmd_context_add(opts)
  if #opts.fargs < 2 then
    vim.notify("Usage: :JigAgentContextAdd <id> <bytes> [kind] [label]", vim.log.levels.ERROR)
    return
  end

  local source_id = tostring(opts.fargs[1])
  local bytes = parse_number(opts.fargs[2], 0)
  local kind = tostring(opts.fargs[3] or "extra")
  local label = tostring(opts.fargs[4] or source_id)

  local ok, payload = observability.add_source({
    id = source_id,
    kind = kind,
    label = label,
    bytes = bytes,
    chars = bytes,
    source = "manual",
    estimate = true,
  })

  if not ok then
    vim.notify("Context add blocked: " .. tostring(payload), vim.log.levels.WARN)
    return
  end

  vim.notify("Context source added: " .. payload.id, vim.log.levels.INFO)
end

local function cmd_context_remove(opts)
  if opts.args == "" then
    vim.notify("Usage: :JigAgentContextRemove <source_id>", vim.log.levels.ERROR)
    return
  end

  local ok, payload = observability.remove_source(opts.args)
  if not ok then
    vim.notify("Context remove failed: " .. tostring(payload), vim.log.levels.ERROR)
    return
  end

  vim.notify("Context source removed", vim.log.levels.INFO)
end

local function cmd_context_reset()
  observability.reset()
  vim.notify("JigAgentContext ledger reset", vim.log.levels.INFO)
end

local function default_task_runner(ctx)
  vim.wait(120, function()
    return ctx.is_cancelled()
  end, 15)

  if ctx.is_cancelled() then
    return {
      cancelled = true,
    }
  end

  return {
    candidate = "noop",
  }
end

local function cmd_task_start(opts)
  local title = opts.args ~= "" and opts.args or "agent-task"
  local item = task.start({
    title = title,
    kind = "manual",
    run = default_task_runner,
  })

  vim.notify("JigAgentTaskStart: " .. item.id, vim.log.levels.INFO)
end

local function cmd_task_cancel(opts)
  if opts.args == "" then
    vim.notify("Usage: :JigAgentTaskCancel <task_id>", vim.log.levels.ERROR)
    return
  end

  local ok, payload = task.cancel(opts.args, "user_cancel")
  if not ok then
    vim.notify("JigAgentTaskCancel failed: " .. tostring(payload), vim.log.levels.ERROR)
    return
  end

  vim.notify("JigAgentTaskCancel: " .. payload.id, vim.log.levels.INFO)
end

local function cmd_task_resume(opts)
  if opts.args == "" then
    vim.notify("Usage: :JigAgentTaskResume <task_id>", vim.log.levels.ERROR)
    return
  end

  local ok, payload = task.resume(opts.args, {
    run = default_task_runner,
  })

  if not ok then
    vim.notify("JigAgentTaskResume failed: " .. tostring(payload), vim.log.levels.ERROR)
    return
  end

  vim.notify("JigAgentTaskResume: " .. payload.task.id, vim.log.levels.INFO)
end

local function cmd_task_list()
  local tasks = task.list()
  local lines = {
    "Jig Agent Tasks",
    string.rep("=", 48),
  }

  if #tasks == 0 then
    lines[#lines + 1] = "<empty>"
  end

  for _, item in ipairs(tasks) do
    lines[#lines + 1] = string.format(
      "- %s status=%s parent=%s resume_count=%d title=%s",
      item.id,
      item.status,
      tostring(item.parent_task_id or "-"),
      tonumber(item.resume_count) or 0,
      item.title
    )
  end

  open_report("JigAgentTasks", lines, tasks)
end

local function cmd_log_tail(opts)
  local count = tonumber(opts.args) or 20
  local rows = log.tail(count)

  local lines = {
    "Jig Agent Evidence Log",
    string.rep("=", 48),
    "path: " .. log.path(),
    "entries: " .. tostring(#rows),
    "",
  }

  for _, row in ipairs(rows) do
    lines[#lines + 1] = string.format(
      "- %s task=%s tool=%s decision=%s event=%s",
      tostring(row.timestamp),
      tostring(row.task_id),
      tostring(row.tool),
      tostring(row.policy_decision),
      tostring(row.event)
    )
  end

  open_report("JigAgentLogTail", lines, rows)
end

local function cmd_acp_handshake(opts)
  if opts.args == "" then
    vim.notify("Usage: :JigAcpHandshake <json_spec>", vim.log.levels.ERROR)
    return
  end

  local ok_json, spec_or_err = parse_json(opts.args)
  if not ok_json then
    vim.notify("JigAcpHandshake invalid JSON: " .. spec_or_err, vim.log.levels.ERROR)
    return
  end

  local adapter = backends.get("acp-stdio")
  local result = adapter.handshake(spec_or_err, {})
  local level = result.ok and vim.log.levels.INFO or vim.log.levels.WARN
  vim.notify("JigAcpHandshake: " .. tostring(result.ok), level)
  vim.g.jig_agent_last_acp = result
end

local function cmd_acp_prompt(opts)
  if #opts.fargs < 2 then
    vim.notify("Usage: :JigAcpPrompt <json_spec> <prompt>", vim.log.levels.ERROR)
    return
  end

  local ok_json, spec_or_err = parse_json(opts.fargs[1])
  if not ok_json then
    vim.notify("JigAcpPrompt invalid JSON spec: " .. spec_or_err, vim.log.levels.ERROR)
    return
  end

  local prompt = table.concat(vim.list_slice(opts.fargs, 2), " ")
  local result = backends.prompt("acp-stdio", spec_or_err, prompt, {})
  local lines = {
    "Jig ACP Prompt",
    string.rep("=", 48),
    "ok: " .. tostring(result.ok),
    "reason: " .. tostring(result.reason or "ok"),
    "",
    stringify(result.result or result.response or result),
  }
  open_report("JigAcpPrompt", lines, result)
end

local function cmd_patch_create(opts)
  if opts.args == "" then
    vim.notify("Usage: :JigPatchCreate <json_patch_spec>", vim.log.levels.ERROR)
    return
  end

  local ok_json, spec_or_err = parse_json(opts.args)
  if not ok_json then
    vim.notify("JigPatchCreate invalid JSON: " .. tostring(spec_or_err), vim.log.levels.ERROR)
    return
  end

  local ok_create, session_or_err = patch.create(spec_or_err)
  if not ok_create then
    vim.notify("JigPatchCreate failed: " .. tostring(session_or_err), vim.log.levels.ERROR)
    return
  end

  set_last_patch_session_id(session_or_err.id)
  vim.notify("JigPatchCreate: " .. session_or_err.id, vim.log.levels.INFO)
end

local function cmd_patch_sessions()
  local sessions = patch.list()
  local lines = {
    "Jig Patch Sessions",
    string.rep("=", 48),
  }

  if #sessions == 0 then
    lines[#lines + 1] = "<empty>"
  end

  for _, session in ipairs(sessions) do
    lines[#lines + 1] = string.format(
      "- %s status=%s files=%d intent=%s",
      session.id,
      tostring(session.status),
      #(session.files or {}),
      tostring(session.intent)
    )
  end

  open_report("JigPatchSessions", lines, sessions)
end

local function cmd_patch_review(opts)
  local session_id = require_session_id(opts.args)
  if session_id == "" then
    vim.notify("Usage: :JigPatchReview <session_id>", vim.log.levels.ERROR)
    return
  end

  local ok, payload = patch.open_review(session_id)
  if not ok then
    vim.notify("JigPatchReview failed: " .. tostring(payload), vim.log.levels.ERROR)
    return
  end

  set_last_patch_session_id(session_id)
  vim.g.jig_patch_last_view = payload
end

local function cmd_patch_hunk_show(opts)
  if #opts.fargs < 3 then
    vim.notify(
      "Usage: :JigPatchHunkShow <session_id> <file_index> <hunk_index>",
      vim.log.levels.ERROR
    )
    return
  end

  local session_id = opts.fargs[1]
  local file_index = parse_number(opts.fargs[2], 0)
  local hunk_index = parse_number(opts.fargs[3], 0)

  local ok, payload = patch.open_hunk(session_id, file_index, hunk_index)
  if not ok then
    vim.notify("JigPatchHunkShow failed: " .. tostring(payload), vim.log.levels.ERROR)
    return
  end

  set_last_patch_session_id(session_id)
  vim.g.jig_patch_last_hunk_view = payload
end

local function patch_hunk_action(command_name, fn, opts)
  if #opts.fargs < 3 then
    vim.notify(
      string.format("Usage: :%s <session_id> <file_index> <hunk_index>", command_name),
      vim.log.levels.ERROR
    )
    return
  end

  local session_id = opts.fargs[1]
  local file_index = parse_number(opts.fargs[2], 0)
  local hunk_index = parse_number(opts.fargs[3], 0)

  local ok, payload = fn(session_id, file_index, hunk_index)
  if not ok then
    vim.notify(
      string.format("%s failed: %s", command_name, tostring(payload)),
      vim.log.levels.ERROR
    )
    return
  end

  set_last_patch_session_id(session_id)
  vim.notify(
    string.format(
      "%s: file=%d hunk=%d status=%s",
      command_name,
      file_index,
      hunk_index,
      payload.status
    ),
    vim.log.levels.INFO
  )
end

local function patch_session_action(command_name, fn, opts)
  local session_id = require_session_id(opts.args)
  if session_id == "" then
    vim.notify(string.format("Usage: :%s <session_id>", command_name), vim.log.levels.ERROR)
    return
  end

  local ok, payload = fn(session_id)
  if not ok then
    vim.notify(
      string.format("%s failed: %s", command_name, tostring(payload)),
      vim.log.levels.ERROR
    )
    return
  end

  set_last_patch_session_id(session_id)
  vim.notify(string.format("%s: %s", command_name, tostring(payload.status)), vim.log.levels.INFO)
end

local function create_command(name, fn, opts)
  if vim.fn.exists(":" .. name) == 2 then
    return
  end
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

local function register_commands()
  if commands_registered then
    return
  end

  create_command(brand.command("McpList"), cmd_mcp_list, {
    desc = "List MCP config files, servers, and runtime states",
  })

  create_command(brand.command("McpStart"), cmd_mcp_start, {
    nargs = 1,
    desc = "Start MCP server handshake",
  })

  create_command(brand.command("McpStop"), cmd_mcp_stop, {
    nargs = "?",
    complete = function()
      return { "all" }
    end,
    desc = "Stop one MCP server or all runtime sessions",
  })

  create_command(brand.command("McpTools"), cmd_mcp_tools, {
    nargs = 1,
    desc = "List tools from an MCP server (policy-routed)",
  })

  create_command(brand.command("McpCall"), cmd_mcp_call, {
    nargs = "+",
    desc = "Call MCP tool with JSON args (policy-routed)",
  })

  create_command(brand.command("McpTrust"), cmd_mcp_trust, {
    nargs = "*",
    complete = function(_, cmdline)
      local values = {}
      local tokens = vim.split(cmdline, "%s+", { trimempty = true })
      if #tokens <= 1 then
        return { "allow", "ask", "deny", "revoke" }
      end
      local report = mcp.list()
      for _, server in ipairs(report.servers or {}) do
        values[#values + 1] = server.name
      end
      return values
    end,
    desc = "List or modify MCP trust entries",
  })

  create_command(brand.command("AgentPolicyList"), cmd_policy_list, {
    desc = "List persisted allow/ask/deny rules",
  })

  create_command(brand.command("AgentPolicyGrant"), cmd_policy_grant, {
    nargs = "+",
    desc = "Persist allow/ask/deny policy rule with explicit scope",
  })

  create_command(brand.command("AgentPolicyRevoke"), cmd_policy_revoke, {
    nargs = 1,
    desc = "Revoke persisted policy rule",
  })

  create_command(brand.command("AgentApprovals"), cmd_approvals, {
    desc = "Show pending/resolved approval queue",
  })

  create_command(brand.command("AgentApprovalResolve"), cmd_approval_resolve, {
    nargs = "+",
    complete = function(_, cmdline)
      local tokens = vim.split(cmdline, "%s+", { trimempty = true })
      if #tokens <= 1 then
        local values = {}
        for _, entry in ipairs(approvals.list({ status = "pending" })) do
          values[#values + 1] = entry.id
        end
        return values
      end
      if #tokens == 2 then
        return { "allow", "deny", "allow-always", "deny-always" }
      end
      if #tokens == 3 then
        return { "global", "project", "task" }
      end
      return {}
    end,
    desc = "Resolve pending approval (once or persisted)",
  })

  create_command(brand.command("AgentInstructions"), cmd_instructions, {
    desc = "Show merged instruction files and precedence",
  })

  create_command(brand.command("AgentInstructionDisable"), cmd_instruction_disable, {
    nargs = 1,
    desc = "Disable one instruction source with audit log entry",
  })

  create_command(brand.command("AgentInstructionEnable"), cmd_instruction_enable, {
    nargs = 1,
    desc = "Enable one instruction source with audit log entry",
  })

  create_command(brand.command("AgentContext"), cmd_context, {
    desc = "Show context ledger with budget warnings",
  })

  create_command(brand.command("AgentContextAdd"), cmd_context_add, {
    nargs = "+",
    desc = "Add manual source to context ledger (budget enforced)",
  })

  create_command(brand.command("AgentContextRemove"), cmd_context_remove, {
    nargs = 1,
    desc = "Remove source from context ledger",
  })

  create_command(brand.command("AgentContextReset"), cmd_context_reset, {
    desc = "Reset context ledger snapshot",
  })

  create_command(brand.command("AgentTaskStart"), cmd_task_start, {
    nargs = "?",
    desc = "Start background Jig-level agent task handle",
  })

  create_command(brand.command("AgentTaskCancel"), cmd_task_cancel, {
    nargs = 1,
    desc = "Cancel Jig-level agent task handle",
  })

  create_command(brand.command("AgentTaskResume"), cmd_task_resume, {
    nargs = 1,
    desc = "Resume Jig-level task handle from metadata + evidence log",
  })

  create_command(brand.command("AgentTasks"), cmd_task_list, {
    desc = "List agent task handles",
  })

  create_command(brand.command("AgentLogTail"), cmd_log_tail, {
    nargs = "?",
    desc = "Show tail of append-only agent evidence log",
  })

  create_command(brand.command("AcpHandshake"), cmd_acp_handshake, {
    nargs = 1,
    desc = "Run ACP stdio handshake skeleton using JSON spec",
  })

  create_command(brand.command("AcpPrompt"), cmd_acp_prompt, {
    nargs = "+",
    desc = "Run ACP stdio candidate prompt call using JSON spec",
  })

  create_command(brand.command("PatchCreate"), cmd_patch_create, {
    nargs = 1,
    desc = "Create patch session from JSON candidate",
  })

  create_command(brand.command("PatchSessions"), cmd_patch_sessions, {
    desc = "List patch sessions",
  })

  create_command(brand.command("PatchReview"), cmd_patch_review, {
    nargs = "?",
    desc = "Open dedicated patch review view",
  })

  create_command(brand.command("PatchHunkShow"), cmd_patch_hunk_show, {
    nargs = "+",
    desc = "Open hunk drill-down view",
  })

  create_command(brand.command("PatchHunkAccept"), function(opts)
    patch_hunk_action(brand.command("PatchHunkAccept"), patch.accept_hunk, opts)
  end, {
    nargs = "+",
    desc = "Accept one hunk",
  })

  create_command(brand.command("PatchHunkReject"), function(opts)
    patch_hunk_action(brand.command("PatchHunkReject"), patch.reject_hunk, opts)
  end, {
    nargs = "+",
    desc = "Reject one hunk",
  })

  create_command(brand.command("PatchApplyAll"), function(opts)
    patch_session_action(brand.command("PatchApplyAll"), patch.apply_all, opts)
  end, {
    nargs = "?",
    desc = "Mark all hunks accepted",
  })

  create_command(brand.command("PatchDiscardAll"), function(opts)
    patch_session_action(brand.command("PatchDiscardAll"), patch.discard_all, opts)
  end, {
    nargs = "?",
    desc = "Mark all hunks rejected",
  })

  create_command(brand.command("PatchApply"), function(opts)
    patch_session_action(brand.command("PatchApply"), patch.apply, opts)
  end, {
    nargs = "?",
    desc = "Apply accepted hunks to files",
  })

  create_command(brand.command("PatchRollback"), function(opts)
    patch_session_action(brand.command("PatchRollback"), patch.rollback, opts)
  end, {
    nargs = "?",
    desc = "Rollback files to session checkpoint",
  })

  commands_registered = true
end

function M.setup(opts)
  opts = opts or {}

  if vim.g.jig_safe_profile then
    return {
      enabled = false,
      profile = "safe",
    }
  end

  local cfg = config.get(opts)
  if cfg.enabled ~= true and opts.force ~= true then
    vim.g.jig_agent_enabled = false
    return {
      enabled = false,
      profile = vim.g.jig_profile,
    }
  end

  register_commands()
  approvals.pending_count()
  vim.g.jig_agent_enabled = true
  return {
    enabled = true,
    profile = vim.g.jig_profile,
    session_id = log.session_id(),
  }
end

return M
