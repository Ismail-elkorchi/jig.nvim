local os_platform = require("jig.platform.os")
local path = require("jig.platform.path")

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

function M.parse_executable(shell)
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

function M.executable_path(cmd)
  if type(cmd) ~= "string" or cmd == "" then
    return ""
  end

  local clean = trim_quotes(cmd)
  local resolved = vim.fn.exepath(clean)
  if resolved ~= "" then
    return resolved
  end

  if clean:find("/") or clean:find("\\") then
    if vim.uv.fs_stat(clean) ~= nil then
      return clean
    end
  end

  return ""
end

function M.classify(shell)
  local executable = M.parse_executable(shell)
  local name = path.basename(path.to_slash(executable)):lower():gsub("%.exe$", "")
  if shell_candidates[name] ~= nil then
    return name
  end
  if name == "" then
    return "unknown"
  end
  return "unknown"
end

function M.available_shells()
  local items = {}
  for kind, candidates in pairs(shell_candidates) do
    local found = ""
    local selected = ""
    for _, executable in ipairs(candidates) do
      local candidate_path = M.executable_path(executable)
      if candidate_path ~= "" then
        found = candidate_path
        selected = executable
        break
      end
    end

    items[kind] = {
      kind = kind,
      available = found ~= "",
      executable = selected,
      path = found,
    }
  end
  return items
end

function M.configured_shell()
  local configured = vim.o.shell
  local executable = M.parse_executable(configured)
  local detected_path = M.executable_path(executable)
  local kind = M.classify(executable)

  return {
    configured = configured,
    executable = executable,
    exists = detected_path ~= "",
    path = detected_path,
    kind = kind,
  }
end

function M.detect()
  local os = os_platform.detect()
  local shells = M.available_shells()
  local configured = M.configured_shell()

  return {
    os = os,
    shell = configured,
    shells = shells,
    capabilities = {
      argv_execution = true,
      shell_kind = configured.kind,
      shell_configured = configured.configured,
      shell_exists = configured.exists,
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
    },
  }
end

function M.run_one_liner(kind, expression)
  local value = tostring(expression or "")
  if kind == "bash" or kind == "zsh" then
    return { kind, "-lc", value }
  end
  if kind == "fish" then
    return { "fish", "-c", value }
  end
  if kind == "pwsh" then
    return { "pwsh", "-NoProfile", "-NonInteractive", "-Command", value }
  end
  if kind == "powershell" then
    return { "powershell", "-NoProfile", "-NonInteractive", "-Command", value }
  end
  if kind == "cmd" then
    return { "cmd", "/d", "/s", "/c", value }
  end
  return nil
end

return M
