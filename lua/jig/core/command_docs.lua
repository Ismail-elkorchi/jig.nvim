local brand = require("jig.core.brand")

local M = {}

local function repo_root()
  if type(_G.__jig_repo_root) == "string" and _G.__jig_repo_root ~= "" then
    return _G.__jig_repo_root
  end
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h:h:h")
end

local function read_or_empty(path)
  local fd = vim.uv.fs_open(path, "r", 420)
  if not fd then
    return ""
  end
  local stat = vim.uv.fs_fstat(fd)
  local data = vim.uv.fs_read(fd, stat.size, 0) or ""
  vim.uv.fs_close(fd)
  return data
end

local function normalize_newlines(value)
  return tostring(value or ""):gsub("\r\n", "\n")
end

local function write(path, content)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local fd = assert(vim.uv.fs_open(path, "w", 420))
  assert(vim.uv.fs_write(fd, content, 0))
  assert(vim.uv.fs_close(fd))
end

local function map_nargs(value)
  local table_map = {
    ["0"] = "none",
    ["1"] = "one",
    ["?"] = "optional-one",
    ["+"] = "one-or-more",
    ["*"] = "zero-or-more",
  }
  return table_map[tostring(value)] or tostring(value)
end

function M.collect_commands()
  local commands = vim.api.nvim_get_commands({ builtin = false })
  local out = {}

  for name, spec in pairs(commands) do
    if name:match("^" .. brand.brand) then
      out[#out + 1] = {
        name = name,
        definition = tostring(spec.definition or ""),
        nargs = map_nargs(spec.nargs),
        bang = spec.bang == true,
        bar = spec.bar == true,
      }
    end
  end

  table.sort(out, function(a, b)
    return a.name < b.name
  end)

  return out
end

function M.render_markdown(entries)
  local lines = {
    "# commands.jig.nvim.md",
    "",
    "Generated from the default runtime command surface. Do not edit manually.",
    "",
    "| Command | Args | Bang | Description |",
    "|---|---|---|---|",
  }

  for _, entry in ipairs(entries) do
    lines[#lines + 1] = string.format(
      "| `:%s` | `%s` | `%s` | %s |",
      entry.name,
      entry.nargs,
      entry.bang and "yes" or "no",
      entry.definition ~= "" and entry.definition or "(no description)"
    )
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "Canonical help: `:help jig-commands`"
  lines[#lines + 1] = ""

  return table.concat(lines, "\n") .. "\n"
end

function M.render_vimdoc(entries)
  local lines = {
    "*jig-commands*  Jig command index",
    "",
    "Generated from the default runtime command surface. Do not edit manually.",
    "",
    "COMMANDS",
  }

  for _, entry in ipairs(entries) do
    lines[#lines + 1] =
      string.format("  :%-18s %-12s %s", entry.name, entry.nargs, entry.definition)
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "BOUNDARIES"
  lines[#lines + 1] = "  This file covers default-profile commands. Optional agent commands are"
  lines[#lines + 1] = "  documented in |jig-agents| when agent module is explicitly enabled."
  lines[#lines + 1] = ""
  lines[#lines + 1] = "vim:tw=78:ts=8:noet:ft=help:norl:"

  return table.concat(lines, "\n") .. "\n"
end

function M.generate(opts)
  opts = opts or {}

  local entries = opts.entries or M.collect_commands()
  local root = repo_root()

  local markdown_path = root .. "/docs/commands.jig.nvim.md"
  local vimdoc_path = root .. "/doc/jig-commands.txt"

  local markdown = M.render_markdown(entries)
  local vimdoc = M.render_vimdoc(entries)

  if opts.check then
    local current_markdown = normalize_newlines(read_or_empty(markdown_path))
    local current_vimdoc = normalize_newlines(read_or_empty(vimdoc_path))
    local expected_markdown = normalize_newlines(markdown)
    local expected_vimdoc = normalize_newlines(vimdoc)

    if current_markdown ~= expected_markdown then
      error("docs/commands.jig.nvim.md is out of sync with runtime command surface")
    end

    if current_vimdoc ~= expected_vimdoc then
      error("doc/jig-commands.txt is out of sync with runtime command surface")
    end

    return true
  end

  write(markdown_path, markdown)
  write(vimdoc_path, vimdoc)

  return {
    markdown_path = markdown_path,
    vimdoc_path = vimdoc_path,
    entries = #entries,
  }
end

return M
