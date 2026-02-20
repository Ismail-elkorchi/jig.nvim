local M = {}

M.defaults = {
  markers = {
    "jig.root",
    ".git",
    "package.json",
    "pyproject.toml",
    "go.mod",
    "Cargo.toml",
    "Makefile",
  },
  candidate_cap = 500,
  large_repo_threshold = 15000,
  large_repo_cap = 200,
  fallback_select_cap = 200,
  ignore_globs = {
    "!.git/*",
    "!node_modules/*",
    "!dist/*",
    "!build/*",
    "!target/*",
    "!coverage/*",
    "!.cache/*",
  },
  enable_miller = false,
}

function M.get()
  local cfg = vim.deepcopy(M.defaults)
  if type(vim.g.jig_nav) == "table" then
    cfg = vim.tbl_deep_extend("force", cfg, vim.g.jig_nav)
  end
  return cfg
end

return M
