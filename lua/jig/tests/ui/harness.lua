local chrome = require("jig.ui.chrome")
local cmdline = require("jig.ui.cmdline")
local float = require("jig.ui.float")
local icons = require("jig.ui.icons")
local tokens = require("jig.ui.tokens")

local M = {}

local function snapshot_path(opts)
  if opts and opts.snapshot_path and opts.snapshot_path ~= "" then
    return opts.snapshot_path
  end
  return vim.fn.stdpath("state") .. "/jig/ui-harness-snapshot.json"
end

local function write_snapshot(path, payload)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(payload) }, path)
end

local function command_exists(name)
  return vim.fn.exists(":" .. name) == 2
end

local default_commands = {
  "JigHealth",
  "JigVerboseMap",
  "JigVerboseSet",
  "JigBisectGuide",
  "JigUiProfile",
  "JigIconMode",
  "JigCmdlineCheck",
  "JigFloatDemo",
  "JigPluginBootstrap",
  "JigPluginInstall",
  "JigPluginUpdate",
  "JigPluginRestore",
  "JigPluginRollback",
}

local function command_surface()
  local surface = {}
  for _, command in ipairs(default_commands) do
    surface[command] = command_exists(command)
  end
  return surface
end

local function same_surface(a, b)
  for _, command in ipairs(default_commands) do
    if a[command] ~= b[command] then
      return false, command
    end
  end
  return true, nil
end

local function as_number(value)
  if type(value) == "table" then
    return math.floor(value[false] or value[1] or 0)
  end
  return math.floor(value or 0)
end

local cases = {
  {
    id = "semantic-token-groups",
    run = function()
      local groups = {
        tokens.groups.diagnostics,
        tokens.groups.action,
        tokens.groups.inactive,
        tokens.groups.accent,
        tokens.groups.neutral,
        tokens.groups.danger,
        tokens.groups.warning,
      }
      local details = {}
      for _, group in ipairs(groups) do
        local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
        if not next(hl) then
          return false, { missing = group }
        end
        details[group] = hl
      end
      return true, details
    end,
  },
  {
    id = "active-inactive-chrome",
    run = function()
      local start_win = vim.api.nvim_get_current_win()
      vim.cmd("vsplit")
      vim.cmd("wincmd l")
      local active_win = vim.api.nvim_get_current_win()
      chrome.refresh()

      local active_statusline = vim.api.nvim_get_option_value("statusline", { win = active_win })
      local active_winbar = vim.api.nvim_get_option_value("winbar", { win = active_win })
      local inactive_statusline = vim.api.nvim_get_option_value("statusline", { win = start_win })
      local inactive_winbar = vim.api.nvim_get_option_value("winbar", { win = start_win })

      vim.cmd("only")

      local ok = active_statusline:find("JigStatuslineActive", 1, true) ~= nil
        and inactive_statusline:find("JigStatuslineInactive", 1, true) ~= nil
        and active_winbar:find("JigWinbarActive", 1, true) ~= nil
        and inactive_winbar:find("JigWinbarInactive", 1, true) ~= nil

      return ok,
        {
          active_statusline = active_statusline,
          inactive_statusline = inactive_statusline,
          active_winbar = active_winbar,
          inactive_winbar = inactive_winbar,
        }
    end,
  },
  {
    id = "cmdline-open-close",
    labels = { "timing-sensitive" },
    retries = 3,
    retry_delay_ms = 80,
    run = function()
      local ok, details = cmdline.open_close_check()
      return ok, details
    end,
  },
  {
    id = "floating-design-policy",
    run = function()
      local _, first = float.open({ "first float" }, {
        level = "primary",
        row = 2,
        col = 6,
        width = 30,
        height = 4,
        title = "Primary",
      })
      local _, second = float.open({ "second float" }, {
        level = "secondary",
        row = 2,
        col = 6,
        width = 30,
        height = 4,
        title = "Secondary",
      })

      local first_conf = vim.api.nvim_win_get_config(first)
      local second_conf = vim.api.nvim_win_get_config(second)

      vim.api.nvim_win_close(second, true)
      vim.api.nvim_win_close(first, true)

      local first_row = as_number(first_conf.row)
      local second_row = as_number(second_conf.row)

      local border_is_valid = type(first_conf.border) == "string"
      if type(first_conf.border) == "table" then
        border_is_valid = #first_conf.border > 0
      end

      local ok = border_is_valid

      ok = ok and second_row >= first_row
      ok = ok and first_conf.zindex > second_conf.zindex and second_conf.zindex > 0

      return ok,
        {
          first = first_conf,
          second = second_conf,
          collision_shifted = second_row > first_row,
        }
    end,
  },
  {
    id = "ascii-fallback-legibility",
    run = function()
      local previous = vim.g.jig_icon_mode or "auto"
      icons.set_mode("nerd")
      require("jig.ui").reapply()
      local nerd_surface = command_surface()

      icons.set_mode("ascii")
      require("jig.ui").reapply()
      local ascii_surface = command_surface()

      local win = vim.api.nvim_get_current_win()
      local statusline = vim.api.nvim_get_option_value("statusline", { win = win })
      local winbar = vim.api.nvim_get_option_value("winbar", { win = win })

      local same_commands, mismatch = same_surface(nerd_surface, ascii_surface)
      local ok = icons.ascii_only(statusline) and icons.ascii_only(winbar) and same_commands

      vim.g.jig_icon_mode = previous
      require("jig.ui").reapply()

      return ok,
        {
          statusline = statusline,
          winbar = winbar,
          mismatched_command = mismatch,
          nerd_surface = nerd_surface,
          ascii_surface = ascii_surface,
        }
    end,
  },
}

local function run_case(case)
  local attempts = case.retries or 1
  local delay = case.retry_delay_ms or 0
  local last_details = {}

  for attempt = 1, attempts do
    local ok, passed, details = pcall(case.run)
    if ok and passed then
      return true,
        {
          attempts = attempt,
          labels = case.labels or {},
          details = details or {},
        }
    end
    last_details = details or { error = passed }
    if attempt < attempts and delay > 0 then
      vim.wait(delay)
    end
  end

  return false,
    {
      attempts = attempts,
      labels = case.labels or {},
      details = last_details,
    }
end

function M.run(opts)
  local report = {
    harness = "headless-child-ui",
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    cases = {},
  }

  local failed = {}
  for _, case in ipairs(cases) do
    local ok, case_result = run_case(case)
    report.cases[case.id] = {
      ok = ok,
      labels = case_result.labels,
      attempts = case_result.attempts,
      details = case_result.details,
    }
    if not ok then
      table.insert(failed, case.id)
    end
  end

  report.summary = {
    passed = #failed == 0,
    failed_cases = failed,
  }

  local path = snapshot_path(opts)
  write_snapshot(path, report)
  print("ui-harness snapshot written: " .. path)

  if #failed > 0 then
    error("UI harness failed: " .. table.concat(failed, ", "))
  end
end

return M
