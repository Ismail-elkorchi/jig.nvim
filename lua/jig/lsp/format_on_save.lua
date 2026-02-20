local config = require("jig.lsp.config")

local M = {}

local state = {
  policy = {},
  buffers = {},
}

local function to_set(items)
  local out = {}
  for _, item in ipairs(items or {}) do
    if type(item) == "string" and item ~= "" then
      out[item] = true
    end
  end
  return out
end

local function filetype_allowed(bufnr)
  local ft = vim.bo[bufnr].filetype
  local allow = to_set(state.policy.allow_filetypes)
  local deny = to_set(state.policy.deny_filetypes)

  if next(allow) ~= nil and not allow[ft] then
    return false
  end

  if deny[ft] then
    return false
  end

  return true
end

local function supports_formatting(client)
  return client
    and type(client.supports_method) == "function"
    and client:supports_method("textDocument/formatting")
end

function M.setup(policy)
  local defaults = config.get().format_on_save or {}
  state.policy = vim.tbl_deep_extend("force", defaults, policy or {})
  state.buffers = {}
  return vim.deepcopy(state)
end

function M.on_attach(client, bufnr)
  if state.policy.enabled ~= true then
    return true, "disabled"
  end

  if not supports_formatting(client) then
    return true, "unsupported"
  end

  if not filetype_allowed(bufnr) then
    return true, "filetype-filtered"
  end

  local group_name = string.format("JigLspFormatOnSave_%d_%d", bufnr, client.id)
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })

  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    buffer = bufnr,
    callback = function()
      local ok, err = pcall(vim.lsp.buf.format, {
        bufnr = bufnr,
        id = client.id,
        timeout_ms = state.policy.timeout_ms or 1000,
        async = false,
      })

      if not ok then
        vim.notify(
          string.format("Jig LSP format-on-save failed (%s): %s", client.name, tostring(err)),
          vim.log.levels.WARN
        )
      end
    end,
    desc = "Jig format-on-save",
  })

  state.buffers[bufnr] = state.buffers[bufnr] or {}
  state.buffers[bufnr][client.id] = {
    client = client.name,
    group = group_name,
  }

  return true, "enabled"
end

function M.state()
  return vim.deepcopy(state)
end

function M.reset_for_test()
  state = {
    policy = {},
    buffers = {},
  }
end

return M
