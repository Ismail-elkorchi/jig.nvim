vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

local map = vim.keymap.set
local opts = { noremap = true, silent = true }

map("n", "<leader>qq", "<cmd>qa<cr>", vim.tbl_extend("force", opts, { desc = "Quit all" }))
map("n", "<leader>w", "<cmd>w<cr>", vim.tbl_extend("force", opts, { desc = "Write" }))
map("n", "<leader>e", "<cmd>Ex<cr>", vim.tbl_extend("force", opts, { desc = "File explorer" }))

map("n", "<leader>fd", function()
  vim.diagnostic.setloclist({ open = true })
end, vim.tbl_extend("force", opts, { desc = "Diagnostics list" }))

map(
  "n",
  "<leader>tt",
  "<cmd>terminal<cr>",
  vim.tbl_extend("force", opts, { desc = "Terminal current" })
)
map(
  "n",
  "<leader>th",
  "<cmd>split | terminal<cr>",
  vim.tbl_extend("force", opts, { desc = "Terminal horizontal" })
)
map(
  "n",
  "<leader>tv",
  "<cmd>vsplit | terminal<cr>",
  vim.tbl_extend("force", opts, { desc = "Terminal vertical" })
)

map("n", "]d", function()
  vim.diagnostic.jump({ count = 1, float = true })
end, vim.tbl_extend("force", opts, { desc = "Next diagnostic" }))

map("n", "[d", function()
  vim.diagnostic.jump({ count = -1, float = true })
end, vim.tbl_extend("force", opts, { desc = "Prev diagnostic" }))
