local brand = require("jig.core.brand")
-- boundary: allow-vim-api

local M = {}

local function has_ui()
  return #vim.api.nvim_list_uis() > 0
end

local function docs_entries()
  return {
    { label = "Jig overview", help = "jig" },
    { label = "Install", help = "jig-install" },
    { label = "Configuration", help = "jig-configuration" },
    { label = "Commands", help = "jig-commands" },
    { label = "Workbench", help = "jig-workbench" },
    { label = "Keymaps", help = "jig-keymaps" },
    { label = "Troubleshooting", help = "jig-troubleshooting" },
    { label = "Migration", help = "jig-migration" },
    { label = "Release operations", help = "jig-release" },
    { label = "Rollback runbook", help = "jig-rollback" },
    { label = "Incident operations", help = "jig-incidents" },
    { label = "Safety model", help = "jig-safety" },
    { label = "LSP", help = "jig-lsp" },
    { label = "Tools", help = "jig-tools" },
    { label = "Security", help = "jig-security" },
    { label = "Platform", help = "jig-platform" },
    { label = "Testing", help = "jig-testing" },
    { label = "Agents (optional)", help = "jig-agents" },
  }
end

local function render_docs_lines(entries)
  local lines = {
    "Jig Documentation Index",
    string.rep("=", 28),
    "",
    "Primary help topics:",
  }

  for _, item in ipairs(entries) do
    lines[#lines + 1] = string.format("  - :help %s  (%s)", item.help, item.label)
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "Recovery shortcuts:"
  lines[#lines + 1] = "  - :JigWorkbench dev"
  lines[#lines + 1] = "  - :JigRepro"
  lines[#lines + 1] = "  - :JigBisectGuide"
  lines[#lines + 1] = "  - NVIM_APPNAME=jig-safe nvim"
  lines[#lines + 1] = "  - nvim --startuptime /tmp/jig.startuptime.log -u ./init.lua '+qa'"

  return lines
end

local function open_scratch(title, lines)
  local width = math.min(math.max(56, 80), math.max(56, vim.o.columns - 4))
  local height = math.min(#lines + 2, math.max(10, math.floor(vim.o.lines * 0.7)))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(1, math.floor((vim.o.lines - height) / 2)),
    col = math.max(1, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    border = "rounded",
    style = "minimal",
    title = title,
    title_pos = "left",
    zindex = 86,
  })

  return {
    buf = buf,
    win = win,
    lines = lines,
  }
end

local function line_help_target(line)
  if type(line) ~= "string" then
    return nil
  end
  local token = line:match(":help%s+([%w%-_]+)")
  if token and token ~= "" then
    return token
  end
  return nil
end

function M.open_docs_index(opts)
  opts = opts or {}
  local entries = docs_entries()
  local lines = render_docs_lines(entries)

  if not has_ui() and opts.force_scratch ~= true then
    vim.g.jig_docs_last = {
      lines = lines,
      entries = entries,
      mode = "headless",
    }
    print(table.concat(lines, "\n"))
    return vim.g.jig_docs_last
  end

  local state = open_scratch("Jig Docs", lines)

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_close(state.win, true)
    end
  end, { buffer = state.buf, silent = true, noremap = true })

  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(state.win)[1]
    local line = vim.api.nvim_buf_get_lines(state.buf, row - 1, row, false)[1] or ""
    local tag = line_help_target(line)
    if tag then
      vim.cmd("help " .. tag)
    end
  end, { buffer = state.buf, silent = true, noremap = true })

  vim.g.jig_docs_last = {
    lines = lines,
    entries = entries,
    buf = state.buf,
    win = state.win,
    mode = "ui",
  }
  return vim.g.jig_docs_last
end

function M.render_repro_lines()
  return {
    "Jig minimal repro (deterministic)",
    string.rep("=", 33),
    "",
    "1. Use isolated profile and dirs:",
    "   NVIM_APPNAME=jig-repro \\",
    "   XDG_CONFIG_HOME=$(mktemp -d) \\",
    "   XDG_DATA_HOME=$(mktemp -d) \\",
    "   XDG_STATE_HOME=$(mktemp -d) \\",
    "   XDG_CACHE_HOME=$(mktemp -d) \\",
    "   nvim --clean -u repro/minimal_init.lua",
    "",
    "2. Collect environment evidence:",
    "   nvim --version",
    "   nvim --headless -u ./init.lua '+checkhealth jig' '+qa'",
    "   nvim --headless -u ./init.lua '+JigHealth' '+qa'",
    "",
    "3. Recovery baseline:",
    "   NVIM_APPNAME=jig-safe nvim --headless -u ./init.lua '+JigDocs' '+qa'",
    "",
    "4. Startup timing trace (if startup issue):",
    "   nvim --startuptime /tmp/jig.startuptime.log -u ./init.lua '+qa'",
    "",
    "5. Attach outputs + exact repro steps in issue template.",
  }
end

function M.show_repro_steps()
  local lines = M.render_repro_lines()

  if not has_ui() then
    vim.g.jig_repro_last = {
      lines = lines,
      mode = "headless",
    }
    print(table.concat(lines, "\n"))
    return vim.g.jig_repro_last
  end

  local state = open_scratch("Jig Repro", lines)
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_close(state.win, true)
    end
  end, { buffer = state.buf, silent = true, noremap = true })

  vim.g.jig_repro_last = {
    lines = lines,
    buf = state.buf,
    win = state.win,
    mode = "ui",
  }

  return vim.g.jig_repro_last
end

function M.setup()
  vim.api.nvim_create_user_command(brand.command("Docs"), function()
    M.open_docs_index()
  end, {
    desc = "Open Jig documentation index",
  })

  vim.api.nvim_create_user_command(brand.command("Repro"), function()
    M.show_repro_steps()
  end, {
    desc = "Print deterministic minimal repro steps",
  })
end

return M
