local M = {}

M.registry = {
  {
    id = "S0-R01",
    section = 0,
    level = "MUST",
    text = "Jig must provide a portable, maintainable Neovim configuration system.",
    owner = "core.bootstrap",
    verification = "nvim --headless -u ./init.lua '+qa'",
    falsifier = "startup requires machine-local manual patching or undocumented steps",
  },
  {
    id = "S0-R02",
    section = 0,
    level = "MUST_NOT",
    text = "Jig must not force a single workflow ideology.",
    owner = "core.bootstrap",
    verification = "docs/contract.jig.nvim.md references optional modules and defaults",
    falsifier = "core startup hard-requires optional workflow modules",
  },
  {
    id = "S1-R01",
    section = 1,
    level = "MUST",
    text = "Jig must enforce a minimum supported Neovim version with deterministic diagnostics.",
    owner = "core.bootstrap",
    verification = "nvim --headless -u ./init.lua '+lua print(vim.g.jig_boot_ok)' '+qa'",
    falsifier = "unsupported Neovim version reaches plugin initialization path",
  },
  {
    id = "S1-R02",
    section = 1,
    level = "SHOULD",
    text = "Jig should support isolated profiles via NVIM_APPNAME.",
    owner = "core.bootstrap",
    verification = "NVIM_APPNAME=jig nvim --headless -u ./init.lua '+qa'",
    falsifier = "profile data/state collide across different NVIM_APPNAME values",
  },
  {
    id = "S2-R01",
    section = 2,
    level = "MUST",
    text = "Plugin install/update/restore operations must be explicit.",
    owner = "core.lazy",
    verification = ":JigPluginInstall, :JigPluginUpdate, :JigPluginRestore, :JigPluginRollback",
    falsifier = "startup triggers install/update without explicit user command",
  },
  {
    id = "S2-R02",
    section = 2,
    level = "MUST_NOT",
    text = "Startup must not auto-install plugins by default.",
    owner = "core.lazy",
    verification = "lazy bootstrap path returns guidance instead of cloning on startup",
    falsifier = "cold startup executes git clone/fetch as implicit side effect",
  },
  {
    id = "S3-R01",
    section = 3,
    level = "MUST",
    text = "Jig must provide a doctor entrypoint for actionable troubleshooting.",
    owner = "core.health",
    verification = "nvim --headless -u ./init.lua '+checkhealth jig' '+qa'",
    falsifier = "health checks report failures without actionable next step",
  },
  {
    id = "S3-R02",
    section = 3,
    level = "SHOULD",
    text = "Jig should provide a safe-mode startup entrypoint.",
    owner = "core.bootstrap",
    verification = "NVIM_APPNAME=jig-safe nvim --headless -u ./init.lua '+qa'",
    falsifier = "safe profile loads optional modules that are expected to be disabled",
  },
  {
    id = "S4-R01",
    section = 4,
    level = "MUST",
    text = "Missing providers and binaries must be surfaced with guidance.",
    owner = "core.health",
    verification = "nvim --headless -u ./init.lua '+checkhealth jig' '+qa'",
    falsifier = "missing provider is silent or causes non-actionable crash",
  },
  {
    id = "S5-R01",
    section = 5,
    level = "MUST",
    text = "Startup must avoid heavy eager work and unnecessary side effects.",
    owner = "core.lazy",
    verification = "nvim --startuptime /tmp/jig.startup.log -u ./init.lua '+qa'",
    falsifier = "core startup path performs eager network or large module loading without need",
  },
  {
    id = "S6-R01",
    section = 6,
    level = "MUST",
    text = "Default commands and keymaps must be documented and discoverable.",
    owner = "docs.keymaps",
    verification = "rg -n \"Jig\" docs/keymaps.jig.nvim.md",
    falsifier = "default command/keymap exists with no documentation entry",
  },
  {
    id = "S7-R01",
    section = 7,
    level = "MUST",
    text = "Startup must not execute network operations by default.",
    owner = "core.lazy",
    verification = "core lazy bootstrap policy emits guidance and does not auto-clone",
    falsifier = "startup path performs remote fetch/clone without explicit consent",
  },
  {
    id = "S8-R01",
    section = 8,
    level = "MUST",
    text = "Jig must remain modular and allow user overrides without core patching.",
    owner = "core.bootstrap",
    verification = "lua/jig paths are layered (core, plugins) and documented in docs/architecture.jig.nvim.md",
    falsifier = "core behavior can only be changed by editing internal module files",
  },
  {
    id = "S9-R01",
    section = 9,
    level = "MAY",
    text = "Agent integrations are optional and removable extensions.",
    owner = "agent.optional",
    verification = "docs/architecture.jig.nvim.md marks agent path as optional extension",
    falsifier = "core startup fails when optional agent module is absent",
  },
}

local required_fields = {
  "id",
  "section",
  "level",
  "text",
  "owner",
  "verification",
  "falsifier",
}

local function as_string(value)
  if type(value) == "string" then
    return value
  end
  return tostring(value)
end

function M.validate()
  local errors = {}
  local seen_ids = {}
  local covered_sections = {}

  for index, entry in ipairs(M.registry) do
    for _, key in ipairs(required_fields) do
      local value = entry[key]
      if value == nil or as_string(value) == "" then
        table.insert(errors, string.format("entry %d missing required field '%s'", index, key))
      end
    end

    if type(entry.id) == "string" and entry.id ~= "" then
      if seen_ids[entry.id] then
        table.insert(errors, string.format("duplicate requirement id '%s'", entry.id))
      end
      seen_ids[entry.id] = true
    end

    if type(entry.section) ~= "number" or entry.section < 0 or entry.section > 9 then
      table.insert(
        errors,
        string.format("entry %d has invalid section '%s'", index, as_string(entry.section))
      )
    else
      covered_sections[entry.section] = true
    end
  end

  for section = 0, 9 do
    if not covered_sections[section] then
      table.insert(errors, string.format("missing requirement coverage for section %d", section))
    end
  end

  return #errors == 0, errors
end

function M.self_check()
  local ok, errors = M.validate()
  if ok then
    return true
  end
  error("requirements registry validation failed:\n- " .. table.concat(errors, "\n- "))
end

return M
