local platform = require("jig.tools.platform")
local registry = require("jig.tools.registry")

local M = {}

local provider_matrix = {
  { key = "clipboard", label = "clipboard", has_flag = "clipboard" },
  { key = "python3", label = "python3 provider", has_flag = "python3" },
  { key = "nodejs", label = "node provider", has_flag = "nodejs" },
  { key = "ruby", label = "ruby provider", has_flag = "ruby" },
}

local shell_order = { "bash", "zsh", "fish", "pwsh", "powershell", "cmd" }

local function provider_status()
  local items = {}
  for _, provider in ipairs(provider_matrix) do
    local enabled = vim.fn.has(provider.has_flag) == 1
    table.insert(items, {
      key = provider.key,
      label = provider.label,
      enabled = enabled,
      hint = enabled and "" or "Run :checkhealth provider for setup guidance",
    })
  end
  return items
end

local function shell_status()
  local detected = platform.detect()
  local items = {}

  for _, name in ipairs(shell_order) do
    local shell = detected.shells[name]
    table.insert(items, {
      name = name,
      available = shell and shell.available == true,
      executable = shell and shell.executable or "",
      path = shell and shell.path or "",
    })
  end

  return {
    os = detected.os,
    shell = detected.shell,
    capabilities = detected.capabilities,
    shells = items,
  }
end

function M.summary()
  local shell = shell_status()
  local tools = registry.status({ os_class = shell.os.class })

  return {
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    shell = shell,
    tools = tools,
    providers = provider_status(),
    execution_policy = {
      argv_first = true,
      auto_install = false,
      auto_network_startup = false,
      wait_timeout_required = true,
      capture_concurrency_default = 1,
    },
  }
end

function M.lines()
  local report = M.summary()
  local lines = {
    "Jig Tool Health",
    string.rep("=", 48),
    string.format("os_class: %s", report.shell.os.class),
    string.format("configured_shell: %s", report.shell.shell.configured),
    string.format("configured_shell_kind: %s", report.shell.shell.kind),
    string.format("configured_shell_exists: %s", tostring(report.shell.shell.exists)),
    string.format("argv_first_execution: %s", tostring(report.execution_policy.argv_first)),
    string.format(
      "capture_concurrency_default: %d",
      tonumber(report.execution_policy.capture_concurrency_default) or -1
    ),
    "",
    "Shell matrix:",
  }

  for _, shell in ipairs(report.shell.shells) do
    local status = shell.available and "available" or "missing"
    local suffix = shell.available and (" via " .. shell.executable) or ""
    table.insert(lines, string.format("- %s: %s%s", shell.name, status, suffix))
  end

  table.insert(lines, "")
  table.insert(lines, "Providers:")
  for _, provider in ipairs(report.providers) do
    local state = provider.enabled and "ok" or "missing"
    local hint = provider.enabled and "" or ("; next: " .. provider.hint)
    table.insert(lines, string.format("- %s: %s%s", provider.label, state, hint))
  end

  table.insert(lines, "")
  table.insert(lines, "Tool registry:")
  for _, tool in ipairs(report.tools) do
    if tool.available then
      table.insert(
        lines,
        string.format("- %s (%s): ok via %s", tool.name, tool.level, tool.executable or tool.path)
      )
    else
      table.insert(
        lines,
        string.format("- %s (%s): missing; next: %s", tool.name, tool.level, tool.hint)
      )
    end
  end

  table.insert(lines, "")
  table.insert(lines, "Jig does not auto-install tools or run startup network actions.")

  return lines, report
end

function M.checkhealth()
  local lines, report = M.lines()
  vim.health.start("jig-tools")

  if report.shell.shell.exists then
    vim.health.ok(
      string.format(
        "configured shell detected: %s (%s)",
        report.shell.shell.configured,
        report.shell.shell.kind
      )
    )
  else
    vim.health.warn(
      "configured shell executable missing; run :JigToolHealth for shell matrix and hints"
    )
  end

  for _, provider in ipairs(report.providers) do
    if provider.enabled then
      vim.health.ok(provider.label .. " available")
    else
      vim.health.warn(provider.label .. " missing; " .. provider.hint)
    end
  end

  for _, tool in ipairs(report.tools) do
    if tool.available then
      vim.health.ok(string.format("%s (%s) detected", tool.name, tool.level))
    elseif tool.level == "required" then
      vim.health.warn(
        string.format("%s missing; affected commands degrade. next: %s", tool.name, tool.hint)
      )
    else
      vim.health.info(string.format("%s missing (%s); %s", tool.name, tool.level, tool.hint))
    end
  end

  vim.health.info(table.concat(lines, "\n"))
end

return M
