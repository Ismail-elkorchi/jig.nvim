local config = require("jig.agent.config")
local instructions = require("jig.agent.instructions")
local log = require("jig.agent.log")

local M = {}

local session_sources = {}

local function estimate(content)
  local text = content or ""
  return {
    bytes = #text,
    chars = vim.str_utfindex(text),
  }
end

local function budget_config(opts)
  local cfg = config.get(opts)
  local budget = tonumber(cfg.observability.budget_bytes) or 120000
  local warning_ratio = tonumber(cfg.observability.warning_ratio) or 0.8
  return {
    budget_bytes = math.max(1, math.floor(budget)),
    warning_ratio = math.max(0.1, math.min(0.99, warning_ratio)),
  }
end

local function canonical_source(source)
  local item = vim.deepcopy(source or {})
  item.id = tostring(item.id or "")
  if item.id == "" then
    return nil, "source id required"
  end

  item.kind = tostring(item.kind or "extra")
  item.label = tostring(item.label or item.id)
  item.path = tostring(item.path or "")
  item.source = tostring(item.source or "session")
  item.bytes = tonumber(item.bytes) or 0
  item.chars = tonumber(item.chars) or item.bytes
  item.tokens = item.tokens ~= nil and tonumber(item.tokens) or nil
  item.estimate = item.estimate ~= false
  return item, nil
end

