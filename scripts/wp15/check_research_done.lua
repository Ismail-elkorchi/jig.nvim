#!/usr/bin/env -S nvim --headless -u NONE -l

local function join(...)
  local parts = { ... }
  local out = table.concat(parts, "/")
  return out:gsub("/+", "/")
end

local function exists(path)
  return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

local function has_wp15_dataset(path)
  return exists(join(path, "data/wp15/baselines.yaml")) and exists(join(path, "data/wp15/evidence.jsonl"))
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

local function repo_root()
  local source = debug.getinfo(1, "S").source
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

  error("unable to resolve repo root for wp15 dataset")
end

local ROOT = repo_root()

local function read_lines(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  return vim.fn.readfile(path)
end

local function parse_inline_array(raw)
  local value = vim.trim(raw or "")
  if not value:match("^%[") then
    return nil
  end
  local body = value:gsub("^%[", ""):gsub("%]$", "")
  local out = {}
  for token in body:gmatch("[^,]+") do
    local item = vim.trim(token)
    item = item:gsub('^"', ""):gsub('"$', "")
    if item ~= "" then
      out[#out + 1] = item
    end
  end
  return out
end

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
  if value:match('^".*"$') then
    return value:sub(2, -2)
  end
  return value
end

local function parse_baselines(path)
  local lines = assert(read_lines(path), "missing baselines file: " .. path)
  local baselines = {}
  local current = nil

  local function assign(key, raw)
    local arr = parse_inline_array(raw)
    if arr ~= nil then
      current[key] = arr
      return
    end
    current[key] = parse_scalar(raw)
  end

  for _, line in ipairs(lines) do
    local id = line:match("^%s*%-+%s*id:%s*(.-)%s*$")
    if id ~= nil then
      current = { id = parse_scalar(id) }
      baselines[#baselines + 1] = current
    else
      local key, raw = line:match("^%s*([%w_]+):%s*(.-)%s*$")
      if key and raw and current ~= nil then
        assign(key, raw)
      end
    end
  end

  return baselines
end

local function parse_jsonl(path)
  local lines = assert(read_lines(path), "missing evidence file: " .. path)
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

local function to_set(items)
  local set = {}
  for _, value in ipairs(items or {}) do
    set[value] = true
  end
  return set
end

local function domain(url)
  if type(url) ~= "string" then
    return nil
  end
  return url:match("^https?://([^/%?#]+)")
end

local function count_links(lines)
  local count = 0
  for _, line in ipairs(lines or {}) do
    for _ in tostring(line):gmatch("https?://[%w%-%._~:/%?#%[%]@!$&'()*+,;=]+") do
      count = count + 1
    end
  end
  return count
end

local function choose_dossier_path()
  local default_offrepo =
    "/home/ismail-el-korchi/Documents/Projects/tse-workbench/research/jig.nvim/wp-15/2026-02-25--wp-15-research-dossier.md"
  local preferred = vim.env.WP15_DOSSIER_PATH
  local candidates = {}
  if type(preferred) == "string" and preferred ~= "" then
    candidates[#candidates + 1] = preferred
  end
  candidates[#candidates + 1] = default_offrepo
  candidates[#candidates + 1] = ROOT .. "/data/wp15/disconfirming.md"

  for _, path in ipairs(candidates) do
    if type(path) == "string" and path ~= "" and vim.fn.filereadable(path) == 1 then
      return path
    end
  end
  return nil
end

local function fail(errors)
  for _, err in ipairs(errors) do
    vim.api.nvim_err_writeln("wp15 research check failed: " .. err)
  end
  vim.cmd("cquit 1")
end

local function main()
  local baselines_path = ROOT .. "/data/wp15/baselines.yaml"
  local evidence_path = ROOT .. "/data/wp15/evidence.jsonl"

  local baselines = parse_baselines(baselines_path)
  local evidence = parse_jsonl(evidence_path)

  local errors = {}

  -- R1 baseline coverage and tag requirements
  local nvim_count = 0
  local agent_count = 0
  local stability_ops = 0
  local minimal_starter = 0
  local agent_first = 0

  local by_id = {}
  for _, baseline in ipairs(baselines) do
    by_id[baseline.id] = baseline
    if baseline.category == "nvim_distro" or baseline.category == "nvim_starter" then
      nvim_count = nvim_count + 1
    end
    if
      baseline.category == "agent_cli"
      or baseline.category == "agent_editor"
      or baseline.category == "agent_protocol"
    then
      agent_count = agent_count + 1
    end

    local tags = to_set(baseline.positioning_tags or {})
    if tags.stability_ops then
      stability_ops = stability_ops + 1
    end
    if tags.minimal_starter then
      minimal_starter = minimal_starter + 1
    end
    if tags.agent_first then
      agent_first = agent_first + 1
    end
  end

  if nvim_count < 6 then
    errors[#errors + 1] = "R1 violation: fewer than 6 nvim baselines (" .. nvim_count .. ")"
  end
  if agent_count < 6 then
    errors[#errors + 1] = "R1 violation: fewer than 6 agent baselines (" .. agent_count .. ")"
  end
  if stability_ops < 2 then
    errors[#errors + 1] = "R1 violation: fewer than 2 stability_ops baselines (" .. stability_ops .. ")"
  end
  if minimal_starter < 2 then
    errors[#errors + 1] = "R1 violation: fewer than 2 minimal_starter baselines (" .. minimal_starter .. ")"
  end
  if agent_first < 2 then
    errors[#errors + 1] = "R1 violation: fewer than 2 agent_first baselines (" .. agent_first .. ")"
  end

  -- R2 pin completeness
  for _, baseline in ipairs(baselines) do
    if baseline.pinned_version == nil or baseline.pinned_version == "" then
      errors[#errors + 1] = "R2 violation: missing pinned_version for " .. tostring(baseline.id)
    end
    if baseline.pin_evidence_url == nil or baseline.pin_evidence_url == "" then
      errors[#errors + 1] = "R2 violation: missing pin_evidence_url for " .. tostring(baseline.id)
    end
    if baseline.qualitative_only == true then
      if baseline.pinned_version == nil or baseline.pinned_version == "" then
        errors[#errors + 1] =
          "R2 violation: qualitative_only baseline missing explicit version " .. tostring(baseline.id)
      end
    end
  end

  -- R3 evidence coverage and per-baseline minimums
  if #evidence < 40 then
    errors[#errors + 1] = "R3 violation: evidence count below 40 (" .. #evidence .. ")"
  end

  local ev_by_baseline = {}
  local domains = {}
  for _, item in ipairs(evidence) do
    local bid = item.baseline_id
    if bid ~= "general" then
      ev_by_baseline[bid] = ev_by_baseline[bid] or {}
      table.insert(ev_by_baseline[bid], item)
    end

    local d = domain(item.url)
    if d then
      domains[d] = true
    end
  end

  for _, baseline in ipairs(baselines) do
    local entries = ev_by_baseline[baseline.id] or {}
    if #entries < 3 then
      errors[#errors + 1] =
        "R3 violation: baseline has fewer than 3 evidence items: " .. tostring(baseline.id)
    end

    local official = 0
    local negative = 0
    for _, item in ipairs(entries) do
      if item.type == "official_doc" then
        official = official + 1
      end
      if item.polarity == "negative" and (item.type == "issue" or item.type == "discussion" or item.type == "security_writeup") then
        negative = negative + 1
      end
    end
    if official < 1 then
      errors[#errors + 1] = "R3 violation: no official_doc evidence for " .. tostring(baseline.id)
    end
    if negative < 1 then
      errors[#errors + 1] = "R3 violation: no negative issue/discussion/security evidence for " .. tostring(baseline.id)
    end
  end

  -- R4 evidence domain diversity
  local domain_count = 0
  for _ in pairs(domains) do
    domain_count = domain_count + 1
  end
  if domain_count < 10 then
    errors[#errors + 1] = "R4 violation: fewer than 10 distinct evidence domains (" .. domain_count .. ")"
  end

  -- R5 disconfirming evidence links in dossier
  local dossier_path = choose_dossier_path()
  if dossier_path == nil then
    errors[#errors + 1] = "R5 violation: no dossier/disconfirming file found"
  else
    local dossier_lines = read_lines(dossier_path) or {}
    local links = count_links(dossier_lines)
    if links < 5 then
      errors[#errors + 1] = "R5 violation: fewer than 5 disconfirming links in " .. dossier_path
    end
  end

  if #errors > 0 then
    fail(errors)
    return
  end

  print(
    string.format(
      "wp15 research check passed: baselines=%d evidence=%d domains=%d",
      #baselines,
      #evidence,
      domain_count
    )
  )
  vim.cmd("qa")
end

local ok, err = pcall(main)
if not ok then
  vim.api.nvim_err_writeln("wp15 research check runtime error: " .. tostring(err))
  vim.cmd("cquit 1")
end
