local config = require("jig.lsp.config")

local M = {}

local state = {
  policy = {},
  attached = {},
}

local function supports_inlay(client)
  return client
    and type(client.supports_method) == "function"
    and client:supports_method("textDocument/inlayHint")
end

function M.setup(policy)
  local defaults = config.get().inlay_hints or {}
  state.policy = vim.tbl_deep_extend("force", defaults, policy or {})
  state.attached = {}

  if type(vim.lsp.inlay_hint) == "table" and type(vim.lsp.inlay_hint.enable) == "function" then
    vim.lsp.inlay_hint.enable(state.policy.enabled == true)
  end

  return vim.deepcopy(state)
end

function M.on_attach(client, bufnr)
  if state.policy.enabled ~= true then
    return true, "disabled"
  end

  if type(vim.lsp.inlay_hint) ~= "table" or type(vim.lsp.inlay_hint.enable) ~= "function" then
    return false, "vim.lsp.inlay_hint.enable unavailable"
  end

  if not supports_inlay(client) then
    return true, "unsupported"
  end

  local ok, err = pcall(vim.lsp.inlay_hint.enable, true, { bufnr = bufnr })
  if not ok then
    return false, tostring(err)
  end

  state.attached[bufnr] = state.attached[bufnr] or {}
  state.attached[bufnr][client.id] = client.name
  return true, "enabled"
end

function M.state()
  return vim.deepcopy(state)
end

function M.reset_for_test()
  state = {
    policy = {},
    attached = {},
  }
end

return M
