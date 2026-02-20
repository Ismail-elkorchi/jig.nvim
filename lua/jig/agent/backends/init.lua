local acp_stdio = require("jig.agent.backends.acp_stdio")

local M = {}

local adapters = {
  [acp_stdio.name()] = acp_stdio,
}

function M.list()
  local names = {}
  for name in pairs(adapters) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

function M.get(name)
  return adapters[name]
end

function M.handshake(name, spec, opts)
  local adapter = M.get(name)
  if not adapter then
    return {
      ok = false,
      reason = "adapter_not_found",
    }
  end

  return adapter.handshake(spec, opts)
end

function M.prompt(name, spec, prompt, opts)
  local adapter = M.get(name)
  if not adapter then
    return {
      ok = false,
      reason = "adapter_not_found",
    }
  end

  return adapter.prompt(spec, prompt, opts)
end

return M
