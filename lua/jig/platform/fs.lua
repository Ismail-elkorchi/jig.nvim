local path = require("jig.platform.path")

local M = {}

function M.cwd(opts)
  opts = opts or {}
  local current = vim.uv.cwd() or vim.fn.getcwd()
  if opts.slash == true then
    return path.normalize(current, { slash = true, expand = false })
  end
  return path.normalize(current, { slash = false, expand = false })
end

function M.realpath(value, opts)
  opts = opts or {}
  local normalized = path.normalize(value, { slash = true })
  local real = vim.uv.fs_realpath(normalized)
  if real == nil then
    return ""
  end
  if opts.slash == true then
    return path.to_slash(real)
  end
  return path.from_slash(real)
end

function M.exists(value)
  if type(value) ~= "string" or value == "" then
    return false
  end
  local stat = vim.uv.fs_stat(value)
  return stat ~= nil
end

function M.is_dir(value)
  local stat = vim.uv.fs_stat(value)
  return stat ~= nil and stat.type == "directory"
end

function M.is_file(value)
  local stat = vim.uv.fs_stat(value)
  return stat ~= nil and stat.type == "file"
end

function M.stdpaths()
  return {
    config = vim.fn.stdpath("config"),
    data = vim.fn.stdpath("data"),
    state = vim.fn.stdpath("state"),
    cache = vim.fn.stdpath("cache"),
  }
end

return M
