local bootstrap = require("jig.core.bootstrap")

if not bootstrap.bootstrap() then
  return
end

require("jig.core.options")

if not vim.g.jig_safe_profile then
  require("jig.ui").setup()
end

require("jig.core.keymaps")
require("jig.core.autocmd")
require("jig.core.doctor").setup()

if vim.g.jig_safe_profile then
  return
end

require("jig.nav").setup()
require("jig.core.lazy")
