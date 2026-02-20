local platform = require("jig.tools.platform")

local M = {}

M.tools = {
  git = {
    level = "required",
    category = "scm",
    executables = { "git" },
    hints = {
      linux = "Example: sudo apt install git",
      macos = "Example: brew install git",
      windows = "Example: winget install Git.Git",
      wsl = "Example: sudo apt install git",
    },
  },
  rg = {
    level = "required",
    category = "search",
    executables = { "rg" },
    hints = {
      linux = "Example: sudo apt install ripgrep",
      macos = "Example: brew install ripgrep",
      windows = "Example: winget install BurntSushi.ripgrep.MSVC",
      wsl = "Example: sudo apt install ripgrep",
    },
  },
  fd = {
    level = "required",
    category = "filesystem",
    executables = { "fd", "fdfind" },
    hints = {
      linux = "Example: sudo apt install fd-find",
      macos = "Example: brew install fd",
      windows = "Example: winget install sharkdp.fd",
      wsl = "Example: sudo apt install fd-find",
    },
  },
  stylua = {
    level = "recommended",
    category = "formatter",
    executables = { "stylua" },
    hints = {
      linux = "Example: cargo install stylua",
      macos = "Example: brew install stylua",
      windows = "Example: cargo install stylua",
      wsl = "Example: cargo install stylua",
    },
  },
  luacheck = {
    level = "recommended",
    category = "linter",
    executables = { "luacheck" },
    hints = {
      linux = "Example: luarocks install luacheck",
      macos = "Example: luarocks install luacheck",
      windows = "Example: luarocks install luacheck",
      wsl = "Example: luarocks install luacheck",
    },
  },
  shellcheck = {
    level = "optional",
    category = "linter",
    executables = { "shellcheck" },
    hints = {
      linux = "Example: sudo apt install shellcheck",
      macos = "Example: brew install shellcheck",
      windows = "Example: choco install shellcheck",
      wsl = "Example: sudo apt install shellcheck",
    },
  },
}

local function sorted_names()
  local names = {}
  for name in pairs(M.tools) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

local function find_executable(executables)
  for _, executable in ipairs(executables or {}) do
    local path = platform.executable_path(executable)
    if path ~= "" then
      return true, executable, path
    end
  end
  return false, nil, ""
end

function M.get(name)
  local item = M.tools[name]
  if not item then
    return nil
  end
  return vim.deepcopy(item)
end

function M.is_available(name)
  local item = M.tools[name]
  if not item then
    return false, nil, ""
  end
  return find_executable(item.executables)
end

function M.install_hint(name, os_class)
  local item = M.tools[name]
  if not item then
    return ""
  end

  local class = os_class or platform.detect().os.class
  local hint = item.hints and item.hints[class] or ""
  if hint == "" then
    hint = "Example: install via your system package manager"
  end

  return hint
end

function M.status(opts)
  opts = opts or {}
  local os_class = opts.os_class or platform.detect().os.class
  local report = {}

  for _, name in ipairs(sorted_names()) do
    local item = M.tools[name]
    local available, executable, path = M.is_available(name)

    table.insert(report, {
      name = name,
      level = item.level,
      category = item.category,
      available = available,
      executable = executable,
      path = path,
      hint = M.install_hint(name, os_class),
    })
  end

  return report
end

return M
