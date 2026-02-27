local function fail(message)
  vim.api.nvim_err_writeln(message)
  vim.cmd("cquit 1")
end

local root = vim.fn.getcwd()
_G.__jig_repo_root = root
package.path = string.format("%s/lua/?.lua;%s/lua/?/init.lua;", root, root) .. package.path

local ok, checker = pcall(require, "jig.workbench.research_check")
if not ok then
  fail("failed to load workbench research checker: " .. tostring(checker))
end

local passed, payload = checker.run({ root = root })
if not passed then
  local errors = payload and payload.errors or { "unknown error" }
  fail("workbench research gate failed:\n - " .. table.concat(errors, "\n - "))
end

print("workbench research gate passed")
vim.cmd("qa")
