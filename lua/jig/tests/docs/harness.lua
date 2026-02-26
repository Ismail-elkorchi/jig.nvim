local command_docs = require("jig.core.command_docs")
local fabric = require("jig.tests.fabric")
local keymap_docs = require("jig.core.keymap_docs")

local M = {}

local function repo_root()
  if type(_G.__jig_repo_root) == "string" and _G.__jig_repo_root ~= "" then
    return _G.__jig_repo_root
  end
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h:h:h:h")
end

local function snapshot_path(opts)
  return fabric.snapshot_path(opts, vim.fn.stdpath("state") .. "/jig/docs-harness-snapshot.json")
end

local function read_or_empty(path)
  if vim.fn.filereadable(path) ~= 1 then
    return ""
  end
  return table.concat(vim.fn.readfile(path), "\n")
end

local function collect_tags()
  local path = repo_root() .. "/doc/tags"
  local content = read_or_empty(path)
  assert(content ~= "", "doc/tags missing or empty")

  local tags = {}
  for line in content:gmatch("[^\n]+") do
    local tag = line:match("^([^\t]+)\t")
    if tag and tag ~= "" then
      tags[tag] = true
    end
  end

  return tags
end

local function markdown_files()
  local root = repo_root()
  local files = {}
  local docs = vim.fn.globpath(root .. "/docs", "**/*.md", false, true)
  for _, path in ipairs(docs) do
    files[#files + 1] = path
  end

  local extras = {
    root .. "/README.md",
    root .. "/repro/README.md",
    root .. "/docs/runbooks/MAINTAINERS.md",
    root .. "/docs/runbooks/CONTRIBUTORS.md",
  }

  for _, path in ipairs(extras) do
    if vim.fn.filereadable(path) == 1 then
      files[#files + 1] = path
    end
  end

  table.sort(files)
  return files
end

local function resolve_relative(base_file, link)
  local cleaned = tostring(link):gsub("#.*$", "")
  cleaned = cleaned:gsub("%?.*$", "")
  local base_dir = vim.fn.fnamemodify(base_file, ":h")
  return vim.fn.fnamemodify(base_dir .. "/" .. cleaned, ":p")
end

local function markdown_links_ok()
  local invalid = {}
  local checked = 0

  for _, path in ipairs(markdown_files()) do
    local content = read_or_empty(path)
    for link in content:gmatch("%[[^%]]+%]%(([^%)]+)%)") do
      if
        not vim.startswith(link, "http://")
        and not vim.startswith(link, "https://")
        and not vim.startswith(link, "mailto:")
        and not vim.startswith(link, "#")
      then
        checked = checked + 1
        local resolved = resolve_relative(path, link)
        if vim.fn.filereadable(resolved) ~= 1 and vim.fn.isdirectory(resolved) ~= 1 then
          invalid[#invalid + 1] = string.format("%s -> %s", path, link)
        end
      end
    end
  end

  assert(#invalid == 0, "invalid markdown links: " .. table.concat(invalid, "; "))
  return {
    checked_links = checked,
  }
end

local function help_refs_ok()
  local tags = collect_tags()
  local missing = {}
  local checked = 0

  for _, path in ipairs(markdown_files()) do
    local content = read_or_empty(path)
    for token in content:gmatch(":help%s+([%w%-_]+)") do
      if token:match("^jig") then
        checked = checked + 1
        if not tags[token] then
          missing[#missing + 1] = string.format("%s -> %s", path, token)
        end
      end
    end
  end

  assert(#missing == 0, "missing help tags in markdown refs: " .. table.concat(missing, "; "))
  return {
    checked_help_refs = checked,
  }
end

local function command_cross_ref_ok()
  local entries = command_docs.collect_commands()
  local md = read_or_empty(repo_root() .. "/docs/commands.jig.nvim.md")
  local vimdoc = read_or_empty(repo_root() .. "/doc/jig-commands.txt")

  local missing = {}
  for _, entry in ipairs(entries) do
    local cmd = ":" .. entry.name
    local in_md = md:find(cmd, 1, true) ~= nil
    local in_help = vimdoc:find(cmd, 1, true) ~= nil
    if not in_md or not in_help then
      missing[#missing + 1] = entry.name
    end
  end

  assert(#missing == 0, "commands missing docs coverage: " .. table.concat(missing, ","))

  local index = read_or_empty(repo_root() .. "/docs/index.jig.nvim.md")
  assert(index:find(":help jig%-keymaps", 1, false) ~= nil, "index missing jig-keymaps link")

  return {
    commands = #entries,
  }
end

local function required_vimdoc_ok()
  local tags = collect_tags()
  local required = {
    "jig",
    "jig-install",
    "jig-configuration",
    "jig-keymaps",
    "jig-troubleshooting",
    "jig-migration",
    "jig-release",
    "jig-rollback",
    "jig-incidents",
    "jig-safety",
    "jig-commands",
  }

  for _, tag in ipairs(required) do
    assert(tags[tag] == true, "missing required help tag: " .. tag)
  end

  local files = {
    "doc/jig.txt",
    "doc/jig-install.txt",
    "doc/jig-configuration.txt",
    "doc/jig-keymaps.txt",
    "doc/jig-troubleshooting.txt",
    "doc/jig-migration.txt",
    "doc/jig-release.txt",
    "doc/jig-rollback.txt",
    "doc/jig-incidents.txt",
    "doc/jig-safety.txt",
    "doc/jig-commands.txt",
  }

  local root = repo_root()
  for _, rel in ipairs(files) do
    local abs = root .. "/" .. rel
    assert(vim.fn.filereadable(abs) == 1, "missing required vimdoc file: " .. rel)
  end

  return {
    required_tags = #required,
    required_files = #files,
  }
end

local function issue_template_ok()
  local bug = read_or_empty(repo_root() .. "/.github/ISSUE_TEMPLATE/bug_report.yml")
  local incident = read_or_empty(repo_root() .. "/.github/ISSUE_TEMPLATE/incident_report.yml")

  local required_surface = {
    "startup",
    "cmdline",
    "completion",
    "lsp",
    "ui",
    "performance",
    "platform",
    "integration",
    "agent",
    "security",
  }
  for _, item in ipairs(required_surface) do
    assert(bug:find("- " .. item, 1, true) ~= nil, "bug template missing failure surface: " .. item)
  end

  local required_tokens = {
    "Severity",
    "Neovim version",
    "OS",
    "Terminal",
    "Shell",
    "NVIM_APPNAME",
    "reproduced in jig-safe",
    ":checkhealth jig",
    ":JigHealth",
    "Permanent fix reference",
  }

  for _, token in ipairs(required_tokens) do
    assert(bug:lower():find(token:lower(), 1, true) ~= nil, "bug template missing field: " .. token)
  end

  assert(incident ~= "", "incident_report.yml missing")
  for _, token in ipairs(required_surface) do
    assert(
      incident:find("- " .. token, 1, true) ~= nil,
      "incident template missing failure surface: " .. token
    )
  end
  for _, token in ipairs({
    "Severity",
    "Exact reproduction steps",
    "Evidence",
    "Permanent fix reference",
  }) do
    assert(
      incident:lower():find(token:lower(), 1, true) ~= nil,
      "incident template missing field: " .. token
    )
  end

  return {
    surfaces = #required_surface,
    fields = #required_tokens,
  }
end

local function repro_template_ok()
  local root = repo_root()
  local files = {
    root .. "/repro/README.md",
    root .. "/repro/minimal_init.lua",
  }

  for _, path in ipairs(files) do
    assert(vim.fn.filereadable(path) == 1, "missing repro template file: " .. path)
  end

  return {
    files = #files,
  }
end

local function runbooks_ok()
  local root = repo_root()
  local files = {
    root .. "/docs/runbooks/MAINTAINERS.md",
    root .. "/docs/runbooks/CONTRIBUTORS.md",
    root .. "/docs/runbooks/RELEASE.md",
    root .. "/docs/runbooks/ROLLBACK.md",
    root .. "/docs/runbooks/INCIDENTS.md",
    root .. "/docs/runbooks/MIGRATION_CONTRACT.md",
  }

  for _, path in ipairs(files) do
    assert(vim.fn.filereadable(path) == 1, "missing runbook: " .. path)
  end

  return {
    files = #files,
  }
end

local function labels_manifest_ok()
  local root = repo_root()
  local manifest = read_or_empty(root .. "/.github/labels.md")
  local sync_script = root .. "/.github/scripts/sync_labels.sh"

  assert(manifest ~= "", "labels manifest missing")
  assert(vim.fn.filereadable(sync_script) == 1, "sync_labels.sh missing")
  for _, token in ipairs({
    "incident",
    "sev0",
    "sev1",
    "sev2",
    "sev3",
    "surface:startup",
    "surface:security",
  }) do
    assert(manifest:find(token, 1, true) ~= nil, "labels manifest missing token: " .. token)
  end

  return {
    manifest = ".github/labels.md",
    sync_script = ".github/scripts/sync_labels.sh",
  }
end

local function docs_index_command_ok()
  assert(vim.fn.exists(":JigDocs") == 2, "JigDocs command missing")

  local docs = require("jig.core.docs")
  local state = docs.open_docs_index({ force_scratch = true })
  assert(type(state) == "table" and state.buf and state.win, "JigDocs state invalid")
  assert(vim.api.nvim_win_is_valid(state.win), "JigDocs window invalid")
  vim.api.nvim_win_close(state.win, true)

  return {
    opened = true,
  }
end

local function help_entrypoint_ok()
  local ok, err = pcall(vim.cmd, "help jig")
  assert(ok, "help jig failed: " .. tostring(err))
  local topic = vim.fn.expand("%:t")
  assert(topic == "jig.txt", "help jig did not open jig.txt")
  vim.cmd("q")
  return {
    topic = topic,
  }
end

local function repro_command_ok()
  assert(vim.fn.exists(":JigRepro") == 2, "JigRepro command missing")
  vim.cmd("JigRepro")
  local payload = vim.g.jig_repro_last
  assert(type(payload) == "table" and type(payload.lines) == "table", "JigRepro output missing")

  local joined = table.concat(payload.lines, "\n")
  assert(
    joined:find("nvim %-%-clean %-u repro/minimal_init%.lua", 1, false) ~= nil,
    "JigRepro missing minimal command"
  )

  return {
    lines = #payload.lines,
  }
end

local function keymap_docs_linked_ok()
  assert(keymap_docs.generate({ check = true }), "keymap docs out of sync")
  local index = read_or_empty(repo_root() .. "/docs/index.jig.nvim.md")
  assert(
    index:find(":help jig%-keymaps", 1, false) ~= nil,
    "keymaps help not linked from docs index"
  )
  return {
    linked = true,
  }
end

local function execution_board_tracking_ok()
  local board = read_or_empty(repo_root() .. "/docs/roadmap/EXECUTION_BOARD.md")
  assert(board ~= "", "execution board missing")

  assert(
    board:find("Updated at:%s*`%d%d%d%d%-%d%d%-%d%d`", 1, false) ~= nil,
    "execution board missing deterministic Updated at timestamp"
  )
  assert(
    board:find("### WP%-16: Toolchain Lockfile and External Dependency Lifecycle", 1, false) ~= nil,
    "execution board missing WP-16 section"
  )
  assert(
    board:find("### WP%-16:.-%- Status: `done`", 1, false) ~= nil,
    "execution board must mark WP-16 as done"
  )
  assert(
    board:find("https://github.com/Ismail%-elkorchi/jig%.nvim/pull/47", 1, false) ~= nil,
    "execution board missing WP-16 PR reference"
  )
  assert(
    board:find("### WP%-17: Agent UX Surface, Transactional Edits, and Context Ledger", 1, false)
      ~= nil,
    "execution board missing WP-17 section"
  )
  assert(
    board:find("### WP%-17:.-%- Status: `done`", 1, false) ~= nil,
    "execution board must mark WP-17 as done"
  )
  assert(
    board:find("https://github.com/Ismail%-elkorchi/jig%.nvim/pull/49", 1, false) ~= nil,
    "execution board missing WP-17 PR reference"
  )
  assert(
    board:find("### WP%-18: Agent Threat Model and Security Regression Suite", 1, false) ~= nil,
    "execution board missing WP-18 section"
  )
  assert(
    board:find("### WP%-18:.-%- Status: `not%-started` %(`next`%)", 1, false) ~= nil,
    "execution board must mark WP-18 as next"
  )

  return {
    wp16 = "done",
    wp17 = "done",
    wp18 = "next",
  }
end

local cases = {
  {
    id = "required-vimdoc-set",
    run = required_vimdoc_ok,
  },
  {
    id = "docs-index-command-open-close",
    run = docs_index_command_ok,
  },
  {
    id = "help-entrypoint",
    run = help_entrypoint_ok,
  },
  {
    id = "repro-command-surface",
    run = repro_command_ok,
  },
  {
    id = "command-doc-sync-gate",
    run = function()
      assert(command_docs.generate({ check = true }), "command docs out of sync")
      return { ok = true }
    end,
  },
  {
    id = "command-doc-cross-reference",
    run = command_cross_ref_ok,
  },
  {
    id = "markdown-link-check",
    run = markdown_links_ok,
  },
  {
    id = "help-reference-check",
    run = help_refs_ok,
  },
  {
    id = "keymap-doc-linkage",
    run = keymap_docs_linked_ok,
  },
  {
    id = "issue-template-failure-surfaces",
    run = issue_template_ok,
  },
  {
    id = "repro-template-present",
    run = repro_template_ok,
  },
  {
    id = "runbooks-present",
    run = runbooks_ok,
  },
  {
    id = "labels-manifest-controls",
    run = labels_manifest_ok,
  },
  {
    id = "execution-board-wp16-wp18-tracking",
    run = execution_board_tracking_ok,
  },
}

function M.run(opts)
  local report = fabric.run_cases(cases, {
    harness = "headless-child-docs",
  })

  local path = snapshot_path(opts)
  fabric.finalize(report, {
    snapshot_path = path,
    fail_label = "docs harness",
  })
  print("docs-harness snapshot written: " .. path)
end

return M
