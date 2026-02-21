-- Minimal reproducible init for Jig issue reports.
-- Intentionally plugin-free and deterministic.

vim.o.swapfile = false
vim.o.hidden = true
vim.o.updatetime = 200

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    print("jig-repro-minimal init loaded")
    print("nvim version: " .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch)
    print("appname: " .. vim.fn.getenv("NVIM_APPNAME"))
  end,
})
