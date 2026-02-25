#!/usr/bin/env -S nvim --headless -u NONE -l

local source = debug.getinfo(1, "S").source:sub(2)
local script_dir = vim.fn.fnamemodify(source, ":p:h")
local common = dofile(script_dir .. "/common.lua")

local ROOT = common.repo_root()

local METHOD_VALUES = {
  benchmark = true,
  ["field-study"] = true,
  ["lab-study"] = true,
  survey = true,
  ["security-eval"] = true,
  spec = true,
  ["issue-report"] = true,
  ["incident-report"] = true,
}

local QUALITY_VALUES = {
  peer_reviewed = true,
  standards_spec = true,
  official_docs = true,
  incident = true,
  community_issues = true,
}

local CATEGORY_THRESHOLDS = {
  A = 1, -- agent interface / ACI
  B = 1, -- software engineering benchmark relevance
  C = 2, -- human factors / verification burden
  D = 2, -- security of tool-integrated agents
  E = 1, -- longitudinal multi-session collaboration
}

local REQUIRED_PATTERNS = {
  ["SWE-bench ICLR 2024"] = "VTF8yNQM66",
  ["SWE-agent NeurIPS 2024"] = "neurips.cc/paper_files/paper/2024/hash/c3359f42",
  ["ICSE 2024 code understanding"] = "10.1145/3597503.3639187",
  ["InjecAgent Findings ACL 2024"] = "2024%.findings%-acl%.624",
  ["CCS 2024 prompt-injection"] = "10.1145/3658644.3690291",
  ["Trojan Source USENIX Security"] = "usenixsecurity23%-boucher%.pdf",
  ["CodeBreaker USENIX Security 2024"] = "usenixsecurity24%-yan%.pdf",
}

local REQUIRED_EVIDENCE_FIELDS = {
  "id",
  "baseline_id",
  "type",
  "url",
  "published_at",
  "retrieved_at",
  "claim",
  "why_it_matters",
  "polarity",
  "failure_surface",
  "peer_reviewed",
  "venue",
  "method",
  "quality_tier",
}

local REQUIRED_PEER_METADATA_FIELDS = {
  "title",
  "year",
  "why_this_matters_for_jig",
}

local REQUIRED_LOG_FIELDS = {
  "date",
  "query",
  "search_intent",
  "target_categories",
  "candidate_refs",
  "included_ids",
  "excluded_ids",
  "exclude_reasons",
  "what_new_failure_mode_or_metric_it_added",
}

local function to_string(value)
  if value == vim.NIL then
    return ""
  end
  return tostring(value or "")
end

local function to_set(items)
  local set = {}
  for _, item in ipairs(items or {}) do
    local key = to_string(item)
    if key ~= "" then
      set[key] = true
    end
  end
  return set
end

local function coerce_array(value)
  if type(value) == "table" then
    return value
  end
  local raw = to_string(value)
  if raw == "" then
    return {}
  end
  return { raw }
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

local function domain(url)
  if type(url) ~= "string" then
    return nil
  end
  return url:match("^https?://([^/%?#]+)")
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

