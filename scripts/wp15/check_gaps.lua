#!/usr/bin/env -S nvim --headless -u NONE -l

local function parse_scalar(raw)
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
  if value:match('^".*"$') then
    return value:sub(2, -2)
  end
  return value
end

local function parse_gaps(path)
  if vim.fn.filereadable(path) ~= 1 then
    error("missing gaps file: " .. path)
  end

  local lines = vim.fn.readfile(path)
  local gaps = {}
  local current = nil

  for _, line in ipairs(lines) do
    if not line:match("^%s*#") and not line:match("^%s*$") then
      local key, raw = line:match("^%s*%-+%s*([%w_]+):%s*(.-)%s*$")
      if key ~= nil then
        current = {}
        gaps[#gaps + 1] = current
        current[key] = parse_scalar(raw)
      else
        local k, v = line:match("^%s*([%w_]+):%s*(.-)%s*$")
        if k and v and current ~= nil then
          current[k] = parse_scalar(v)
        end
      end
    end
  end

  return gaps
end

local function main()
  local root = vim.fn.getcwd()
  local path = root .. "/data/wp15/gaps.yaml"
  local gaps = parse_gaps(path)
  local errors = {}

  local valid_severity = {
    sev0 = true,
    sev1 = true,
    sev2 = true,
    sev3 = true,
  }

  for _, gap in ipairs(gaps) do
    local id = tostring(gap.id or "<missing-id>")
    local severity = tostring(gap.severity or "")
    local owner = tostring(gap.owner or "")
    local test_plan = tostring(gap.test_plan or "")
    local surface = tostring(gap.failure_surface or "")

    if id == "<missing-id>" then
      errors[#errors + 1] = "gap entry missing id"
    end

    if not valid_severity[severity] then
      errors[#errors + 1] = id .. ": invalid severity '" .. severity .. "'"
    end

    if surface == "" then
      errors[#errors + 1] = id .. ": missing failure_surface"
    end

    if severity == "sev0" or severity == "sev1" then
      if owner == "" or owner == "unassigned" then
        errors[#errors + 1] = id .. ": high-severity gap missing owner"
      end
      if test_plan == "" then
        errors[#errors + 1] = id .. ": high-severity gap missing test_plan"
      end
    end
  end

  if #errors > 0 then
    for _, err in ipairs(errors) do
      vim.api.nvim_err_writeln("wp15 gaps check failed: " .. err)
    end
    vim.cmd("cquit 1")
    return
  end

  print("wp15 gaps check passed: gaps=" .. tostring(#gaps))
  vim.cmd("qa")
end

local ok, err = pcall(main)
if not ok then
  vim.api.nvim_err_writeln("wp15 gaps check runtime error: " .. tostring(err))
  vim.cmd("cquit 1")
end
