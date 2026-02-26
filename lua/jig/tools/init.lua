local brand = require("jig.core.brand")
local health = require("jig.tools.health")
local system = require("jig.tools.system")
local terminal = require("jig.tools.terminal")
local toolchain = require("jig.tools.toolchain")

local M = {}

local commands_registered = false

local function open_scratch(title, lines)
  local payload = vim.deepcopy(lines or {})
  if #payload == 0 then
    payload = { "<empty>" }
  end

  if #vim.api.nvim_list_uis() == 0 then
    vim.g.jig_tools_last_lines = payload
    print(string.format("%s (%d lines)", title, #payload))
    return {
      headless = true,
      lines = payload,
    }
  end

  vim.cmd("botright new")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = "jigreport"
  vim.api.nvim_buf_set_name(bufnr, title)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, payload)
  vim.bo[bufnr].modifiable = false

  return {
    bufnr = bufnr,
    headless = false,
    lines = payload,
  }
end

local function parse_exec_args(opts)
  local argv = {}
  for _, item in ipairs(opts.fargs or {}) do
    table.insert(argv, item)
  end
  return argv
end

local function cmd_exec(opts)
  local argv = parse_exec_args(opts)
  local result = system.run_sync(argv, {
    timeout_ms = vim.g.jig_exec_timeout_ms,
    actor = "user",
    origin = "jig.exec",
    override_destructive = opts.bang == true,
  })

  local lines = system.format_result_lines(result)
  local state = open_scratch("JigExec", lines)
  state.result = result
  vim.g.jig_exec_last = state
end

local function cmd_tool_health()
  local lines, report = health.lines()
  local state = open_scratch("JigToolHealth", lines)
  state.report = report
  vim.g.jig_tool_health_last = state
end

local function cmd_term(opts)
  local scope = opts.args ~= "" and opts.args or "root"
  if scope ~= "root" and scope ~= "buffer" then
    vim.notify("Usage: :JigTerm [root|buffer]", vim.log.levels.ERROR)
    return
  end

  local ok, state_or_err = terminal.open({ scope = scope })
  if ok then
    vim.g.jig_term_last = state_or_err
    return
  end

  vim.g.jig_term_last = {
    ok = false,
    error = state_or_err,
  }
end

local function open_toolchain_report(title, report)
  local lines = toolchain.render_action_lines(report)
  local state = open_scratch(title, lines)
  state.report = report
  vim.g.jig_toolchain_last = state
  if report.ok ~= true then
    vim.notify(
      title .. " failed; inspect report buffer or run :JigToolHealth for drift details",
      vim.log.levels.WARN
    )
  end
  return state
end

local function cmd_toolchain_install()
  local report = toolchain.install({
    actor = "user",
    origin = "jig.toolchain.install",
  })
  open_toolchain_report("JigToolchainInstall", report)
end

local function cmd_toolchain_update()
  local report = toolchain.update({
    actor = "user",
    origin = "jig.toolchain.update",
  })
  open_toolchain_report("JigToolchainUpdate", report)
end

local function cmd_toolchain_restore()
  local report = toolchain.restore({
    actor = "user",
    origin = "jig.toolchain.restore",
  })
  open_toolchain_report("JigToolchainRestore", report)
end

local function cmd_toolchain_rollback()
  local report = toolchain.rollback({
    actor = "user",
    origin = "jig.toolchain.rollback",
  })
  open_toolchain_report("JigToolchainRollback", report)
end

local function create_command(name, callback, opts)
  if vim.fn.exists(":" .. name) == 2 then
    return
  end
  vim.api.nvim_create_user_command(name, callback, opts)
end

function M.setup()
  if vim.g.jig_safe_profile then
    return
  end

  if commands_registered then
    return
  end

  create_command(brand.command("Exec"), cmd_exec, {
    nargs = "+",
    bang = true,
    complete = "shellcmd",
    desc = "Run command via Jig system wrapper and show deterministic result",
  })

  create_command(brand.command("ToolHealth"), cmd_tool_health, {
    nargs = 0,
    desc = "Show shell, provider, and external tool integration summary",
  })

  create_command(brand.command("Term"), cmd_term, {
    nargs = "?",
    complete = function()
      return { "root", "buffer" }
    end,
    desc = "Open integrated terminal (default root or buffer directory)",
  })

  create_command(brand.command("ToolchainInstall"), cmd_toolchain_install, {
    nargs = 0,
    desc = "Install toolchain from manifest and write toolchain lockfile",
  })

  create_command(brand.command("ToolchainUpdate"), cmd_toolchain_update, {
    nargs = 0,
    desc = "Update toolchain lock state from manifest with explicit command",
  })

  create_command(brand.command("ToolchainRestore"), cmd_toolchain_restore, {
    nargs = 0,
    desc = "Restore toolchain to versions pinned in toolchain lockfile",
  })

  create_command(brand.command("ToolchainRollback"), cmd_toolchain_rollback, {
    nargs = 0,
    desc = "Restore previous toolchain lock backup and re-apply",
  })

  commands_registered = true
end

return M
