local platform = require("jig.platform")

local M = {}

function M.detect()
  return platform.detect()
end

function M.classify_shell(shell)
  return platform.shell.classify(shell)
end

function M.parse_shell_executable(shell)
  return platform.shell.parse_executable(shell)
end

function M.executable_path(command)
  return platform.shell.executable_path(command)
end

return M
