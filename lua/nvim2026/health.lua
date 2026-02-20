local M = {}

function M.check()
  vim.health.start("nvim-2026.dev")

  if vim.fn.has("nvim-0.11") == 1 then
    vim.health.ok("Neovim version >= 0.11")
  else
    vim.health.error("Neovim 0.11+ is required")
  end

  if vim.fn.executable("rg") == 1 then
    vim.health.ok("ripgrep detected")
  else
    vim.health.warn("ripgrep not found; grep picker performance/features reduced")
  end

  if vim.g.have_nerd_font then
    vim.health.ok("Nerd Font detected")
  else
    vim.health.info("Nerd Font not detected; ASCII icon fallback active")
  end
end

return M
