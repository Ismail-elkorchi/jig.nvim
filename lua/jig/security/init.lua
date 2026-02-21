local net_guard = require("jig.security.net_guard")
local startup_phase = require("jig.security.startup_phase")

local M = {}

local initialized = false

function M.setup()
  if initialized then
    return
  end

  if vim.g.jig_safe_profile then
    vim.g.jig_security_enabled = false
    return
  end

  startup_phase.setup()
  net_guard.install_startup_hooks()
  vim.g.jig_security_enabled = true

  local fixture = net_guard.simulate_startup_network_attempt()
  if fixture ~= nil then
    vim.g.jig_security_startup_fixture = fixture
  end

  initialized = true
end

function M.is_startup()
  return startup_phase.is_startup()
end

function M.mark_startup_done(reason)
  startup_phase.mark_startup_done(reason)
end

return M