local function validate_baselines(baselines, errors)
  local nvim_count = 0
  local agent_count = 0
  local stability_ops = 0
  local minimal_starter = 0
  local agent_first = 0

  for _, baseline in ipairs(baselines) do
    local category = to_string(baseline.category)
    if category == "nvim_distro" or category == "nvim_starter" then
      nvim_count = nvim_count + 1
    end
    if category == "agent_cli" or category == "agent_editor" or category == "agent_protocol" then
      agent_count = agent_count + 1
    end

    local tags = to_set(coerce_array(baseline.positioning_tags))
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
    errors[#errors + 1] = "R1 violation: fewer than 2 stability_ops baselines ("
      .. stability_ops
      .. ")"
  end
  if minimal_starter < 2 then
    errors[#errors + 1] = "R1 violation: fewer than 2 minimal_starter baselines ("
      .. minimal_starter
      .. ")"
  end
  if agent_first < 2 then
    errors[#errors + 1] = "R1 violation: fewer than 2 agent_first baselines (" .. agent_first .. ")"
  end

  for _, baseline in ipairs(baselines) do
    if to_string(baseline.pinned_version) == "" then
      errors[#errors + 1] = "R2 violation: missing pinned_version for " .. to_string(baseline.id)
    end
    if to_string(baseline.pin_evidence_url) == "" then
      errors[#errors + 1] = "R2 violation: missing pin_evidence_url for " .. to_string(baseline.id)
    end
  end
end

local function validate_evidence_schema(evidence, errors)
  local by_id = {}
  local peer_count = 0
  local category_counts = {
    A = 0,
    B = 0,
    C = 0,
    D = 0,
    E = 0,
  }

  local required_pattern_seen = {}
  for name, _ in pairs(REQUIRED_PATTERNS) do
    required_pattern_seen[name] = false
  end

  for _, item in ipairs(evidence) do
    for _, key in ipairs(REQUIRED_EVIDENCE_FIELDS) do
      if item[key] == nil then
        errors[#errors + 1] = "schema violation: evidence "
          .. to_string(item.id)
          .. " missing field `"
          .. key
          .. "`"
      end
    end

    if type(item.peer_reviewed) ~= "boolean" then
      errors[#errors + 1] = "schema violation: evidence "
        .. to_string(item.id)
        .. " field `peer_reviewed` must be boolean"
    end

    if to_string(item.venue) == "" then
      errors[#errors + 1] = "schema violation: evidence "
        .. to_string(item.id)
        .. " field `venue` must be non-empty"
    end

    local method = to_string(item.method)
    if METHOD_VALUES[method] ~= true then
      errors[#errors + 1] = "schema violation: evidence "
        .. to_string(item.id)
        .. " invalid method `"
        .. method
        .. "`"
    end

    local quality = to_string(item.quality_tier)
    if QUALITY_VALUES[quality] ~= true then
      errors[#errors + 1] = "schema violation: evidence "
        .. to_string(item.id)
        .. " invalid quality_tier `"
        .. quality
        .. "`"
    end

    if item.peer_reviewed == true and quality ~= "peer_reviewed" then
      errors[#errors + 1] = "schema violation: evidence "
        .. to_string(item.id)
        .. " peer_reviewed=true requires quality_tier=peer_reviewed"
    end
    if item.peer_reviewed ~= true and quality == "peer_reviewed" then
      errors[#errors + 1] = "schema violation: evidence "
        .. to_string(item.id)
        .. " quality_tier=peer_reviewed requires peer_reviewed=true"
    end

    local id = to_string(item.id)
    if id ~= "" then
      by_id[id] = item
    end

    if item.peer_reviewed == true then
      peer_count = peer_count + 1
      for _, key in ipairs(REQUIRED_PEER_METADATA_FIELDS) do
        if item[key] == nil or to_string(item[key]) == "" then
          errors[#errors + 1] = "schema violation: evidence "
            .. to_string(item.id)
            .. " peer_reviewed entry missing `"
            .. key
            .. "`"
        end
      end
      if type(item.year) ~= "number" or item.year < 2000 then
        errors[#errors + 1] = "schema violation: evidence "
          .. to_string(item.id)
          .. " peer_reviewed entry has invalid `year`"
      end

      local title = to_string(item.title)
      local claim = to_string(item.claim)
      if title == claim then
        errors[#errors + 1] = "schema violation: evidence "
          .. to_string(item.id)
          .. " peer_reviewed title must not equal claim string"
      end
      local title_lower = title:lower()
      if title_lower:find("paper presents", 1, true) ~= nil then
        errors[#errors + 1] = "schema violation: evidence "
          .. to_string(item.id)
          .. " peer_reviewed title contains placeholder phrase `paper presents`"
      end

      local categories = to_set(coerce_array(item.research_categories))
      local category_hit = false
      for category, _ in pairs(CATEGORY_THRESHOLDS) do
        if categories[category] == true then
          category_counts[category] = category_counts[category] + 1
          category_hit = true
        end
      end
      if not category_hit then
        errors[#errors + 1] = "schema violation: evidence "
          .. to_string(item.id)
          .. " peer_reviewed entry missing research_categories A-E"
      end
    end

    local url = to_string(item.url):lower()
    for name, pattern in pairs(REQUIRED_PATTERNS) do
      if url:match(pattern:lower()) ~= nil then
        required_pattern_seen[name] = true
      end
    end
  end

  if peer_count < 10 then
    errors[#errors + 1] = "R6 violation: fewer than 10 peer-reviewed evidence entries ("
      .. peer_count
      .. ")"
  end

  for category, threshold in pairs(CATEGORY_THRESHOLDS) do
    local count = category_counts[category] or 0
    if count < threshold then
      errors[#errors + 1] = string.format(
        "R6 violation: category %s peer-reviewed coverage below threshold (%d < %d)",
        category,
        count,
        threshold
      )
    end
  end

  for name, seen in pairs(required_pattern_seen) do
    if seen ~= true then
      errors[#errors + 1] = "R6 violation: required peer-reviewed source missing: " .. name
    end
  end

  return by_id
end

local function validate_evidence_coverage(baselines, evidence, errors)
  if #evidence < 40 then
    errors[#errors + 1] = "R3 violation: evidence count below 40 (" .. #evidence .. ")"
  end

  local ev_by_baseline = {}
  local domains = {}
  for _, item in ipairs(evidence) do
    local bid = to_string(item.baseline_id)
    if bid ~= "" and bid ~= "general" then
      ev_by_baseline[bid] = ev_by_baseline[bid] or {}
      ev_by_baseline[bid][#ev_by_baseline[bid] + 1] = item
    end

    local d = domain(to_string(item.url))
    if d then
      domains[d] = true
    end
  end

  for _, baseline in ipairs(baselines) do
    local id = to_string(baseline.id)
    local entries = ev_by_baseline[id] or {}
    if #entries < 3 then
      errors[#errors + 1] = "R3 violation: baseline has fewer than 3 evidence items: " .. id
    end

    local official = 0
    local negative = 0
    for _, item in ipairs(entries) do
      local item_type = to_string(item.type)
      if item_type == "official_doc" then
        official = official + 1
      end
      if
        to_string(item.polarity) == "negative"
        and (item_type == "issue" or item_type == "discussion" or item_type == "security_writeup")
      then
        negative = negative + 1
      end
    end

    if official < 1 then
      errors[#errors + 1] = "R3 violation: no official_doc evidence for " .. id
    end
    if negative < 1 then
      errors[#errors + 1] = "R3 violation: no negative issue/discussion/security evidence for "
        .. id
    end
  end

  local domain_count = 0
  for _ in pairs(domains) do
    domain_count = domain_count + 1
  end
  if domain_count < 10 then
    errors[#errors + 1] = "R4 violation: fewer than 10 distinct evidence domains ("
      .. domain_count
      .. ")"
  end

  return domain_count
end

local function validate_research_log(path, evidence_by_id, errors)
  if vim.fn.filereadable(path) ~= 1 then
    errors[#errors + 1] = "R7 violation: missing research log file " .. path
    return
  end

  local entries = common.parse_yaml_list(path)
  if #entries == 0 then
    errors[#errors + 1] = "R7 violation: research log is empty"
    return
  end

  local query_entries = {}

  for _, entry in ipairs(entries) do
    for _, key in ipairs(REQUIRED_LOG_FIELDS) do
      if entry[key] == nil then
        errors[#errors + 1] = "R7 violation: research log entry missing `"
          .. key
          .. "` for query `"
          .. to_string(entry.query)
          .. "`"
      end
    end

    local date_value = to_string(entry.date)
    if date_value:match("^%d%d%d%d%-%d%d%-%d%d$") == nil then
      errors[#errors + 1] = "R7 violation: date must be YYYY-MM-DD for query `"
        .. to_string(entry.query)
        .. "`"
    end

    local search_intent = to_string(entry.search_intent)
    if
      search_intent ~= "confirming"
      and search_intent ~= "disconfirming"
      and search_intent ~= "exploratory"
    then
      errors[#errors + 1] = "R7 violation: search_intent must be confirming|disconfirming|exploratory for query `"
        .. to_string(entry.query)
        .. "`"
    end

    local target_categories = to_set(coerce_array(entry.target_categories))
    local target_count = 0
    for _, category in ipairs({ "A", "B", "C", "D", "E" }) do
      if target_categories[category] then
        target_count = target_count + 1
      end
    end
    if target_count == 0 then
      errors[#errors + 1] = "R7 violation: target_categories must include at least one of A-E for query `"
        .. to_string(entry.query)
        .. "`"
    end

    local candidate_refs = to_set(coerce_array(entry.candidate_refs))
    local candidate_count = 0
    for _ in pairs(candidate_refs) do
      candidate_count = candidate_count + 1
    end

    local included_ids = coerce_array(entry.included_ids)
    local excluded_ids = coerce_array(entry.excluded_ids)
    local exclude_reasons = coerce_array(entry.exclude_reasons)

    if #exclude_reasons < #excluded_ids then
      errors[#errors + 1] = "R7 violation: exclude_reasons must have at least one reason per excluded id for query `"
        .. to_string(entry.query)
        .. "`"
    end

    local exclude_reason_map = {}
    for _, reason in ipairs(exclude_reasons) do
      local raw = to_string(reason)
      local ref = raw:match("^([^=]+)=")
      if ref ~= nil and ref ~= "" then
        exclude_reason_map[ref] = true
      end
    end

    local peer_includes = 0
    for _, include_id in ipairs(included_ids) do
      local include_key = to_string(include_id)
      if include_key ~= "" and candidate_refs[include_key] ~= true then
        errors[#errors + 1] = "R7 violation: included id not present in candidate_refs for query `"
          .. to_string(entry.query)
          .. "`: "
          .. include_key
      end
      local evidence_item = evidence_by_id[include_key]
      if evidence_item == nil then
        errors[#errors + 1] = "R7 violation: included id missing from evidence register: `"
          .. include_key
          .. "`"
      elseif evidence_item.peer_reviewed == true then
        peer_includes = peer_includes + 1
      end
    end

    for _, excluded_id in ipairs(excluded_ids) do
      local excluded_key = to_string(excluded_id)
      if excluded_key ~= "" and candidate_refs[excluded_key] ~= true then
        errors[#errors + 1] = "R7 violation: excluded id not present in candidate_refs for query `"
          .. to_string(entry.query)
          .. "`: "
          .. excluded_key
      end
      if excluded_key ~= "" and exclude_reason_map[excluded_key] ~= true then
        errors[#errors + 1] = "R7 violation: excluded id missing explicit reason mapping for query `"
          .. to_string(entry.query)
          .. "`: "
          .. excluded_key
      end
    end

    query_entries[#query_entries + 1] = {
      query = to_string(entry.query),
      search_intent = search_intent,
      target_categories = target_categories,
      candidate_count = candidate_count,
      peer_includes = peer_includes,
    }
  end

  if #query_entries < 6 then
    errors[#errors + 1] =
      "R7 violation: research log must include at least 6 distinct queries for saturation check"
    return
  end

  local start_index = math.max(1, #query_entries - 5)
  local categories_seen = {}
  local has_disconfirming = false

  for index = start_index, #query_entries do
    local item = query_entries[index]

    if item.candidate_count < 3 then
      errors[#errors + 1] = "R7 violation: last-6 saturation window query has fewer than 3 candidates: `"
        .. item.query
        .. "`"
    end

    if item.peer_includes > 1 then
      errors[#errors + 1] = "R7 violation: saturation failed for query `"
        .. item.query
        .. "` (peer-reviewed includes="
        .. item.peer_includes
        .. ")"
    end

    if item.search_intent == "disconfirming" then
      has_disconfirming = true
    end

    for category, _ in pairs(item.target_categories) do
      if CATEGORY_THRESHOLDS[category] ~= nil then
        categories_seen[category] = true
      end
    end
  end

  local coverage_count = 0
  for _ in pairs(categories_seen) do
    coverage_count = coverage_count + 1
  end

  if coverage_count < 3 then
    errors[#errors + 1] =
      "R7 violation: last-6 saturation window must cover at least 3 distinct target categories"
  end

  if has_disconfirming ~= true then
    errors[#errors + 1] =
      "R7 violation: last-6 saturation window must include at least one disconfirming query"
  end
end

local function validate_disconfirming(errors)
  local dossier_path = choose_dossier_path()
  if dossier_path == nil then
    errors[#errors + 1] = "R5 violation: no dossier/disconfirming file found"
    return
  end
  local lines = common.read_lines(dossier_path) or {}
  local links = count_links(lines)
  if links < 5 then
    errors[#errors + 1] = "R5 violation: fewer than 5 disconfirming links in " .. dossier_path
  end
end

local function main()
  local paths = {
    baselines = common.join(ROOT, "data/wp15/baselines.yaml"),
    evidence = common.join(ROOT, "data/wp15/evidence.jsonl"),
    research_log = common.join(ROOT, "data/wp15/research_log.yaml"),
  }

  local baselines = common.parse_yaml_list(paths.baselines)
  local evidence = common.parse_jsonl(paths.evidence)
  local errors = {}

  validate_baselines(baselines, errors)
  local evidence_by_id = validate_evidence_schema(evidence, errors)
  local domain_count = validate_evidence_coverage(baselines, evidence, errors)
  validate_research_log(paths.research_log, evidence_by_id, errors)
  validate_disconfirming(errors)

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
