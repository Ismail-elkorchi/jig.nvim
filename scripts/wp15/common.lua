local M = {}

local function join(...)
  local parts = { ... }
  local out = table.concat(parts, "/")
  return out:gsub("/+", "/")
end

function M.join(...)
  return join(...)
end

function M.exists(path)
  return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

function M.read_lines(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  return vim.fn.readfile(path)
end

function M.read_text(path)
  local lines = M.read_lines(path)
  if lines == nil then
    return nil
  end
  return table.concat(lines, "\n")
end

function M.write_text(path, content)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(vim.split(content, "\n", { plain = true }), path)
end

function M.parse_inline_array(raw)
  local value = vim.trim(raw or "")
  if not value:match("^%[") then
    return nil
  end
  local body = value:gsub("^%[", ""):gsub("%]$", "")
  local out = {}
  for token in body:gmatch("[^,]+") do
    local item = vim.trim(token)
    item = item:gsub("^\"", ""):gsub("\"$", "")
    if item ~= "" then
      out[#out + 1] = item
    end
  end
  return out
end

function M.parse_scalar(raw)
  local value = vim.trim(raw or "")
  if value == "true" then
    return true
  end
  if value == "false" then
    return false
  end
  if value == "null" then
    return vim.NIL
  end
  if value:match("^%-?%d+$") then
    return tonumber(value)
  end
  if value:match("^%-?%d+%.%d+$") then
    return tonumber(value)
  end
  if value:match("^\".*\"$") then
    return value:sub(2, -2)
  end
  return value
end

function M.parse_yaml_list(path)
  local lines = assert(M.read_lines(path), "missing yaml file: " .. path)
  local out = {}
  local current = nil

  for _, line in ipairs(lines) do
    if not line:match("^%s*#") and not line:match("^%s*$") then
      local key, raw = line:match("^%s*%-+%s*([%w_]+):%s*(.-)%s*$")
      if key ~= nil then
        current = {}
        out[#out + 1] = current
        local arr = M.parse_inline_array(raw)
        current[key] = arr ~= nil and arr or M.parse_scalar(raw)
      else
        local k, v = line:match("^%s*([%w_]+):%s*(.-)%s*$")
        if k and v and current ~= nil then
          local arr = M.parse_inline_array(v)
          current[k] = arr ~= nil and arr or M.parse_scalar(v)
        end
      end
    end
  end

  return out
end

function M.parse_yaml_map(path)
  local lines = assert(M.read_lines(path), "missing yaml map file: " .. path)
  local out = {}

  for _, line in ipairs(lines) do
    if not line:match("^%s*#") and not line:match("^%s*$") then
      local key, raw = line:match("^%s*([%w_]+):%s*(.-)%s*$")
      if key and raw then
        local arr = M.parse_inline_array(raw)
        out[key] = arr ~= nil and arr or M.parse_scalar(raw)
      end
    end
  end

  return out
end

function M.date_to_epoch_days(raw)
  if type(raw) ~= "string" then
    return nil
  end

  local year, month, day = raw:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if year == nil then
    return nil
  end

  local ts = os.time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = 12,
    min = 0,
    sec = 0,
  })
  if type(ts) ~= "number" then
    return nil
  end
  return math.floor(ts / 86400)
end

function M.parse_json(path)
  local text = assert(M.read_text(path), "missing json file: " .. path)
  local ok, decoded = pcall(vim.json.decode, text)
  assert(ok and type(decoded) == "table", "invalid json file: " .. path)
  return decoded
end

function M.parse_jsonl(path)
  local lines = assert(M.read_lines(path), "missing jsonl file: " .. path)
  local out = {}
  for _, line in ipairs(lines) do
    local trimmed = vim.trim(line)
    if trimmed ~= "" then
      local ok, decoded = pcall(vim.json.decode, trimmed)
      assert(ok and type(decoded) == "table", "invalid jsonl line in " .. path)
      out[#out + 1] = decoded
    end
  end
  return out
end

function M.sorted_keys(map)
  local keys = {}
  for key, _ in pairs(map or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

local function has_wp15_dataset(path)
  return M.exists(join(path, "data/wp15/baselines.yaml"))
    and M.exists(join(path, "data/wp15/evidence.jsonl"))
end

local function upward_candidates(path)
  local out = {}
  local current = vim.fn.fnamemodify(path, ":p")
  if current == "" then
    return out
  end
  if vim.fn.isdirectory(current) ~= 1 then
    current = vim.fn.fnamemodify(current, ":h")
  end

  while current and current ~= "" do
    out[#out + 1] = current
    local parent = vim.fn.fnamemodify(current, ":h")
    if parent == current then
      break
    end
    current = parent
  end
  return out
end

function M.repo_root()
  if type(_G.__jig_repo_root) == "string" and _G.__jig_repo_root ~= "" then
    return _G.__jig_repo_root
  end

  local source = debug.getinfo(2, "S").source
  if type(source) == "string" and vim.startswith(source, "@") then
    source = source:sub(2)
  else
    source = nil
  end

  local candidates = {}
  if type(source) == "string" and source ~= "" then
    for _, path in ipairs(upward_candidates(source)) do
      candidates[#candidates + 1] = path
    end
  end
  for _, path in ipairs(upward_candidates(vim.fn.getcwd())) do
    candidates[#candidates + 1] = path
  end

  local seen = {}
  for _, path in ipairs(candidates) do
    if seen[path] ~= true then
      seen[path] = true
      if has_wp15_dataset(path) then
        return path
      end
    end
  end

  error("unable to resolve repository root")
end

return M
