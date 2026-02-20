local config = require("jig.nav.config")
local fallback = require("jig.nav.fallback")
local guardrails = require("jig.nav.guardrails")

local M = {}

local picker_override = nil

local function picker()
  if picker_override ~= nil then
    return picker_override
  end

  local ok, snacks = pcall(require, "snacks")
  if not ok or type(snacks) ~= "table" or type(snacks.picker) ~= "table" then
    return nil
  end

  return snacks.picker
end

local function to_snacks_excludes(ignore_globs)
  local out = {}
  for _, glob in ipairs(ignore_globs or {}) do
    local clean = glob:gsub("^!", "")
    if clean ~= "" then
      table.insert(out, clean)
    end
  end
  return out
end

local function use_snacks(source, opts)
  local instance = picker()
  if not instance then
    return false, "snacks picker unavailable"
  end

  local fn = instance[source]
  if type(fn) ~= "function" then
    return false, "snacks picker source missing: " .. source
  end

  local ok, err = pcall(fn, opts)
  if not ok then
    return false, tostring(err)
  end

  return true, nil
end

local function fallback_with_log(method, root, opts, reason)
  vim.schedule(function()
    vim.notify(
      string.format("Jig navigation fallback used (%s): %s", method, reason),
      vim.log.levels.WARN
    )
  end)
  return fallback[method](root, opts)
end

function M._set_picker_for_test(mock)
  picker_override = mock
end

function M.files(context, opts)
  local cfg = config.get()
  local runtime = vim.tbl_deep_extend("force", cfg, opts or {})
  local cap_info = guardrails.effective_cap(context.root, runtime)
  runtime.cap = runtime.cap or cap_info.cap

  if runtime.select == false then
    return fallback.pick_files(context.root, runtime)
  end

  local ok, err = use_snacks("files", {
    cwd = context.root,
    hidden = false,
    ignored = false,
    follow = false,
    exclude = to_snacks_excludes(runtime.ignore_globs),
    limit = runtime.cap,
  })

  if ok then
    return {
      backend = "snacks",
      action = "files",
      root = context.root,
      cap = runtime.cap,
      large_repo = cap_info.large_repo,
      file_count = cap_info.file_count,
    }
  end

  return fallback_with_log("pick_files", context.root, runtime, err)
end

function M.buffers(context, opts)
  local cfg = config.get()
  local runtime = vim.tbl_deep_extend("force", cfg, opts or {})
  if runtime.select == false then
    return fallback.pick_buffers(context.root, runtime)
  end
  local ok, err = use_snacks("buffers", {
    cwd = context.root,
    limit = runtime.candidate_cap,
  })

  if ok then
    return {
      backend = "snacks",
      action = "buffers",
      root = context.root,
      cap = runtime.candidate_cap,
    }
  end

  return fallback_with_log("pick_buffers", context.root, runtime, err)
end

function M.recent(context, opts)
  local cfg = config.get()
  local runtime = vim.tbl_deep_extend("force", cfg, opts or {})
  if runtime.select == false then
    return fallback.pick_recent(context.root, runtime)
  end
  local ok, err = use_snacks("recent", {
    cwd = context.root,
    limit = runtime.candidate_cap,
  })

  if ok then
    return {
      backend = "snacks",
      action = "recent",
      root = context.root,
      cap = runtime.candidate_cap,
    }
  end

  return fallback_with_log("pick_recent", context.root, runtime, err)
end

function M.symbols(context, opts)
  local cfg = config.get()
  local runtime = vim.tbl_deep_extend("force", cfg, opts or {})
  if runtime.select == false then
    return fallback.pick_symbols(context.root, runtime)
  end
  local ok, err = use_snacks("lsp_symbols", {
    cwd = context.root,
    limit = runtime.candidate_cap,
  })

  if ok then
    return {
      backend = "snacks",
      action = "symbols",
      root = context.root,
      cap = runtime.candidate_cap,
    }
  end

  return fallback_with_log("pick_symbols", context.root, runtime, err)
end

function M.diagnostics(context, opts)
  local cfg = config.get()
  local runtime = vim.tbl_deep_extend("force", cfg, opts or {})
  if runtime.select == false then
    return fallback.pick_diagnostics(context.root, runtime)
  end
  local ok, err = use_snacks("diagnostics", {
    cwd = context.root,
    limit = runtime.candidate_cap,
  })

  if ok then
    return {
      backend = "snacks",
      action = "diagnostics",
      root = context.root,
      cap = runtime.candidate_cap,
    }
  end

  return fallback_with_log("pick_diagnostics", context.root, runtime, err)
end

function M.history(context, opts)
  local cfg = config.get()
  local runtime = vim.tbl_deep_extend("force", cfg, opts or {})
  if runtime.select == false then
    return fallback.pick_history(context.root, runtime)
  end
  local ok, err = use_snacks("command_history", {
    limit = runtime.candidate_cap,
  })

  if ok then
    return {
      backend = "snacks",
      action = "history",
      root = context.root,
      cap = runtime.candidate_cap,
    }
  end

  return fallback_with_log("pick_history", context.root, runtime, err)
end

function M.git_changes(context, opts)
  local cfg = config.get()
  local runtime = vim.tbl_deep_extend("force", cfg, opts or {})
  if runtime.select == false then
    return fallback.pick_git_changes(context.root, runtime)
  end
  local ok, err = use_snacks("git_status", {
    cwd = context.root,
    limit = runtime.candidate_cap,
  })

  if ok then
    return {
      backend = "snacks",
      action = "git_changes",
      root = context.root,
      cap = runtime.candidate_cap,
    }
  end

  return fallback_with_log("pick_git_changes", context.root, runtime, err)
end

return M
