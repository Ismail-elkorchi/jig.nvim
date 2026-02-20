local platform = require("jig.tools.platform")

local M = {}

local function resolve_root_cwd()
  local ok, root = pcall(require, "jig.nav.root")
  if ok and type(root.resolve) == "function" then
    local resolved = root.resolve()
    if type(resolved) == "table" and type(resolved.root) == "string" and resolved.root ~= "" then
      return resolved.root
    end
  end
  return vim.uv.cwd()
end

local function resolve_buffer_cwd()
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" then
    return resolve_root_cwd()
  end

  if vim.fn.isdirectory(name) == 1 then
    return name
  end

  local dir = vim.fn.fnamemodify(name, ":p:h")
  if dir ~= "" and vim.fn.isdirectory(dir) == 1 then
    return dir
  end

  return resolve_root_cwd()
end

local function select_shell()
  local detected = platform.detect()
  if detected.shell.exists then
    return { detected.shell.executable }, detected.shell.kind
  end

  local order = { "bash", "zsh", "fish", "pwsh", "powershell", "cmd" }
  for _, kind in ipairs(order) do
    local shell = detected.shells[kind]
    if shell and shell.available then
      return { shell.executable }, kind
    end
  end

  return nil, "unknown"
end

local function shell_title(kind)
  if kind == "unknown" then
    return "unknown"
  end
  return kind
end

local function set_chrome(win, bufnr, kind)
  local statusline = table.concat({
    "%#JigUiAccent# TERM ",
    "%#JigUiNeutral#",
    shell_title(kind),
    " %<%f",
    "%=",
    "%#JigUiAction#",
    "%{mode()}",
    " ",
    "%#JigUiWarning#",
    "%{get(b:,'jig_term_state','running')}",
    " ",
  })

  local winbar = table.concat({
    "%#JigUiAccent# TERM ",
    "%#JigUiNeutral#",
    shell_title(kind),
    " ",
    "%#JigUiWarning#",
    "%{get(b:,'jig_term_state','running')}",
    " ",
  })

  vim.api.nvim_set_option_value("statusline", statusline, { win = win })
  vim.api.nvim_set_option_value("winbar", winbar, { win = win })
  vim.b[bufnr].jig_term_shell_kind = kind
end

local function mark_state(bufnr, text)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.b[bufnr].jig_term_state = text
  end
end

function M.open(opts)
  opts = opts or {}

  local scope = opts.scope or "root"
  local cwd = scope == "buffer" and resolve_buffer_cwd() or resolve_root_cwd()

  local shell_argv, shell_kind = select_shell()
  if shell_argv == nil then
    vim.notify(
      "No supported shell found. Run :JigToolHealth for shell detection details.",
      vim.log.levels.ERROR
    )
    return false, "missing_shell"
  end

  vim.cmd("botright split")
  local win = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_get_current_buf()

  vim.bo[bufnr].buflisted = false
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false

  mark_state(bufnr, "running")
  set_chrome(win, bufnr, shell_kind)

  local ok, job_or_err = pcall(vim.fn.jobstart, shell_argv, {
    cwd = cwd,
    term = true,
    on_exit = vim.schedule_wrap(function(_, code, _)
      local state = code == 0 and "exited:0" or ("exited:" .. tostring(code))
      mark_state(bufnr, state)
      local level = code == 0 and vim.log.levels.INFO or vim.log.levels.WARN
      vim.notify(
        string.format("JigTerm %s (%s) cwd=%s", state, shell_title(shell_kind), cwd),
        level
      )
    end),
  })

  if not ok or type(job_or_err) ~= "number" or job_or_err <= 0 then
    vim.notify("Failed to start terminal shell: " .. tostring(job_or_err), vim.log.levels.ERROR)
    return false, "spawn_error"
  end

  if #vim.api.nvim_list_uis() > 0 then
    vim.cmd("startinsert")
  end
  vim.notify(
    string.format("JigTerm running (%s) cwd=%s", shell_title(shell_kind), cwd),
    vim.log.levels.INFO
  )

  local state = {
    bufnr = bufnr,
    win = win,
    job_id = job_or_err,
    cwd = cwd,
    scope = scope,
    shell_kind = shell_kind,
  }

  vim.g.jig_term_last = state
  return true, state
end

return M
