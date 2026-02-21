local function repo_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h:h")
end

local ROOT = repo_root()

local ok, err = pcall(function()
  vim.cmd("helptags " .. vim.fn.fnameescape(ROOT .. "/doc"))
  print("helptags generated: " .. ROOT .. "/doc/tags")
end)

if not ok then
  vim.api.nvim_err_writeln(tostring(err))
  vim.cmd("cquit 1")
end

vim.cmd("qa")
