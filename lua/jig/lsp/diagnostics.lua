local config = require("jig.lsp.config")

local M = {}

local state = {
  policy = {},
}

function M.apply(policy)
  local defaults = config.get().diagnostics or {}
  local effective = vim.tbl_deep_extend("force", defaults, policy or {})

  vim.diagnostic.config(effective)
  state.policy = vim.deepcopy(effective)

  return vim.deepcopy(state.policy)
end

function M.state()
  return vim.deepcopy(state)
end

return M
