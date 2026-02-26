local approvals = require("jig.agent.approvals")
local agent_config = require("jig.agent.config")
local instructions = require("jig.agent.instructions")
local log = require("jig.agent.log")
local mcp_config = require("jig.agent.mcp.config")
local patch = require("jig.agent.patch")
local policy = require("jig.agent.policy")

local M = {}

function M.summary(opts)
  local cfg = agent_config.get(opts)
  local instruction_report = instructions.collect(opts)
  local mcp_report = mcp_config.discover(opts)

  return {
    enabled = cfg.enabled == true,
    root = cfg.root,
    policy_path = policy.path(),
    approvals_path = approvals.path(),
    log_path = log.path(),
    patch_path = patch.path(),
    instructions_state_path = instructions.path(),
    instruction_sources = instruction_report.sources,
    mcp_files = mcp_report.files,
    mcp_server_count = vim.tbl_count(mcp_report.servers),
  }
end

function M.checkhealth(opts)
  local report = M.summary(opts)
  vim.health.start("jig-agent")

  if report.enabled then
    vim.health.ok("agent module enabled")
  else
    vim.health.info("agent module disabled (default)")
  end

  vim.health.info("policy store: " .. report.policy_path)
  vim.health.info("approval queue store: " .. report.approvals_path)
  vim.health.info("patch session store: " .. report.patch_path)
  vim.health.info("instruction state store: " .. report.instructions_state_path)
  vim.health.info("evidence log: " .. report.log_path)
  vim.health.info("mcp discovered servers: " .. tostring(report.mcp_server_count))

  local loaded = 0
  for _, source in ipairs(report.instruction_sources) do
    if source.exists then
      loaded = loaded + 1
    end
  end
  vim.health.info("instruction files loaded: " .. tostring(loaded))
end

return M
