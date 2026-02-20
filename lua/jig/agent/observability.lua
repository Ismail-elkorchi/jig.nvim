local config = require("jig.agent.config")
local instructions = require("jig.agent.instructions")

local M = {}

local function estimate(content)
  local text = content or ""
  return {
    bytes = #text,
    chars = vim.str_utfindex(text),
  }
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
    source = "editor",
  }
end

local function instruction_sources(opts)
  local report = instructions.collect(opts)
  local sources = {}
  for _, item in ipairs(report.sources) do
    if item.exists then
      table.insert(sources, {
        id = "instructions:" .. item.id,
        kind = "instructions",
        label = item.name,
        path = item.path,
        bytes = item.bytes,
        chars = item.chars,
        tokens = nil,
        source = item.scope,
      })
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
    source = "tools",
  }
end

local function extra_sources(opts)
  local out = {}

  if type(opts) == "table" and type(opts.sources) == "table" then
    for _, source in ipairs(opts.sources) do
      if type(source) == "table" then
        local item = vim.deepcopy(source)
        item.id = tostring(item.id or ("extra:" .. tostring(#out + 1)))
        item.kind = tostring(item.kind or "extra")
        item.label = tostring(item.label or item.id)
        item.path = tostring(item.path or "")
        item.bytes = tonumber(item.bytes) or 0
        item.chars = tonumber(item.chars) or item.bytes
        out[#out + 1] = item
      end
    end
  end

  return out
end

function M.capture(opts)
  local cfg = config.get(opts)
  local budget = tonumber(cfg.observability.budget_bytes) or 120000
  local warning_ratio = tonumber(cfg.observability.warning_ratio) or 0.8

  local sources = {}

  local instruction_items, instruction_report = instruction_sources(opts)
  vim.list_extend(sources, instruction_items)
  table.insert(sources, current_buffer_source())

  local tool_item = tool_output_source()
  if tool_item then
    table.insert(sources, tool_item)
  end

  vim.list_extend(sources, extra_sources(opts))

  local totals = {
    bytes = 0,
    chars = 0,
    tokens_estimate = 0,
    has_token_estimates = false,
  }

  for _, source in ipairs(sources) do
    totals.bytes = totals.bytes + (tonumber(source.bytes) or 0)
    totals.chars = totals.chars + (tonumber(source.chars) or 0)
    if source.tokens ~= nil then
      totals.has_token_estimates = true
      totals.tokens_estimate = totals.tokens_estimate + (tonumber(source.tokens) or 0)
    end
  end

  local warnings = {}
  if totals.bytes >= budget then
    table.insert(warnings, "context_bytes_exceed_budget")
  elseif totals.bytes >= math.floor(budget * warning_ratio) then
    table.insert(warnings, "context_bytes_near_budget")
  end

  local report = {
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    budget_bytes = budget,
    warning_ratio = warning_ratio,
    warnings = warnings,
    totals = totals,
    sources = sources,
    precedence = instruction_report.precedence,
    root = instruction_report.root,
  }

  M.last_report = report
  return report
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
    table.insert(
      lines,
      string.format(
        "- [%s] %s | bytes=%d chars=%d",
        source.kind,
        source.label,
        tonumber(source.bytes) or 0,
        tonumber(source.chars) or 0
      )
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
  M.last_report = nil
  vim.g.jig_agent_context_last = nil
end

return M
