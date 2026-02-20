local bootstrap = require("jig.core.bootstrap")

if not bootstrap.bootstrap() then
  return
end

require("jig.core.options")
require("jig.core.keymaps")
require("jig.core.autocmd")

if vim.g.jig_safe_profile then
  return
end

require("jig.core.lazy")
