local M = {}

local shell_candidates = {
  bash = { "bash" },
  zsh = { "zsh" },
  fish = { "fish" },
  pwsh = { "pwsh", "pwsh.exe" },
  powershell = { "powershell", "powershell.exe" },
  cmd = { "cmd", "cmd.exe" },
}

local function trim_quotes(value)
  if type(value) ~= "string" then
    return ""
  end
  return value:gsub("^['\"]", ""):gsub("['\"]$", "")
end

local function parse_shell_executable(shell)
  if type(shell) ~= "string" or shell == "" then
    return ""
  end

  local quoted = shell:match("^\"([^\"]+)\"") or shell:match("^'([^']+)'")
  if quoted then
    return quoted
  end

  local token = shell:match("^%S+")
  return token or shell
end

local function executable_path(cmd)
  if type(cmd) ~= "string" or cmd == "" then
    return ""
  end

  local clean = trim_quotes(cmd)
  local path = vim.fn.exepath(clean)
  if path ~= "" then
    return path
  end

  if clean:find("/") or clean:find("\\") then
    if vim.uv.fs_stat(clean) ~= nil then
      return clean
    end
  end

  return ""
end

local function basename(path)
  if type(path) ~= "string" or path == "" then
    return ""
  end
  local normalized = path:gsub("\\", "/")
  local value = normalized:match("([^/]+)$") or normalized
  value = value:lower():gsub("%.exe$", "")
  return value
end

local function classify_shell(shell)
  local name = basename(parse_shell_executable(shell))
  if name == "bash" then
    return "bash"
  end
  if name == "zsh" then
    return "zsh"
  end
  if name == "fish" then
    return "fish"
  end
  if name == "pwsh" then
    return "pwsh"
  end
  if name == "powershell" then
    return "powershell"
  end
  if name == "cmd" then
    return "cmd"
  end
  if name == "" then
    return "unknown"
  end
  return "unknown"
end

local function read_proc_version()
  local handle = io.open("/proc/version", "r")
  if not handle then
    return ""
  end
  local content = handle:read("*a") or ""
  handle:close()
  return content
end

local function detect_os()
  local uname = vim.uv.os_uname()
  local sysname = (uname and uname.sysname or ""):lower()

  local class = "linux"
  if sysname:find("windows", 1, true) then
    class = "windows"
  elseif sysname:find("darwin", 1, true) then
    class = "macos"
  end

  local is_wsl = false
  if class == "linux" then
    local markers = {
      vim.env.WSL_DISTRO_NAME,
      vim.env.WSL_INTEROP,
    }
    for _, value in ipairs(markers) do
      if type(value) == "string" and value ~= "" then
        is_wsl = true
        break
      end
    end

    if not is_wsl then
      local version = read_proc_version():lower()
      if version:find("microsoft", 1, true) then
        is_wsl = true
      end
    end
  end

  if is_wsl then
    class = "wsl"
  end

  return {
    class = class,
    is_wsl = is_wsl,
    sysname = sysname,
  }
end

local function detect_shells()
  local shells = {}
  for kind, candidates in pairs(shell_candidates) do
    local found = ""
    local selected = ""
    for _, executable in ipairs(candidates) do
      local path = executable_path(executable)
      if path ~= "" then
        found = path
        selected = executable
        break
      end
    end

    shells[kind] = {
      kind = kind,
      available = found ~= "",
      executable = selected,
      path = found,
    }
  end

  return shells
end

function M.detect()
  local os = detect_os()
  local configured_shell = vim.o.shell
  local configured_exec = parse_shell_executable(configured_shell)
  local configured_path = executable_path(configured_exec)
  local configured_kind = classify_shell(configured_exec)
  local shells = detect_shells()

  local capabilities = {
    argv_execution = true,
    shell_kind = configured_kind,
    shell_configured = configured_shell,
    shell_exists = configured_path ~= "",
    os_class = os.class,
    is_wsl = os.is_wsl,
    supports = {
      posix = shells.bash.available or shells.zsh.available or shells.fish.available,
      powershell = shells.pwsh.available or shells.powershell.available,
      cmd = shells.cmd.available,
    },
    available_shells = {
      bash = shells.bash.available,
      zsh = shells.zsh.available,
      fish = shells.fish.available,
      pwsh = shells.pwsh.available,
      powershell = shells.powershell.available,
      cmd = shells.cmd.available,
    },
  }

  return {
    os = os,
    shell = {
      configured = configured_shell,
      executable = configured_exec,
      exists = configured_path ~= "",
      path = configured_path,
      kind = configured_kind,
    },
    shells = shells,
    capabilities = capabilities,
  }
end

function M.classify_shell(shell)
  return classify_shell(shell)
end

function M.parse_shell_executable(shell)
  return parse_shell_executable(shell)
end

function M.executable_path(command)
  return executable_path(command)
end

return M
