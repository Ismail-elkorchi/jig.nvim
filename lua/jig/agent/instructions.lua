local config = require("jig.agent.config")
local log = require("jig.agent.log")
local state = require("jig.agent.state")

local M = {}

local default_file_set = {
  AGENTS = "AGENTS.md",
  CLAUDE = "CLAUDE.md",
  GEMINI = "GEMINI.md",
}

local function project_root(opts)
  if opts and type(opts.root) == "string" and opts.root ~= "" then
    return config.normalize_path(opts.root)
  end

  local cfg = config.get(opts)
  return config.normalize_path(cfg.root or vim.uv.cwd())
end

local function disabled_file()
  local cfg = config.get()
  return cfg.instructions.disabled_file
end

local function load_disabled()
  local payload = state.read_json(disabled_file(), {
    version = 1,
    disabled = {},
  })

  local disabled = payload.disabled
  if type(disabled) ~= "table" then
    disabled = {}
  end
  return disabled
end

local function save_disabled(disabled)
  return state.write_json(disabled_file(), {
    version = 1,
    disabled = disabled,
  })
end

local function expand_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local expanded = vim.fn.expand(path)
  return config.normalize_path(expanded)
end

local function read_text(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end

  local lines = vim.fn.readfile(path)
  local content = table.concat(lines, "\n")
  local chars = vim.str_utfindex(content)
  local bytes = #content

  return {
    content = content,
    chars = chars,
    bytes = bytes,
  }
end

local function project_candidates(cfg, root)
  local out = {}
  local names = cfg.instructions.project_files or {}
  for _, name in ipairs(names) do
    out[#out + 1] = {
      scope = "project",
      name = name,
      path = root .. "/" .. name,
    }
  end

  if type(cfg.instructions.project_extra) == "table" then
    for _, name in ipairs(cfg.instructions.project_extra) do
      out[#out + 1] = {
        scope = "project",
        name = name,
        path = root .. "/" .. name,
      }
    end
  end

  return out
end

local function path_candidates(scope, paths)
  local out = {}
  for _, item in ipairs(paths or {}) do
    local normalized = expand_path(item)
    if normalized then
      out[#out + 1] = {
        scope = scope,
        name = vim.fn.fnamemodify(normalized, ":t"),
        path = normalized,
      }
    end
  end
  return out
end

local function collect_for_scope(cfg, scope, root)
  if scope == "project" then
    return project_candidates(cfg, root)
  end

  if scope == "user" then
    return path_candidates("user", cfg.instructions.user_paths)
  end

  if scope == "global" then
    return path_candidates("global", cfg.instructions.global_paths)
  end

  return {}
end

local function normalize_identifier(id)
  return tostring(id or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function resolve_source(identifier, report)
  local token = normalize_identifier(identifier)
  if token == "" then
    return nil
  end

  for _, source in ipairs(report.sources or {}) do
    if source.id == token or source.path == token or source.name == token then
      return source
    end
  end

  return nil
end

local function toggle_source(identifier, disabled_value, opts)
  opts = opts or {}
  local report = M.collect(opts)
  local source = resolve_source(identifier, report)
  if not source then
    return false, "instruction source not found: " .. tostring(identifier)
  end

  if source.path == nil or source.path == "" then
    return false, "instruction source has no stable path"
  end

  local disabled = load_disabled()
  disabled[source.path] = disabled_value and true or nil
  save_disabled(disabled)

  log.record({
    event = disabled_value and "instruction_source_disabled" or "instruction_source_enabled",
    task_id = "",
    tool = "agent.instructions",
    request = {
      source_id = source.id,
      path = source.path,
      scope = source.scope,
    },
    policy_decision = "allow",
    result = {
      disabled = disabled_value == true,
    },
  })

  return true, source
end

function M.collect(opts)
  local cfg = config.get(opts)
  local root = project_root(opts)
  local precedence = cfg.instructions.precedence or { "project", "user", "global" }
  local disabled = load_disabled()

  local entries = {}
  local seen_paths = {}

  for order, scope in ipairs(precedence) do
    local candidates = collect_for_scope(cfg, scope, root)
    for _, candidate in ipairs(candidates) do
      local normalized = config.normalize_path(candidate.path)
      if normalized and not seen_paths[normalized] then
        seen_paths[normalized] = true

        local content = read_text(normalized)
        entries[#entries + 1] = {
          id = string.format("%s:%s", scope, candidate.name),
          scope = scope,
          order = order,
          name = candidate.name,
          path = normalized,
          exists = content ~= nil,
          bytes = content and content.bytes or 0,
          chars = content and content.chars or 0,
          content = content and content.content or "",
          disabled = disabled[normalized] == true,
        }
      end
    end
  end

  table.sort(entries, function(a, b)
    if a.order == b.order then
      return a.name < b.name
    end
    return a.order < b.order
  end)

  return {
    root = root,
    precedence = precedence,
    sources = entries,
    known_files = vim.tbl_values(default_file_set),
    disabled_map = disabled,
  }
end

function M.merge(opts)
  local report = M.collect(opts)
  local merged = {}

  for _, source in ipairs(report.sources) do
    if source.exists and source.content ~= "" and source.disabled ~= true then
      merged[#merged + 1] = string.format("[%s] %s", source.scope, source.path)
      merged[#merged + 1] = source.content
      merged[#merged + 1] = ""
    end
  end

  report.merged_text = table.concat(merged, "\n")
  report.total_bytes = 0
  report.total_chars = 0
  report.disabled_count = 0

  for _, source in ipairs(report.sources) do
    if source.disabled then
      report.disabled_count = report.disabled_count + 1
    end
    if source.exists and source.disabled ~= true then
      report.total_bytes = report.total_bytes + source.bytes
      report.total_chars = report.total_chars + source.chars
    end
  end

  return report
end

function M.describe_lines(opts)
  local report = M.merge(opts)
  local lines = {
    "Jig Agent Instructions",
    string.rep("=", 48),
    "root: " .. tostring(report.root),
    "precedence: " .. table.concat(report.precedence, " > "),
    string.format("totals: %d bytes, %d chars", report.total_bytes, report.total_chars),
    "disabled sources: " .. tostring(report.disabled_count),
    "",
    "sources:",
  }

  for _, source in ipairs(report.sources) do
    local status = source.exists and "loaded" or "missing"
    if source.disabled then
      status = "disabled"
    end
    lines[#lines + 1] =
      string.format("- [%s] %s (%s, %d bytes)", source.scope, source.path, status, source.bytes)
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] =
    "commands: :JigAgentInstructionDisable <source_id|path>, :JigAgentInstructionEnable <source_id|path>"

  return lines, report
end

function M.disable(identifier, opts)
  return toggle_source(identifier, true, opts)
end

function M.enable(identifier, opts)
  return toggle_source(identifier, false, opts)
end

function M.path()
  return state.path(disabled_file())
end

function M.reset_for_test()
  state.delete(disabled_file())
end

return M
