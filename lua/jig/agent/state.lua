local config = require("jig.agent.config")

local M = {}

local function ensure_dir(path)
  vim.fn.mkdir(path, "p")
end

local function state_file(name)
  local dir = config.state_dir()
  ensure_dir(dir)
  return dir .. "/" .. name
end

local function read_file(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  local lines = vim.fn.readfile(path)
  return table.concat(lines, "\n")
end

local function write_file(path, content)
  ensure_dir(vim.fn.fnamemodify(path, ":h"))
  return pcall(
    vim.fn.writefile,
    vim.split(content, "\n", { plain = true, trimempty = false }),
    path
  )
end

function M.path(name)
  return state_file(name)
end

function M.read_json(name, fallback)
  local path = state_file(name)
  local payload = read_file(path)
  if payload == nil or payload == "" then
    return vim.deepcopy(fallback)
  end

  local ok, decoded = pcall(vim.json.decode, payload)
  if not ok or type(decoded) ~= "table" then
    return vim.deepcopy(fallback)
  end
  return decoded
end

function M.write_json(name, payload)
  local path = state_file(name)
  local encoded = vim.json.encode(payload)
  local ok, err = write_file(path, encoded)
  if not ok then
    return false, tostring(err)
  end
  return true, path
end

function M.append_jsonl(name, payload)
  local path = state_file(name)
  ensure_dir(vim.fn.fnamemodify(path, ":h"))
  local encoded = vim.json.encode(payload)
  local ok, err = pcall(vim.fn.writefile, { encoded }, path, "a")
  if not ok then
    return false, tostring(err)
  end
  return true, path
end

function M.tail_jsonl(name, limit)
  local path = state_file(name)
  if vim.fn.filereadable(path) ~= 1 then
    return {}
  end

  local lines = vim.fn.readfile(path)
  local from = math.max(1, #lines - (limit or 50) + 1)
  local items = {}
  for i = from, #lines do
    local line = lines[i]
    if line and line ~= "" then
      local ok, decoded = pcall(vim.json.decode, line)
      if ok and type(decoded) == "table" then
        table.insert(items, decoded)
      end
    end
  end
  return items
end

function M.reset(name, payload)
  return M.write_json(name, payload)
end

function M.delete(name)
  local path = state_file(name)
  if vim.fn.filereadable(path) == 1 then
    vim.fn.delete(path)
  end
end

return M
