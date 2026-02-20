local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  { import = "nvim2026.plugins" },
}, {
  checker = { enabled = false },
  change_detection = { notify = false },
})

vim.api.nvim_create_user_command("Nvim2026Channel", function(opts)
  local channel = opts.args
  if channel ~= "stable" and channel ~= "edge" then
    vim.notify("Usage: :Nvim2026Channel stable|edge", vim.log.levels.ERROR)
    return
  end
  vim.g.nvim2026_channel = channel
  vim.notify("Channel set to " .. channel .. ". Restart Neovim.")
end, { nargs = 1, complete = function() return { "stable", "edge" } end })
