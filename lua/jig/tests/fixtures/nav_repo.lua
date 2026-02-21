local path = require("jig.platform.path")

local M = {}

local SPECS = {
  small = {
    dirs = 10,
    files_per_dir = 12,
    marker = "tier-small",
  },
  medium = {
    dirs = 20,
    files_per_dir = 36,
    marker = "tier-medium",
  },
  large = {
    dirs = 28,
    files_per_dir = 60,
    marker = "tier-large",
  },
}

local function write(pathname, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(pathname, ":h"), "p")
  vim.fn.writefile(lines, pathname)
end

local function tier_root(base, tier)
  return path.join(base, tier)
end

local function ensure_markers(root, marker)
  write(path.join(root, "jig.root"), { marker })
  write(path.join(root, ".git", "HEAD"), { "ref: refs/heads/main" })
  write(path.join(root, ".gitignore"), {
    "build/",
    "node_modules/",
    "*.tmp",
  })
end

local function create_files(root, tier, spec)
  local count = 0
  for d = 1, spec.dirs do
    local dirname = string.format("pkg_%02d", d)
    local dir = path.join(root, "src", dirname)
    vim.fn.mkdir(dir, "p")

    for i = 1, spec.files_per_dir do
      count = count + 1
      local filename = string.format("mod_%04d.lua", i)
      local filepath = path.join(dir, filename)
      write(filepath, {
        string.format("-- fixture tier=%s dir=%s index=%d", tier, dirname, i),
        string.format("return %d", count),
      })
    end
  end

  write(path.join(root, "README.md"), {
    "# Navigation Fixture",
    "",
    "tier: " .. tier,
    "files: " .. tostring(count),
  })

  return count
end

function M.specs()
  return vim.deepcopy(SPECS)
end

function M.generate(opts)
  opts = opts or {}
  local tier = tostring(opts.tier or "small")
  local spec = SPECS[tier]
  assert(spec ~= nil, "unknown tier: " .. tier)

  local base = opts.base_dir or (vim.fn.stdpath("state") .. "/jig/nav-fixtures")
  local root = tier_root(base, tier)

  if vim.fn.isdirectory(root) == 1 then
    return {
      root = root,
      tier = tier,
      files = tonumber(vim.fn.len(vim.fn.globpath(root, "**/*.lua", false, true))) or 0,
      reused = true,
    }
  end

  vim.fn.mkdir(root, "p")
  ensure_markers(root, spec.marker)
  local files = create_files(root, tier, spec)

  return {
    root = root,
    tier = tier,
    files = files,
    reused = false,
  }
end

return M
