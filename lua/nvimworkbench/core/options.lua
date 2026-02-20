local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.wrap = false
opt.termguicolors = true
opt.updatetime = 200
opt.timeoutlen = 300
opt.splitright = true
opt.splitbelow = true
opt.mouse = "a"
opt.clipboard = "unnamedplus"
opt.ignorecase = true
opt.smartcase = true

if vim.loader and vim.loader.enable then
  vim.loader.enable()
end

local function has_nerd_font()
  local patterns = {
    "~/.local/share/fonts/NerdFonts/*/*NerdFont*.ttf",
    "~/.local/share/fonts/*NerdFont*.ttf",
    "~/.fonts/*NerdFont*.ttf",
  }
  for _, p in ipairs(patterns) do
    if vim.fn.glob(p) ~= "" then
      return true
    end
  end
  return false
end

vim.g.have_nerd_font = has_nerd_font()