local function sorted_session_sources()
  local out = {}
  for _, source in pairs(session_sources) do
    out[#out + 1] = vim.deepcopy(source)
  end
  table.sort(out, function(a, b)
    return tostring(a.id) < tostring(b.id)
  end)
  return out
end

local function current_buffer_source()
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    path = "[No Name]"
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local joined = table.concat(lines, "\n")
  local size = estimate(joined)

  return {
    id = "buffer:current",
    kind = "buffer",
    label = path,
    path = path,
    bytes = size.bytes,
    chars = size.chars,
    tokens = nil,
    estimate = true,
    source = "editor",
  }
end

local function instruction_sources(opts)
  local report = instructions.collect(opts)
  local sources = {}
  for _, item in ipairs(report.sources) do
    if item.exists and item.disabled ~= true then
      sources[#sources + 1] = {
        id = "instructions:" .. item.id,
        kind = "instructions",
        label = item.name,
        path = item.path,
        bytes = item.bytes,
        chars = item.chars,
        tokens = nil,
        estimate = true,
        source = item.scope,
      }
    end
  end
  return sources, report
end

local function tool_output_source()
  local last = vim.g.jig_exec_last
  if type(last) ~= "table" or type(last.result) ~= "table" then
    return nil
  end

  local result = last.result
  local stdout = tostring(result.stdout or "")
  local stderr = tostring(result.stderr or "")
  local content = stdout .. "\n" .. stderr
  local size = estimate(content)

  return {
    id = "tool:last_exec",
    kind = "tool_output",
    label = "JigExec(last)",
    path = "",
    bytes = size.bytes,
    chars = size.chars,
    tokens = nil,
    estimate = true,
    source = "tools",
  }
end

local function opts_sources(opts)
  local out = {}
  if type(opts) == "table" and type(opts.sources) == "table" then
    for _, source in ipairs(opts.sources) do
      local item, err = canonical_source(source)
      if item then
        out[#out + 1] = item
      elseif err then
        error(err)
      end
    end
  end
  return out
end

local function compute_totals(sources)
  local totals = {
    bytes = 0,
    chars = 0,
    tokens_estimate = 0,
    has_token_estimates = false,
  }

  for _, source in ipairs(sources or {}) do
    totals.bytes = totals.bytes + (tonumber(source.bytes) or 0)
    totals.chars = totals.chars + (tonumber(source.chars) or 0)
    if source.tokens ~= nil then
      totals.has_token_estimates = true
      totals.tokens_estimate = totals.tokens_estimate + (tonumber(source.tokens) or 0)
    end
  end

  return totals
end

local function warnings_for_totals(totals, budget_bytes, warning_ratio)
  local warnings = {}
  if totals.bytes >= budget_bytes then
    warnings[#warnings + 1] = "context_bytes_exceed_budget"
  elseif totals.bytes >= math.floor(budget_bytes * warning_ratio) then
    warnings[#warnings + 1] = "context_bytes_near_budget"
  end
  return warnings
end

local function make_report(opts)
  local budget = budget_config(opts)

  local sources = {}
  local instruction_items, instruction_report = instruction_sources(opts)
  vim.list_extend(sources, instruction_items)
  sources[#sources + 1] = current_buffer_source()

  local tool_item = tool_output_source()
  if tool_item then
    sources[#sources + 1] = tool_item
  end

  vim.list_extend(sources, sorted_session_sources())
  vim.list_extend(sources, opts_sources(opts))

  local totals = compute_totals(sources)
  local warnings = warnings_for_totals(totals, budget.budget_bytes, budget.warning_ratio)

  return {
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    budget_bytes = budget.budget_bytes,
    warning_ratio = budget.warning_ratio,
    warnings = warnings,
    totals = totals,
    sources = sources,
    precedence = instruction_report.precedence,
    root = instruction_report.root,
    session_source_count = vim.tbl_count(session_sources),
  }
end

function M.capture(opts)
  local report = make_report(opts)
  M.last_report = report
  return report
end

function M.add_source(source, opts)
  local item, err = canonical_source(source)
  if not item then
    return false, err
  end

  local budget = budget_config(opts)
  local existing = sorted_session_sources()
  local projected = vim.deepcopy(existing)

  local replaced = false
  for index, row in ipairs(projected) do
    if row.id == item.id then
      projected[index] = item
      replaced = true
      break
    end
  end
  if not replaced then
    projected[#projected + 1] = item
  end

  local totals = compute_totals(projected)
  if totals.bytes > budget.budget_bytes and opts and opts.force ~= true then
    local reason = "context budget exceeded; use reset or raise budget"
    log.record({
      event = "context_source_add_blocked",
      task_id = "",
      tool = "agent.context",
      request = {
        source_id = item.id,
        bytes = item.bytes,
      },
      policy_decision = "deny",
      result = {
        reason = "budget_exceeded",
        projected_bytes = totals.bytes,
        budget_bytes = budget.budget_bytes,
      },
      error_path = reason,
    })
    return false, reason
  end

  session_sources[item.id] = item

  log.record({
    event = "context_source_added",
    task_id = "",
    tool = "agent.context",
    request = {
      source_id = item.id,
      bytes = item.bytes,
    },
    policy_decision = "allow",
    result = {
      total_sources = vim.tbl_count(session_sources),
    },
  })

  return true, vim.deepcopy(item)
end

function M.remove_source(id)
  local token = tostring(id or "")
  if token == "" then
    return false, "source id required"
  end

  if not session_sources[token] then
    return false, "source not found: " .. token
  end

  session_sources[token] = nil

  log.record({
    event = "context_source_removed",
    task_id = "",
    tool = "agent.context",
    request = {
      source_id = token,
    },
    policy_decision = "allow",
    result = {
      total_sources = vim.tbl_count(session_sources),
    },
  })

  return true
end

function M.list_session_sources()
  return sorted_session_sources()
end

function M.render_lines(report)
  local lines = {
    "Jig Agent Context Ledger",
    string.rep("=", 48),
    "root: " .. tostring(report.root),
    "instruction precedence: " .. table.concat(report.precedence or {}, " > "),
    string.format("budget_bytes: %d", report.budget_bytes),
    string.format("totals: %d bytes, %d chars", report.totals.bytes, report.totals.chars),
    "warnings: " .. (#report.warnings > 0 and table.concat(report.warnings, ",") or "none"),
    "",
    "sources:",
  }

  for _, source in ipairs(report.sources) do
    local token_text
    if source.tokens ~= nil then
      token_text = string.format("tokens=%d (estimate)", tonumber(source.tokens) or 0)
    else
      token_text = "tokens=unknown (estimate unavailable)"
    end

    lines[#lines + 1] = string.format(
      "- [%s] %s | bytes=%d chars=%d %s",
      source.kind,
      source.label,
      tonumber(source.bytes) or 0,
      tonumber(source.chars) or 0,
      token_text
    )
  end

  return lines
end

function M.show(opts)
  local report = M.capture(opts)
  local lines = M.render_lines(report)

  if #vim.api.nvim_list_uis() == 0 then
    vim.g.jig_agent_context_last = report
    print(table.concat(lines, "\n"))
    return report
  end

  local ok_float, float = pcall(require, "jig.ui.float")
  if ok_float and type(float.open) == "function" then
    float.open(lines, {
      title = "Jig Context",
      level = "secondary",
      width = math.floor(vim.o.columns * 0.7),
      height = math.min(16, math.floor(vim.o.lines * 0.6)),
    })
  else
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end

  vim.g.jig_agent_context_last = report
  return report
end

function M.reset()
  session_sources = {}
  M.last_report = nil
  vim.g.jig_agent_context_last = nil

  log.record({
    event = "context_reset",
    task_id = "",
    tool = "agent.context",
    request = {},
    policy_decision = "allow",
    result = {
      total_sources = 0,
    },
  })
end

return M
