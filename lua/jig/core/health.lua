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

  local exrc_enabled = vim.o.exrc == true
  local secure_enabled = vim.o.secure == true
  local modeline_enabled = vim.o.modeline == true

  vim.health.info(
    string.format(
      "local-config surfaces: exrc=%s secure=%s modeline=%s",
      tostring(exrc_enabled),
      tostring(secure_enabled),
      tostring(modeline_enabled)
    )
  )

  if exrc_enabled and not secure_enabled then
    vim.health.warn(
      "exrc is enabled without secure. What: local project configs may execute unsafe commands. "
        .. "Why: reduced isolation. Next: set secure or disable exrc."
    )
  elseif exrc_enabled and secure_enabled then
    vim.health.warn(
      "exrc is enabled. What: project-local configs execute with restrictions. "
        .. "Why: still increases local trust surface. Next: enable only for trusted projects."
    )
  else
    vim.health.ok("exrc disabled by default")
  end

  if modeline_enabled then
    vim.health.warn(
      "modeline is enabled. What: file-local modelines can change editor behavior. "
        .. "Why: adds local parsing surface. Next: disable modeline for stricter posture if needed."
    )
  else
    vim.health.ok("modeline disabled")
  end

  local trace_enabled = vim.env.JIG_TRACE_STARTUP_NET == "1"
    or vim.env.JIG_TRACE_STARTUP_NET == "true"
  local strict_trace = vim.env.JIG_STRICT_STARTUP_NET == "1"
    or vim.env.JIG_STRICT_STARTUP_NET == "true"
  vim.health.info(
    string.format(
      "startup network trace: enabled=%s strict=%s",
      tostring(trace_enabled),
      tostring(strict_trace)
    )
  )

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
