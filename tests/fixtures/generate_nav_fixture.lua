local function repo_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h")
end

local ROOT = repo_root()
package.path = string.format("%s/lua/?.lua;%s/lua/?/init.lua;", ROOT, ROOT) .. package.path
vim.opt.rtp:prepend(ROOT)

local nav_fixture = require("jig.tests.fixtures.nav_repo")

local function parse(argv)
  local out = {
    tier = "small",
    base = ROOT .. "/tests/fixtures/generated",
  }

  local index = 1
  while index <= #argv do
    local token = argv[index]
    if token == "--tier" then
      out.tier = tostring(argv[index + 1] or out.tier)
      index = index + 2
    elseif token == "--base" then
      out.base = tostring(argv[index + 1] or out.base)
      index = index + 2
    else
      index = index + 1
    end
  end

  return out
end

local ok, err = pcall(function()
  local opts = parse(arg or {})
  local generated = nav_fixture.generate({
    tier = opts.tier,
    base_dir = opts.base,
  })
  print(vim.json.encode(generated))
end)

if not ok then
  vim.api.nvim_err_writeln(tostring(err))
  vim.cmd("cquit 1")
end

vim.cmd("qa")
