local brand = require("jig.core.brand")
local config = require("jig.workbench.config")
local icons = require("jig.ui.icons")
local nav_config = require("jig.nav.config")
local nav_fallback = require("jig.nav.fallback")
local nav_root = require("jig.nav.root")
local terminal = require("jig.tools.terminal")

local M = {}

local commands_registered = false

local function in_ui()
  return #vim.api.nvim_list_uis() > 0
end

local function workspace_root()
  local resolved = nav_root.resolve()
  if type(resolved) == "table" and type(resolved.root) == "string" and resolved.root ~= "" then
    return resolved.root
  end
  return vim.uv.cwd()
end

local function is_workbench_role(role)
  return role == "nav" or role == "term" or role == "agent"
end

local function role_for_buf(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return ""
  end
  return tostring(vim.b[bufnr].jig_workbench_role or "")
end

local function set_role(bufnr, role)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.b[bufnr].jig_workbench_role = role
  end
end

local function list_tab_windows()
  return vim.api.nvim_tabpage_list_wins(0)
end

local function role_windows()
  local out = {
    main = {},
    nav = {},
    term = {},
    agent = {},
    other = {},
  }

  for _, win in ipairs(list_tab_windows()) do
    if vim.api.nvim_win_is_valid(win) then
      local role = role_for_buf(vim.api.nvim_win_get_buf(win))
      if out[role] ~= nil then
        out[role][#out[role] + 1] = win
      else
        out.other[#out.other + 1] = win
      end
    end
  end

  return out
end

local function pick_main_window()
  local roles = role_windows()
  if #roles.main > 0 and vim.api.nvim_win_is_valid(roles.main[1]) then
    return roles.main[1]
  end

  for _, win in ipairs(list_tab_windows()) do
    if vim.api.nvim_win_is_valid(win) then
      local role = role_for_buf(vim.api.nvim_win_get_buf(win))
      if not is_workbench_role(role) then
        return win
      end
    end
  end

  local current = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(current) then
    return current
  end

  return list_tab_windows()[1]
end

local function close_window(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  pcall(vim.api.nvim_win_close, win, true)
end

local function close_role_windows(role)
  local roles = role_windows()
  for _, win in ipairs(roles[role] or {}) do
    close_window(win)
  end
end

local function close_workbench_roles()
  close_role_windows("nav")
  close_role_windows("term")
  close_role_windows("agent")
end

local function with_current_win(win, fn)
  local previous = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
  local ok, result1, result2, result3 = pcall(fn)
  if vim.api.nvim_win_is_valid(previous) then
    vim.api.nvim_set_current_win(previous)
  end
  if not ok then
    error(result1)
  end
  return result1, result2, result3
end

local function make_scratch_buffer(name, lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = "jigworkbench"
  vim.api.nvim_buf_set_name(bufnr, name)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  return bufnr
end

local function split_lines(text)
  if type(text) ~= "string" or text == "" then
    return {}
  end
  return vim.split(text, "\n", { plain = true, trimempty = true })
end

local function command_token(argv)
  local first = tostring((argv and argv[1]) or "")
  return first:lower()
end

local function networkish_argv(argv)
  local token = command_token(argv)
  local risky = {
    curl = true,
    wget = true,
    http = true,
    https = true,
    npm = true,
    cargo = true,
    pip = true,
    pnpm = true,
    yarn = true,
  }
  if risky[token] then
    return true
  end

  if token == "git" then
    local sub = tostring((argv and argv[4]) or (argv and argv[2]) or ""):lower()
    local git_network = {
      clone = true,
      fetch = true,
      pull = true,
      push = true,
      remote = true,
      ls_remote = true,
      lsremote = true,
    }
    return git_network[sub] == true
  end

  return false
end

local function git_status_lines(root, operations, cap)
  local system = require("jig.tools.system")
  local argv = { "git", "-C", root, "status", "--short" }
  operations[#operations + 1] = argv

  local result = system.run_sync(argv, {
    timeout_ms = 2000,
    actor = "user",
    origin = "jig.workbench.nav",
  })

  if result.ok ~= true then
    return {
      string.format("%s git status unavailable", icons.get("warning")),
      "hint: use :JigGitChanges for interactive path once git repo is available.",
    },
      false
  end

  local rows = {}
  for _, line in ipairs(split_lines(result.stdout)) do
    rows[#rows + 1] = line
    if #rows >= cap then
      break
    end
  end

  if #rows == 0 then
    rows = { string.format("%s clean working tree", icons.get("health")) }
  end

  return rows, true
end

local function files_lines(root, cap)
  local nav_cfg = nav_config.get()
  local items = nav_fallback.list_files(root, {
    cap = cap,
    ignore_globs = nav_cfg.ignore_globs,
  })

  local rows = {}
  for _, item in ipairs(items) do
    rows[#rows + 1] = tostring(item.label)
    if #rows >= cap then
      break
    end
  end

  if #rows == 0 then
    rows = { string.format("%s no files found", icons.get("warning")) }
  end

  return rows
end

local function nav_lines(preset_name, preset, root, cfg, operations)
  local title = preset.nav_source == "git_changes" and "Git changes" or "Files"
  local lines = {
    string.format("%s Jig Workbench (%s)", icons.get("action"), preset_name),
    string.rep("=", 46),
    string.format("root: %s", root),
    string.format("source: %s", title),
    "",
    "entrypoints:",
    "  :JigFiles",
    "  :JigGitChanges",
    "  :JigDiagnostics",
    "  :JigTerm root",
    "  :JigWorkbenchReset",
    "",
  }

  local content
  if preset.nav_source == "git_changes" then
    content = git_status_lines(root, operations, cfg.nav_cap)
  else
    content = files_lines(root, cfg.nav_cap)
  end

  if type(content) == "table" and type(content[1]) == "table" then
    content = content[1]
  end

  lines[#lines + 1] = "items:"
  for _, row in ipairs(content) do
    lines[#lines + 1] = "  " .. tostring(row)
  end

  return lines
end

local function agent_panel_lines(root)
  local approvals = require("jig.agent.approvals")
  local patch = require("jig.agent.patch")
  local pending = approvals.list({ status = "pending" })
  local sessions = patch.list()

  local lines = {
    string.format("%s Agent Queue", icons.get("warning")),
    string.rep("=", 32),
    string.format("root: %s", root),
    string.format("pending approvals: %d", #pending),
    string.format("patch sessions: %d", #sessions),
    "",
    "entrypoints:",
    "  :JigAgentApprovals",
    "  :JigPatchSessions",
    "  :JigPatchReview <session_id>",
    "  :JigAgentContext",
    "",
  }

  if #pending > 0 then
    lines[#lines + 1] = "pending:"
    for _, item in ipairs(pending) do
      lines[#lines + 1] = string.format(
        "  - %s %s %s",
        tostring(item.id),
        tostring(item.subject.action_class),
        tostring(item.subject.target)
      )
    end
    lines[#lines + 1] = ""
  end

  if #sessions > 0 then
    lines[#lines + 1] = "patch sessions:"
    for _, session in ipairs(sessions) do
      lines[#lines + 1] = string.format(
        "  - %s status=%s files=%d",
        tostring(session.id),
        tostring(session.status),
        #(session.files or {})
      )
    end
  end

  return lines
end

local function open_nav_window(main_win, lines, width)
  return with_current_win(main_win, function()
    vim.cmd("topleft vsplit")
    local win = vim.api.nvim_get_current_win()
    if width and width > 20 then
      pcall(vim.api.nvim_win_set_width, win, math.floor(width))
    end

    local bufnr = make_scratch_buffer("jig://workbench/nav", lines)
    vim.api.nvim_win_set_buf(win, bufnr)
    set_role(bufnr, "nav")
    return {
      win = win,
      bufnr = bufnr,
    }
  end)
end

local function open_agent_window(main_win, lines, width)
  return with_current_win(main_win, function()
    vim.cmd("botright vsplit")
    local win = vim.api.nvim_get_current_win()
    if width and width > 20 then
      pcall(vim.api.nvim_win_set_width, win, math.floor(width))
    end

    local bufnr = make_scratch_buffer("jig://workbench/agent", lines)
    vim.api.nvim_win_set_buf(win, bufnr)
    set_role(bufnr, "agent")
    return {
      win = win,
      bufnr = bufnr,
    }
  end)
end

local function open_term_window(main_win, height)
  local ok, state = with_current_win(main_win, function()
    return terminal.open({ scope = "root" })
  end)
  if ok ~= true then
    return false, state
  end

  if type(state) == "table" and state.win and vim.api.nvim_win_is_valid(state.win) then
    if height and height > 4 then
      pcall(vim.api.nvim_win_set_height, state.win, math.floor(height))
    end
    set_role(state.bufnr, "term")
  end

  return true, state
end

local function agent_enabled()
  if vim.fn.exists(":" .. brand.command("AgentApprovals")) ~= 2 then
    return false
  end
  if vim.fn.exists(":" .. brand.command("PatchReview")) ~= 2 then
    return false
  end
  return true
end

local function ensure_main_role(main_win)
  if not vim.api.nvim_win_is_valid(main_win) then
    return nil
  end
  local bufnr = vim.api.nvim_win_get_buf(main_win)
  set_role(bufnr, "main")
  return bufnr
end

local function ensure_layout(preset_name)
  local preset, normalized, cfg = config.resolve_preset(preset_name)
  if preset == nil then
    return false, string.format("unknown preset: %s", normalized)
  end

  local main_win = pick_main_window()
  if not main_win or not vim.api.nvim_win_is_valid(main_win) then
    return false, "no active window available"
  end

  ensure_main_role(main_win)
  close_workbench_roles()
  if not vim.api.nvim_win_is_valid(main_win) then
    main_win = pick_main_window()
    ensure_main_role(main_win)
  end

  local root = workspace_root()
  local operations = {}

  local nav =
    open_nav_window(main_win, nav_lines(normalized, preset, root, cfg, operations), cfg.nav_width)

  local term = nil
  if preset.terminal == true then
    local ok_term, term_state_or_err = open_term_window(main_win, cfg.term_height)
    if ok_term then
      term = term_state_or_err
    else
      vim.notify(
        "JigWorkbench terminal failed: " .. tostring(term_state_or_err),
        vim.log.levels.WARN
      )
    end
  end

  local agent = nil
  local agent_state = "disabled"
  if preset.agent_panel == true then
    if agent_enabled() then
      agent = open_agent_window(main_win, agent_panel_lines(root), cfg.agent_width)
      agent_state = "enabled"
    else
      agent_state = "skipped_agent_disabled"
      vim.notify(
        "JigWorkbench agent preset: agent module is disabled; right panel skipped.",
        vim.log.levels.INFO
      )
    end
  end

  if vim.api.nvim_win_is_valid(main_win) then
    vim.api.nvim_set_current_win(main_win)
  end

  local networkish = false
  for _, argv in ipairs(operations) do
    if networkish_argv(argv) then
      networkish = true
      break
    end
  end

  local roles = role_windows()
  local state = {
    preset = normalized,
    root = root,
    agent_state = agent_state,
    windows = {
      main = main_win,
      nav = nav and nav.win or nil,
      term = term and term.win or nil,
      agent = agent and agent.win or nil,
    },
    role_counts = {
      main = #roles.main,
      nav = #roles.nav,
      term = #roles.term,
      agent = #roles.agent,
    },
    operations = {
      argv = operations,
      networkish = networkish,
    },
    icon_mode = icons.mode(),
  }

  vim.g.jig_workbench_last = state
  vim.g.jig_workbench_last_preset = normalized

  return true, state
end

local function reset_layout()
  close_workbench_roles()
  vim.g.jig_workbench_last = nil
  vim.g.jig_workbench_last_preset = nil
  return {
    reset = true,
    wins = #list_tab_windows(),
  }
end

local function cmd_workbench(opts)
  local ok, state_or_err = ensure_layout(opts.args)
  if not ok then
    vim.notify("JigWorkbench failed: " .. tostring(state_or_err), vim.log.levels.ERROR)
    return
  end

  if in_ui() then
    vim.notify(
      string.format("JigWorkbench preset=%s root=%s", state_or_err.preset, state_or_err.root),
      vim.log.levels.INFO
    )
  end
end

local function cmd_workbench_reset()
  local payload = reset_layout()
  if in_ui() then
    vim.notify("JigWorkbench reset", vim.log.levels.INFO)
  else
    print(vim.inspect(payload))
  end
end

local function cmd_workbench_help()
  local ok = pcall(vim.cmd, "help jig-workbench")
  if ok then
    vim.g.jig_workbench_help_last = {
      mode = "help",
      tag = "jig-workbench",
    }
    return
  end

  local docs_ok, docs_state = pcall(function()
    return require("jig.core.docs").open_docs_index({ force_scratch = true })
  end)
  if docs_ok then
    vim.g.jig_workbench_help_last = {
      mode = "docs_index_fallback",
      tag = "jig-workbench",
      docs_mode = type(docs_state) == "table" and docs_state.mode or "unknown",
    }
    if not in_ui() then
      print("JigWorkbenchHelp fallback: docs index")
    end
    return
  end

  vim.notify(
    "JigWorkbenchHelp unavailable: missing help tag and docs fallback failed.",
    vim.log.levels.ERROR
  )
end

local function create_command(name, callback, opts)
  if vim.fn.exists(":" .. name) == 2 then
    return
  end
  vim.api.nvim_create_user_command(name, callback, opts or {})
end

function M.setup()
  if vim.g.jig_safe_profile then
    return {
      enabled = false,
      reason = "safe_profile",
    }
  end

  local cfg = config.get()
  if cfg.enabled ~= true then
    return {
      enabled = false,
      reason = "disabled",
    }
  end

  if commands_registered then
    return {
      enabled = true,
      reason = "already_registered",
    }
  end

  create_command(brand.command("Workbench"), cmd_workbench, {
    nargs = "?",
    complete = function()
      return config.preset_names()
    end,
    desc = "Assemble an idempotent workbench layout (dev|review|agent|minimal)",
  })

  create_command(brand.command("WorkbenchReset"), cmd_workbench_reset, {
    nargs = 0,
    desc = "Reset workbench layout roles in current tab",
  })

  create_command(brand.command("WorkbenchHelp"), cmd_workbench_help, {
    nargs = 0,
    desc = "Open workbench help topic",
  })

  commands_registered = true
  return {
    enabled = true,
    reason = "registered",
  }
end

function M._ensure_layout_for_test(preset_name)
  return ensure_layout(preset_name)
end

function M._reset_for_test()
  return reset_layout()
end

return M
