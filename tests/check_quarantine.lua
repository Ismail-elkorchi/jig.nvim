local function repo_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h")
end

local ROOT = repo_root()

local function read_json(path)
  local lines = vim.fn.readfile(path)
  local ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok or type(decoded) ~= "table" then
    error("invalid json: " .. path)
  end
  return decoded
end

local function to_set(input)
  local set = {}
  if type(input) ~= "table" then
    return set
  end
  for key, _ in pairs(input) do
    set[tostring(key)] = true
  end
  return set
end

local function has_label(labels, needle)
  if type(labels) ~= "table" then
    return false
  end
  for _, label in ipairs(labels) do
    if label == needle then
      return true
    end
  end
  return false
end

local function find_snapshots()
  local paths = vim.fn.globpath(ROOT .. "/tests", "*/snapshots/latest-headless.json", false, true)
  table.sort(paths)
  return paths
end

local function suite_name(snapshot_path)
  local parent = vim.fn.fnamemodify(snapshot_path, ":h:h:t")
  return parent
end

local function main()
  local quarantine = read_json(ROOT .. "/tests/quarantine.json")
  local allow = to_set(quarantine.timing_sensitive_allowlist)

  local discovered = {}
  for _, snapshot in ipairs(find_snapshots()) do
    local suite = suite_name(snapshot)
    local payload = read_json(snapshot)
    for case_id, info in pairs(payload.cases or {}) do
      if has_label(info.labels, "timing-sensitive") then
        local key = suite .. ":" .. case_id
        discovered[key] = true
        if not allow[key] then
          error("timing-sensitive case not allowlisted: " .. key)
        end
      end
    end
  end

  for key, _ in pairs(allow) do
    if not discovered[key] then
      error("stale timing-sensitive allowlist entry: " .. key)
    end
  end

  local ordered = vim.tbl_keys(discovered)
  table.sort(ordered)
  print("quarantine allowlist validated")
  for _, key in ipairs(ordered) do
    print(" - " .. key)
  end
end

local ok, err = pcall(main)
if not ok then
  vim.api.nvim_err_writeln(tostring(err))
  vim.cmd("cquit 1")
end

vim.cmd("qa")
