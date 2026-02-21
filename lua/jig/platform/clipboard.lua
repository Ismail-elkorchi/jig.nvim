local M = {}

function M.detect()
  local has_clipboard = vim.fn.has("clipboard") == 1
  local unnamedplus = vim.opt.clipboard:get()
  local has_unnamedplus = false
  for _, item in ipairs(unnamedplus) do
    if item == "unnamedplus" then
      has_unnamedplus = true
      break
    end
  end

  return {
    available = has_clipboard,
    has_unnamedplus = has_unnamedplus,
    hint = has_clipboard and "" or "Clipboard provider missing. Run :checkhealth provider.",
  }
end

return M
