local brand = require("jig.core.brand")

local M = {}

local CHANNEL_KEY = brand.namespace .. "_channel"
local DEFAULT_CHANNEL = "stable"
local ALLOWED = {
  stable = true,
  edge = true,
}

local function normalize(channel)
  if type(channel) ~= "string" then
    return nil
  end
  local value = vim.trim(channel):lower()
  if value == "" then
    return nil
  end
  return value
end

function M.path()
  return vim.fn.stdpath("state") .. "/jig/channel.json"
end

function M.default()
  return DEFAULT_CHANNEL
end

function M.valid(channel)
  local normalized = normalize(channel)
  return normalized ~= nil and ALLOWED[normalized] == true
end

function M.current()
  local configured = normalize(vim.g[CHANNEL_KEY])
  if configured ~= nil and ALLOWED[configured] == true then
    return configured
  end
  return DEFAULT_CHANNEL
end

local function write_channel(path, channel)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode({ channel = channel }) }, path)
end

function M.persist(channel)
  local normalized = normalize(channel)
  if normalized == nil or ALLOWED[normalized] ~= true then
    return false, "invalid_channel"
  end

  local path = M.path()
  local ok, err = pcall(write_channel, path, normalized)
  if not ok then
    return false, tostring(err)
  end

  return true, path
end

function M.set(channel, opts)
  local normalized = normalize(channel)
  if normalized == nil or ALLOWED[normalized] ~= true then
    return false, "invalid_channel"
  end

  vim.g[CHANNEL_KEY] = normalized

  local persist = opts == nil or opts.persist ~= false
  if not persist then
    return true, {
      channel = normalized,
      path = M.path(),
      source = "memory",
    }
  end

  local ok, value = M.persist(normalized)
  if not ok then
    return false, value
  end

  return true, {
    channel = normalized,
    path = value,
    source = "state",
  }
end

function M.load()
  local path = M.path()
  if vim.fn.filereadable(path) ~= 1 then
    return {
      channel = DEFAULT_CHANNEL,
      source = "default",
      path = path,
    }
  end

  local content = table.concat(vim.fn.readfile(path), "\n")
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    return {
      channel = DEFAULT_CHANNEL,
      source = "default",
      path = path,
      error = "invalid_json",
    }
  end

  local channel = normalize(decoded.channel)
  if channel == nil or ALLOWED[channel] ~= true then
    return {
      channel = DEFAULT_CHANNEL,
      source = "default",
      path = path,
      error = "invalid_channel",
    }
  end

  return {
    channel = channel,
    source = "state",
    path = path,
  }
end

function M.initialize()
  local loaded = M.load()
  vim.g[CHANNEL_KEY] = loaded.channel
  return loaded
end

return M
