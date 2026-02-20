local config = require("jig.nav.config")
local guardrails = require("jig.nav.guardrails")

local M = {}

local function normalize(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local expanded = vim.fn.fnamemodify(path, ":p")
  local real = vim.uv.fs_realpath(expanded)
  return (real or expanded):gsub("/+$", "")
end

local function is_within_root(path, root)
  local normalized = normalize(path)
  if not normalized then
    return false
  end
  return normalized == root or vim.startswith(normalized, root .. "/")
end

local function split_lines(text)
  if type(text) ~= "string" or text == "" then
    return {}
  end
  local lines = vim.split(text, "\n", { plain = true, trimempty = true })
  table.sort(lines)
  return lines
end

local function system_lines(args, opts)
  local result = vim.system(args, opts or { text = true }):wait(4000)
  if result.code ~= 0 then
    return nil
  end
  return split_lines(result.stdout)
end

local function pick_with_ui(items, opts)
  if opts.select == false then
    return { selected = nil, shown = false }
  end

  if #items == 0 then
    return { selected = nil, shown = false }
  end

  if #vim.api.nvim_list_uis() == 0 then
    return { selected = items[1], shown = false }
  end

  vim.ui.select(items, {
    prompt = opts.prompt,
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice and opts.on_choice then
      opts.on_choice(choice)
    end
  end)

  return { selected = nil, shown = true }
end

local function from_relative_lines(lines, root, cap)
  local items = {}
  for _, line in ipairs(lines) do
    local rel = line:gsub("^%./", "")
    if rel ~= "" then
      table.insert(items, {
        label = rel,
        value = rel,
        abs = normalize(root .. "/" .. rel),
      })
    end
  end

  table.sort(items, function(a, b)
    return a.label < b.label
  end)

  return guardrails.cap_items(items, cap)
end

local function files_from_walk(root, cap, opts)
  local ignore = {}
  for _, glob in ipairs(opts.ignore_globs or {}) do
    local cleaned = glob:gsub("^!", "")
    cleaned = cleaned:gsub("/%*.*$", "")
    if cleaned ~= "" then
      ignore[cleaned] = true
    end
  end

  local out = {}
  local function walk(dir)
    if #out >= cap then
      return
    end

    local entries = {}
    for name, kind in vim.fs.dir(dir) do
      table.insert(entries, { name = name, kind = kind })
    end

    table.sort(entries, function(a, b)
      return a.name < b.name
    end)

    for _, entry in ipairs(entries) do
      if #out >= cap then
        break
      end
      local full = dir .. "/" .. entry.name
      local rel = full:sub(#root + 2)
      if entry.kind == "directory" then
        if not ignore[entry.name] then
          walk(full)
        end
      elseif entry.kind == "file" then
        table.insert(out, {
          label = rel,
          value = rel,
          abs = full,
        })
      end
    end
  end

  walk(root)
  return out, false
end

function M.list_files(root, opts)
  local cfg = opts or config.get()
  local cap = cfg.cap or guardrails.effective_cap(root, cfg).cap

  local lines
  if guardrails.is_git_repo(root) then
    lines = system_lines({ "git", "-C", root, "ls-files", "-co", "--exclude-standard" })
  end

  if not lines and vim.fn.executable("rg") == 1 then
    local args = { "rg", "--files" }
    vim.list_extend(args, guardrails.rg_glob_args(cfg))
    lines = system_lines(args, { cwd = root, text = true })
  end

  if lines then
    return from_relative_lines(lines, root, cap)
  end

  return files_from_walk(root, cap, cfg)
end

function M.pick_files(root, opts)
  local cfg = opts or config.get()
  local cap = cfg.cap or guardrails.effective_cap(root, cfg).cap
  local items, truncated = M.list_files(root, vim.tbl_extend("force", cfg, { cap = cap }))
  local selection = pick_with_ui(items, {
    select = cfg.select,
    prompt = "Jig files",
    on_choice = function(choice)
      vim.cmd("edit " .. vim.fn.fnameescape(choice.abs))
    end,
  })

  return {
    backend = "fallback",
    action = "files",
    root = root,
    count = #items,
    cap = cap,
    truncated = truncated,
    selection = selection,
  }
end

function M.pick_buffers(root, opts)
  local cfg = opts or config.get()
  local entries = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_loaded(bufnr)
      and vim.api.nvim_get_option_value("buflisted", { buf = bufnr })
    then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name == "" then
        table.insert(entries, {
          label = "[No Name] #" .. bufnr,
          bufnr = bufnr,
        })
      elseif is_within_root(name, root) then
        table.insert(entries, {
          label = vim.fn.fnamemodify(name, ":."),
          bufnr = bufnr,
        })
      end
    end
  end

  table.sort(entries, function(a, b)
    return a.label < b.label
  end)

  local items = guardrails.cap_items(entries, cfg.candidate_cap)
  local selection = pick_with_ui(items, {
    select = cfg.select,
    prompt = "Jig buffers",
    on_choice = function(choice)
      vim.api.nvim_set_current_buf(choice.bufnr)
    end,
  })

  return {
    backend = "fallback",
    action = "buffers",
    root = root,
    count = #items,
    cap = cfg.candidate_cap,
    selection = selection,
  }
end

function M.pick_recent(root, opts)
  local cfg = opts or config.get()
  local entries = {}

  for _, path in ipairs(vim.v.oldfiles or {}) do
    if path ~= "" and vim.fn.filereadable(path) == 1 and is_within_root(path, root) then
      table.insert(entries, {
        label = vim.fn.fnamemodify(path, ":."),
        path = path,
      })
    end
  end

  local items = guardrails.cap_items(entries, cfg.candidate_cap)
  local selection = pick_with_ui(items, {
    select = cfg.select,
    prompt = "Jig recent",
    on_choice = function(choice)
      vim.cmd("edit " .. vim.fn.fnameescape(choice.path))
    end,
  })

  return {
    backend = "fallback",
    action = "recent",
    root = root,
    count = #items,
    cap = cfg.candidate_cap,
    selection = selection,
  }
end

function M.pick_symbols(root, opts)
  local _ = root
  local cfg = opts or config.get()
  local clients = vim.lsp.get_clients({ bufnr = 0 })
  if #clients == 0 then
    vim.notify("No LSP symbols available for current buffer", vim.log.levels.INFO)
    return {
      backend = "fallback",
      action = "symbols",
      root = root,
      count = 0,
      cap = cfg.candidate_cap,
      selection = { selected = nil, shown = false },
    }
  end

  vim.lsp.buf.document_symbol()
  return {
    backend = "fallback",
    action = "symbols",
    root = root,
    count = 0,
    cap = cfg.candidate_cap,
    selection = { selected = nil, shown = true },
  }
end

function M.pick_diagnostics(root, opts)
  local cfg = opts or config.get()
  local diagnostics = {}
  for _, item in ipairs(vim.diagnostic.get()) do
    local name = vim.api.nvim_buf_get_name(item.bufnr)
    if name ~= "" and is_within_root(name, root) then
      table.insert(diagnostics, {
        label = string.format(
          "%s:%d %s",
          vim.fn.fnamemodify(name, ":."),
          item.lnum + 1,
          item.message
        ),
        bufnr = item.bufnr,
        lnum = item.lnum,
      })
    end
  end

  local items = guardrails.cap_items(diagnostics, cfg.candidate_cap)
  local selection = pick_with_ui(items, {
    select = cfg.select,
    prompt = "Jig diagnostics",
    on_choice = function(choice)
      vim.api.nvim_set_current_buf(choice.bufnr)
      vim.api.nvim_win_set_cursor(0, { choice.lnum + 1, 0 })
    end,
  })

  if cfg.select ~= false and #items == 0 then
    vim.diagnostic.setloclist({ open = true })
  end

  return {
    backend = "fallback",
    action = "diagnostics",
    root = root,
    count = #items,
    cap = cfg.candidate_cap,
    selection = selection,
  }
end

function M.pick_history(root, opts)
  local _ = root
  local cfg = opts or config.get()
  local entries = {}

  for i = vim.fn.histnr("cmd"), 1, -1 do
    local item = vim.fn.histget("cmd", i)
    if type(item) == "string" and item ~= "" then
      table.insert(entries, {
        label = item,
        command = item,
      })
    end
    if #entries >= cfg.candidate_cap then
      break
    end
  end

  local selection = pick_with_ui(entries, {
    select = cfg.select,
    prompt = "Jig command history",
    on_choice = function(choice)
      vim.cmd(choice.command)
    end,
  })

  return {
    backend = "fallback",
    action = "history",
    root = root,
    count = #entries,
    cap = cfg.candidate_cap,
    selection = selection,
  }
end

function M.pick_git_changes(root, opts)
  local cfg = opts or config.get()
  local lines = system_lines({ "git", "-C", root, "status", "--short" }) or {}
  local entries = {}

  for _, line in ipairs(lines) do
    local path = line:match("^..%s+(.+)$")
    if path and path ~= "" then
      table.insert(entries, {
        label = line,
        path = normalize(root .. "/" .. path),
      })
    end
  end

  local items = guardrails.cap_items(entries, cfg.candidate_cap)
  local selection = pick_with_ui(items, {
    select = cfg.select,
    prompt = "Jig git changes",
    on_choice = function(choice)
      if choice.path then
        vim.cmd("edit " .. vim.fn.fnameescape(choice.path))
      end
    end,
  })

  return {
    backend = "fallback",
    action = "git_changes",
    root = root,
    count = #items,
    cap = cfg.candidate_cap,
    selection = selection,
  }
end

return M
