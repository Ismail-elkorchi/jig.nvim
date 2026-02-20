local registry = require("jig.core.keymap_registry")

local M = {}

local function repo_root()
  if type(_G.__jig_repo_root) == "string" and _G.__jig_repo_root ~= "" then
    return _G.__jig_repo_root
  end
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h:h:h")
end

local function grouped(entries)
  local groups = {}
  for _, entry in ipairs(entries or {}) do
    local discoverability = entry.discoverability or {}
    if discoverability.hidden ~= true then
      local group = discoverability.group or entry.layer or "Other"
      groups[group] = groups[group] or {}
      table.insert(groups[group], entry)
    end
  end

  local order = vim.tbl_keys(groups)
  table.sort(order)

  for _, group in ipairs(order) do
    table.sort(groups[group], function(a, b)
      local left = (a.discoverability and a.discoverability.order) or 999
      local right = (b.discoverability and b.discoverability.order) or 999
      if left == right then
        return a.lhs < b.lhs
      end
      return left < right
    end)
  end

  return groups, order
end

function M.render_markdown(entries)
  local groups, order = grouped(entries)
  local lines = {
    "# keymaps.jig.nvim.md",
    "",
    "Generated from keymap registry. Do not edit manually.",
    "",
  }

  for _, group in ipairs(order) do
    table.insert(lines, "## " .. group)
    for _, entry in ipairs(groups[group]) do
      table.insert(lines, string.format("- `%s`: %s", entry.lhs, entry.desc))
    end
    table.insert(lines, "")
  end

  return table.concat(lines, "\n") .. "\n"
end

function M.render_vimdoc(entries)
  local groups, order = grouped(entries)
  local lines = {
    "*jig-keymaps*  Keymap Index",
    "",
    "Generated from keymap registry. Do not edit manually.",
    "",
    "COMMANDS",
    "  :JigKeys       Open keymap index panel",
    "",
    "KEYMAPS",
  }

  for _, group in ipairs(order) do
    table.insert(lines, "")
    table.insert(lines, group:upper())
    for _, entry in ipairs(groups[group]) do
      table.insert(lines, string.format("  %-14s %s", entry.lhs, entry.desc))
    end
  end

  table.insert(lines, "")
  table.insert(lines, "vim:tw=78:ts=8:noet:ft=help:norl:")

  return table.concat(lines, "\n") .. "\n"
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

local function write(path, content)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local fd = assert(vim.uv.fs_open(path, "w", 420))
  assert(vim.uv.fs_write(fd, content, 0))
  assert(vim.uv.fs_close(fd))
end

function M.generate(opts)
  opts = opts or {}
  local entries = opts.entries or registry.defaults({ safe_profile = false })
  local root = repo_root()

  local markdown_path = root .. "/docs/keymaps.jig.nvim.md"
  local vimdoc_path = root .. "/doc/jig-keymaps.txt"

  local markdown = M.render_markdown(entries)
  local vimdoc = M.render_vimdoc(entries)

  if opts.check then
    local current_markdown = read_or_empty(markdown_path)
    local current_vimdoc = read_or_empty(vimdoc_path)

    if current_markdown ~= markdown then
      error("docs/keymaps.jig.nvim.md is out of sync with keymap registry")
    end

    if current_vimdoc ~= vimdoc then
      error("doc/jig-keymaps.txt is out of sync with keymap registry")
    end

    return true
  end

  write(markdown_path, markdown)
  write(vimdoc_path, vimdoc)

  return {
    markdown_path = markdown_path,
    vimdoc_path = vimdoc_path,
  }
end

return M
