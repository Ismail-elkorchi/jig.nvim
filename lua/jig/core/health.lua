local M = {}
local brand = require("jig.core.brand")

function M.check()
  vim.health.start(brand.repo_slug)

  if vim.fn.has("nvim-0.11.2") == 1 then
    vim.health.ok("Neovim version >= 0.11.2")
  else
    vim.health.error("Neovim 0.11.2+ is required")
  end

  if vim.fn.executable("rg") == 1 then
    vim.health.ok("ripgrep detected")
  else
    vim.health.warn("ripgrep not found; install with: sudo apt install ripgrep")
  end

  if vim.fn.executable("git") == 1 then
    vim.health.ok("git detected")
  else
    vim.health.warn("git not found; affected commands degrade. next: sudo apt install git")
  end

  if vim.fn.executable("fd") == 1 then
    vim.health.ok("fd detected")
  else
    vim.health.warn(
      "fd not found; finder fallback is slower. install with: sudo apt install fd-find"
    )
  end

  if vim.fn.has("clipboard") == 1 then
    vim.health.ok("clipboard provider available")
  else
    vim.health.warn("clipboard provider missing; run :checkhealth provider for setup details")
  end

  if vim.fn.has("python3") == 1 then
    vim.health.ok("python3 provider available")
  else
    vim.health.warn("python3 provider missing; run :checkhealth provider")
  end

  if vim.fn.has("nodejs") == 1 then
    vim.health.ok("node provider available")
  else
    vim.health.warn("node provider missing; run :checkhealth provider")
  end

  if vim.g.have_nerd_font then
    vim.health.ok("Nerd Font detected")
  else
    vim.health.info("Nerd Font not detected; ASCII icon fallback active")
  end

  if vim.g.jig_safe_profile then
    vim.health.info("safe profile active; optional modules disabled")
  else
    vim.health.ok("default profile active")

    local ok_tools, tools_health = pcall(require, "jig.tools.health")
    if ok_tools and type(tools_health.checkhealth) == "function" then
      tools_health.checkhealth()
    else
      vim.health.warn("tool integration health unavailable")
    end

    local ok, lsp_health = pcall(require, "jig.lsp.health")
    if ok and type(lsp_health.checkhealth) == "function" then
      lsp_health.checkhealth()
    else
      vim.health.info("lsp subsystem not initialized")
    end
  end
end

return M
