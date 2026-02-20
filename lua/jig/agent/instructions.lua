local config = require("jig.agent.config")

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
    table.insert(out, {
      scope = "project",
      name = name,
      path = root .. "/" .. name,
    })
  end

  if type(cfg.instructions.project_extra) == "table" then
    for _, name in ipairs(cfg.instructions.project_extra) do
      table.insert(out, {
        scope = "project",
        name = name,
        path = root .. "/" .. name,
      })
    end
  end

  return out
end

local function path_candidates(scope, paths)
  local out = {}
  for _, item in ipairs(paths or {}) do
    local normalized = expand_path(item)
    if normalized then
      table.insert(out, {
        scope = scope,
        name = vim.fn.fnamemodify(normalized, ":t"),
        path = normalized,
      })
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

function M.collect(opts)
  local cfg = config.get(opts)
  local root = project_root(opts)
  local precedence = cfg.instructions.precedence or { "project", "user", "global" }

  local entries = {}
  local seen_paths = {}

  for order, scope in ipairs(precedence) do
    local candidates = collect_for_scope(cfg, scope, root)
    for _, candidate in ipairs(candidates) do
      local normalized = config.normalize_path(candidate.path)
      if normalized and not seen_paths[normalized] then
        seen_paths[normalized] = true

        local content = read_text(normalized)
        table.insert(entries, {
          id = string.format("%s:%s", scope, candidate.name),
          scope = scope,
          order = order,
          name = candidate.name,
          path = normalized,
          exists = content ~= nil,
          bytes = content and content.bytes or 0,
          chars = content and content.chars or 0,
          content = content and content.content or "",
        })
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
  }
end

function M.merge(opts)
  local report = M.collect(opts)
  local merged = {}

  for _, source in ipairs(report.sources) do
    if source.exists and source.content ~= "" then
      table.insert(merged, string.format("[%s] %s", source.scope, source.path))
      table.insert(merged, source.content)
      table.insert(merged, "")
    end
  end

  report.merged_text = table.concat(merged, "\n")
  report.total_bytes = 0
  report.total_chars = 0
  for _, source in ipairs(report.sources) do
    if source.exists then
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
    "",
    "sources:",
  }

  for _, source in ipairs(report.sources) do
    local status = source.exists and "loaded" or "missing"
    table.insert(
      lines,
      string.format("- [%s] %s (%s, %d bytes)", source.scope, source.path, status, source.bytes)
    )
  end

  return lines, report
end

return M
