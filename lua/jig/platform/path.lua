local os_platform = require("jig.platform.os")
local unpack_values = table.unpack or unpack

local M = {}

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function M.separator()
  return os_platform.is_windows() and "\\" or "/"
end

function M.to_slash(path)
  return trim(path):gsub("\\", "/")
end

function M.from_slash(path)
  if not os_platform.is_windows() then
    return M.to_slash(path)
  end
  return M.to_slash(path):gsub("/", "\\")
end

function M.is_absolute(path)
  local value = trim(path)
  if value == "" then
    return false
  end

  if os_platform.is_windows() then
    return value:match("^%a:[/\\]") ~= nil or value:match("^[/\\][/\\]") ~= nil
  end

  return value:sub(1, 1) == "/"
end

function M.normalize(path, opts)
  opts = opts or {}
  local value = M.to_slash(path)
  if value == "" then
    return ""
  end

  if opts.expand ~= false then
    value = vim.fn.fnamemodify(value, ":p")
    value = M.to_slash(value)
  end

  local real = vim.uv.fs_realpath(value)
  if real ~= nil and real ~= "" then
    value = M.to_slash(real)
  end

  value = value:gsub("/+$", "")
  if os_platform.is_windows() and value:match("^%a:$") then
    value = value .. "/"
  end

  if opts.slash == true then
    return value
  end
  return M.from_slash(value)
end

function M.join(...)
  local values = {}
  for _, value in ipairs({ ... }) do
    local token = trim(value)
    if token ~= "" then
      values[#values + 1] = token
    end
  end

  if #values == 0 then
    return ""
  end

  local joined = vim.fs.joinpath(unpack_values(values))
  if os_platform.is_windows() then
    return M.from_slash(joined)
  end
  return M.to_slash(joined)
end

function M.basename(path)
  local value = M.to_slash(path)
  if value == "" then
    return ""
  end
  return value:match("([^/]+)$") or value
end

function M.dirname(path)
  local value = M.to_slash(path)
  if value == "" then
    return ""
  end
  local parent = value:match("^(.*)/[^/]*$") or ""
  if parent == "" and value:match("^%a:[/]?$") then
    parent = value
  end
  return M.from_slash(parent)
end

return M
