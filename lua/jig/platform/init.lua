local clipboard = require("jig.platform.clipboard")
local fs = require("jig.platform.fs")
local os_platform = require("jig.platform.os")
local path = require("jig.platform.path")
local shell = require("jig.platform.shell")

local M = {
  clipboard = clipboard,
  fs = fs,
  os = os_platform,
  path = path,
  shell = shell,
}

function M.detect()
  local os = os_platform.detect()
  local shell_report = shell.detect()
  local clipboard_report = clipboard.detect()

  return {
    os = os,
    shell = shell_report.shell,
    shells = shell_report.shells,
    capabilities = shell_report.capabilities,
    clipboard = clipboard_report,
    stdpaths = fs.stdpaths(),
  }
end

function M.executable_path(command)
  return shell.executable_path(command)
end

return M
