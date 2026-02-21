local M = {}

local function read_proc_version()
  local handle = io.open("/proc/version", "r")
  if not handle then
    return ""
  end

  local content = handle:read("*a") or ""
  handle:close()
  return content
end

local function normalize_arch(machine)
  local value = tostring(machine or ""):lower()
  if value == "x86_64" or value == "amd64" then
    return "x86_64"
  end
  if value == "aarch64" or value == "arm64" then
    return "arm64"
  end
  if value == "armv7l" or value == "armv8l" then
    return "arm"
  end
  return value ~= "" and value or "unknown"
end

function M.detect()
  local uname = vim.uv.os_uname() or {}
  local sysname = tostring(uname.sysname or ""):lower()

  local class = "linux"
  if sysname:find("windows", 1, true) then
    class = "windows"
  elseif sysname:find("darwin", 1, true) then
    class = "macos"
  end

  local is_wsl = false
  if class == "linux" then
    if (vim.env.WSL_DISTRO_NAME or "") ~= "" or (vim.env.WSL_INTEROP or "") ~= "" then
      is_wsl = true
    else
      local proc = read_proc_version():lower()
      is_wsl = proc:find("microsoft", 1, true) ~= nil
    end
  end

  if is_wsl then
    class = "wsl"
  end

  return {
    class = class,
    sysname = sysname,
    release = tostring(uname.release or ""),
    version = tostring(uname.version or ""),
    machine = tostring(uname.machine or ""),
    arch = normalize_arch(uname.machine),
    is_wsl = is_wsl,
    is_windows = class == "windows",
    is_macos = class == "macos",
    is_linux = class == "linux" or class == "wsl",
  }
end

function M.class()
  return M.detect().class
end

function M.arch()
  return M.detect().arch
end

function M.is_windows()
  return M.detect().is_windows
end

function M.is_macos()
  return M.detect().is_macos
end

function M.is_linux()
  return M.detect().is_linux
end

function M.is_wsl()
  return M.detect().is_wsl
end

return M
