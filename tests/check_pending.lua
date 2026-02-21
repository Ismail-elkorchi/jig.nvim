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

local function is_pending(entry)
  if type(entry) ~= "table" then
    return false
  end
  if entry.status == "pending" then
    return true
  end
  if type(entry.details) == "table" and entry.details.status == "pending" then
    return true
  end
  return false
end

local function main()
  local allow = read_json(ROOT .. "/tests/pending_tests.json")
  local allow_set = to_set(allow.allowed_pending)

  local snapshot = read_json(ROOT .. "/tests/pending/snapshots/latest-headless.json")
  local discovered = {}

  for case_id, entry in pairs(snapshot.cases or {}) do
    if is_pending(entry) then
      discovered[case_id] = true
      if not allow_set[case_id] then
        error("pending case not allowlisted: " .. case_id)
      end
    end
  end

  for case_id, _ in pairs(allow_set) do
    if not discovered[case_id] then
      error("stale pending allowlist entry: " .. case_id)
    end
  end

  local keys = vim.tbl_keys(discovered)
  table.sort(keys)
  print("pending allowlist validated")
  for _, key in ipairs(keys) do
    print(" - " .. key)
  end
end

local ok, err = pcall(main)
if not ok then
  vim.api.nvim_err_writeln(tostring(err))
  vim.cmd("cquit 1")
end

vim.cmd("qa")
