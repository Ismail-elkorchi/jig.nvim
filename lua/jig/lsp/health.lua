local lifecycle = require("jig.lsp.lifecycle")
local snapshot = require("jig.lsp.snapshot")

local M = {}

local function sorted_server_names(servers)
  local names = {}
  for name in pairs(servers or {}) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

local function classify_server(server)
  if server.status == "enabled" then
    return "ok", string.format("%s: enabled", server.name)
  end

  if server.status == "disabled" then
    return "info", string.format("%s: disabled by policy", server.name)
  end

  local remediation = server.remediation and (" Next: " .. server.remediation) or ""
  return "warn",
    string.format("%s: %s.%s", server.name, server.message or server.status, remediation)
end

function M.evaluate()
  local status = lifecycle.summary()
  local snap = snapshot.capture()

  local report = {
    generated_at = snap.generated_at,
    initialized = status.initialized,
    active_servers = status.active_servers,
    degraded_servers = status.degraded_servers,
    registry_errors = status.registry_errors,
    lines = {},
    level = vim.log.levels.INFO,
  }

  if #status.registry_errors > 0 then
    report.level = vim.log.levels.ERROR
    table.insert(report.lines, "LSP registry validation failed:")
    for _, item in ipairs(status.registry_errors) do
      table.insert(report.lines, "- " .. item)
    end
    table.insert(report.lines, "Next: inspect server config and rerun :JigLspHealth")
  end

  for _, name in ipairs(sorted_server_names(status.servers)) do
    local kind, line = classify_server(status.servers[name])
    table.insert(report.lines, "- " .. line)
    if kind == "warn" and report.level < vim.log.levels.WARN then
      report.level = vim.log.levels.WARN
    end
  end

  table.insert(
    report.lines,
    string.format(
      "Summary: active=%d degraded=%d diagnostics=%d",
      status.active_servers,
      status.degraded_servers,
      snap.diagnostics.total
    )
  )
  table.insert(report.lines, "Next: :JigLspInfo for buffer attach state, :JigLspSnapshot for JSON")

  return report
end

function M.notify()
  local report = M.evaluate()
  vim.notify(table.concat(report.lines, "\n"), report.level)
  vim.g.jig_lsp_last_health = report
  return report
end

function M.checkhealth()
  local report = M.evaluate()
  vim.health.start("jig-lsp")

  if #report.registry_errors > 0 then
    vim.health.error("LSP registry validation failed")
    for _, item in ipairs(report.registry_errors) do
      vim.health.info(item)
    end
  end

  if report.active_servers > 0 then
    vim.health.ok(string.format("LSP active servers: %d", report.active_servers))
  else
    vim.health.warn("No active LSP servers")
  end

  if report.degraded_servers > 0 then
    vim.health.warn(string.format("LSP degraded servers: %d", report.degraded_servers))
  else
    vim.health.ok("No degraded LSP servers")
  end

  vim.health.info("Use :JigLspInfo for attach status and :JigLspSnapshot for full context JSON")
end

return M
