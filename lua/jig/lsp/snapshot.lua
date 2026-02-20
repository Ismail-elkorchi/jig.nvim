local diagnostics_policy = require("jig.lsp.diagnostics")
local format_on_save = require("jig.lsp.format_on_save")
local inlay_hints = require("jig.lsp.inlay_hints")
local lifecycle = require("jig.lsp.lifecycle")

local M = {}

local severity_name = {
  [vim.diagnostic.severity.ERROR] = "error",
  [vim.diagnostic.severity.WARN] = "warn",
  [vim.diagnostic.severity.INFO] = "info",
  [vim.diagnostic.severity.HINT] = "hint",
}

local function diagnostics_count(bufnr)
  local counters = {
    total = 0,
    error = 0,
    warn = 0,
    info = 0,
    hint = 0,
  }

  for _, item in ipairs(vim.diagnostic.get(bufnr)) do
    counters.total = counters.total + 1
    local key = severity_name[item.severity]
    if key then
      counters[key] = counters[key] + 1
    end
  end

  return counters
end

local function attached_clients(bufnr)
  local out = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    table.insert(out, {
      id = client.id,
      name = client.name,
      root_dir = client.config.root_dir,
    })
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

function M.capture(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

  return {
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    profile = vim.g.jig_profile,
    appname = vim.g.jig_appname,
    cwd = vim.uv.cwd(),
    bufnr = bufnr,
    buffer_name = vim.api.nvim_buf_get_name(bufnr),
    diagnostics = diagnostics_count(bufnr),
    attached_clients = attached_clients(bufnr),
    servers = lifecycle.state().servers,
    lifecycle = lifecycle.summary(),
    policies = {
      diagnostics = diagnostics_policy.state().policy,
      inlay_hints = inlay_hints.state(),
      format_on_save = format_on_save.state(),
    },
  }
end

function M.write(path, payload)
  local encoded = vim.json.encode(payload)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local ok, err = pcall(vim.fn.writefile, { encoded }, path)
  if not ok then
    return false, tostring(err)
  end
  return true, path
end

return M
