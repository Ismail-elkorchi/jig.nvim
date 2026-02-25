local brand = require("jig.core.brand")
local channel_state = require("jig.core.channel")
local plugin_state = require("jig.core.plugin_state")

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local function lazy_available()
  return vim.uv.fs_stat(lazypath) ~= nil
end

local function install_lazy()
  local system = require("jig.tools.system")
  local result = system.run_sync({
    "git",
    "clone",
    "--filter=blob:none",
    "--branch=stable",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  }, {
    timeout_ms = 20000,
    actor = "user",
    origin = "plugin-manager.bootstrap",
    allow_network = true,
  })

  if result.ok ~= true then
    local stderr = (result.stderr or ""):gsub("%s+$", "")
    local extra = stderr ~= "" and ("\n" .. stderr) or ""
    vim.notify("Failed to install lazy.nvim" .. extra, vim.log.levels.ERROR)
    return
  end

  vim.notify("lazy.nvim installed. Restart Neovim, then run :Lazy sync.", vim.log.levels.INFO)
end

local channel_boot = channel_state.initialize()
if channel_boot.error ~= nil then
  vim.notify(
    string.format(
      "Invalid persisted channel state (%s). Falling back to '%s'.",
      channel_boot.error,
      channel_boot.channel
    ),
    vim.log.levels.WARN
  )
end

-- boundary: allow-vim-api
-- Justification: user command registration is part of Neovim host integration.
vim.api.nvim_create_user_command(brand.command("PluginBootstrap"), function()
  if vim.uv.fs_stat(lazypath) then
    vim.notify("lazy.nvim already installed at " .. lazypath, vim.log.levels.INFO)
    return
  end
  install_lazy()
end, {
  desc = "Install lazy.nvim explicitly (no startup auto-install)",
})

plugin_state.register({
  lazypath = lazypath,
  bootstrap_command = brand.command("PluginBootstrap"),
})

-- boundary: allow-vim-api
-- Justification: user command registration is part of Neovim host integration.
vim.api.nvim_create_user_command(brand.command("Channel"), function(opts)
  local channel = vim.trim(opts.args or "")
  if channel == "" then
    local source = vim.fn.filereadable(channel_state.path()) == 1 and "state" or "default"
    vim.notify(
      string.format(
        "%s channel: %s (source=%s path=%s)",
        brand.brand,
        channel_state.current(),
        source,
        channel_state.path()
      ),
      vim.log.levels.INFO
    )
    return
  end

  local ok, result = channel_state.set(channel, { persist = true })
  if not ok then
    vim.notify("Usage: :" .. brand.command("Channel") .. " [stable|edge]", vim.log.levels.ERROR)
    return
  end

  if not lazy_available() then
    vim.notify(
      "Channel persisted to "
        .. result.path
        .. ", but lazy.nvim is not installed. Run :"
        .. brand.command("PluginBootstrap")
        .. ".",
      vim.log.levels.WARN
    )
    return
  end
  vim.notify(
    brand.brand .. " channel set to " .. result.channel .. ". Persisted at " .. result.path .. "."
  )
end, {
  nargs = "?",
  complete = function()
    return { "stable", "edge" }
  end,
  desc = "Set or show update channel metadata (stable|edge)",
})

if not lazy_available() then
  vim.notify(
    "lazy.nvim not found. Run :" .. brand.command("PluginBootstrap") .. " to install plugins.",
    vim.log.levels.WARN
  )
  return
end

vim.opt.rtp:prepend(lazypath)

require("lazy").setup({ { import = "jig.plugins" } }, {
  checker = { enabled = false },
  change_detection = { notify = false },
})
