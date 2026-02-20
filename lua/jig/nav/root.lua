local cfg = require("jig.nav.config")

local M = {}

local function normalize(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  local expanded = vim.fn.fnamemodify(path, ":p")
  local real = vim.uv.fs_realpath(expanded)
  local normalized = real or expanded
  return normalized:gsub("/+$", "")
end

local function dedupe_markers(markers)
  local seen = {}
  local ordered = {}
  for _, marker in ipairs(markers or {}) do
    if type(marker) == "string" and marker ~= "" and not seen[marker] then
      seen[marker] = true
      table.insert(ordered, marker)
    end
  end
  return ordered
end

local function start_path(path)
  local provided = normalize(path)
  if provided then
    return provided
  end

  local current = normalize(vim.api.nvim_buf_get_name(0))
  if current then
    return current
  end

  return normalize(vim.uv.cwd())
end

local function from_markers(path, markers)
  local resolved = vim.fs.root(path, markers)
  if not resolved then
    return nil
  end
  return normalize(resolved)
end

function M.set(path)
  local root = normalize(path)
  if not root then
    return false, "root override path is empty"
  end
  if vim.fn.isdirectory(root) ~= 1 then
    return false, "root override must be a directory: " .. root
  end
  vim.g.jig_root_override = root
  return true, root
end

function M.reset()
  vim.g.jig_root_override = nil
end

function M.resolve(opts)
  opts = opts or {}

  local config = cfg.get()
  local markers = dedupe_markers(opts.markers or config.markers)
  local origin = start_path(opts.path)

  local env_override = normalize(vim.env.JIG_ROOT)
  if env_override then
    return {
      root = env_override,
      source = "env",
      markers = markers,
      origin = origin,
    }
  end

  local local_override = normalize(vim.g.jig_root_override)
  if local_override then
    return {
      root = local_override,
      source = "command",
      markers = markers,
      origin = origin,
    }
  end

  local marker_root = from_markers(origin, markers)
  if marker_root then
    return {
      root = marker_root,
      source = "markers",
      markers = markers,
      origin = origin,
    }
  end

  return {
    root = normalize(vim.uv.cwd()),
    source = "cwd",
    markers = markers,
    origin = origin,
  }
end

return M
