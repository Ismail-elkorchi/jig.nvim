local M = {}

local conflict_policies = {
  error = true,
  ["allow-override"] = true,
}

local forbidden_normal_mode = {
  ["w"] = true,
  ["e"] = true,
  ["b"] = true,
  ["0"] = true,
  ["$"] = true,
  ["/"] = true,
  ["?"] = true,
  [":"] = true,
  ["i"] = true,
  ["a"] = true,
  ["o"] = true,
  ["O"] = true,
  ["u"] = true,
  ["p"] = true,
  ["dd"] = true,
  ["yy"] = true,
}

local non_leader_allowlist = {
  ["[d"] = true,
  ["]d"] = true,
}

local function base_entries()
  return {
    {
      id = "core.quit_all",
      mode = "n",
      lhs = "<leader>qq",
      rhs = "<cmd>qa<cr>",
      desc = "Quit all",
      layer = "core",
      conflictPolicy = "error",
      discoverability = { group = "Core", order = 10 },
    },
    {
      id = "core.write",
      mode = "n",
      lhs = "<leader>w",
      rhs = "<cmd>w<cr>",
      desc = "Write",
      layer = "core",
      conflictPolicy = "error",
      discoverability = { group = "Core", order = 20 },
    },
    {
      id = "core.explorer",
      mode = "n",
      lhs = "<leader>e",
      rhs = "<cmd>Ex<cr>",
      desc = "File explorer",
      layer = "core",
      conflictPolicy = "error",
      discoverability = { group = "Core", order = 30 },
    },
    {
      id = "nav.files",
      mode = "n",
      lhs = "<leader>ff",
      rhs = "<cmd>JigFiles<cr>",
      desc = "Find files",
      layer = "navigation",
      conflictPolicy = "error",
      discoverability = { group = "Navigation", order = 10 },
    },
    {
      id = "nav.buffers",
      mode = "n",
      lhs = "<leader>fb",
      rhs = "<cmd>JigBuffers<cr>",
      desc = "Find buffers",
      layer = "navigation",
      conflictPolicy = "error",
      discoverability = { group = "Navigation", order = 20 },
    },
    {
      id = "nav.recent",
      mode = "n",
      lhs = "<leader>fr",
      rhs = "<cmd>JigRecent<cr>",
      desc = "Find recent files",
      layer = "navigation",
      conflictPolicy = "error",
      discoverability = { group = "Navigation", order = 30 },
    },
    {
      id = "nav.symbols",
      mode = "n",
      lhs = "<leader>fs",
      rhs = "<cmd>JigSymbols<cr>",
      desc = "Find symbols",
      layer = "navigation",
      conflictPolicy = "error",
      discoverability = { group = "Navigation", order = 40 },
    },
    {
      id = "nav.diagnostics",
      mode = "n",
      lhs = "<leader>fD",
      rhs = "<cmd>JigDiagnostics<cr>",
      desc = "Find diagnostics",
      layer = "navigation",
      conflictPolicy = "error",
      discoverability = { group = "Navigation", order = 50 },
    },
    {
      id = "nav.history",
      mode = "n",
      lhs = "<leader>fh",
      rhs = "<cmd>JigHistory<cr>",
      desc = "Find command history",
      layer = "navigation",
      conflictPolicy = "error",
      discoverability = { group = "Navigation", order = 60 },
    },
    {
      id = "nav.git_changes",
      mode = "n",
      lhs = "<leader>fg",
      rhs = "<cmd>JigGitChanges<cr>",
      desc = "Find git changes",
      layer = "navigation",
      conflictPolicy = "error",
      discoverability = { group = "Navigation", order = 70 },
    },
    {
      id = "diag.loclist",
      mode = "n",
      lhs = "<leader>fd",
      rhs = function()
        vim.diagnostic.setloclist({ open = true })
      end,
      desc = "Diagnostics list",
      layer = "diagnostics",
      conflictPolicy = "error",
      discoverability = { group = "Diagnostics", order = 10 },
    },
    {
      id = "diag.next",
      mode = "n",
      lhs = "]d",
      rhs = function()
        vim.diagnostic.jump({ count = 1, float = true })
      end,
      desc = "Next diagnostic",
      layer = "diagnostics",
      conflictPolicy = "error",
      discoverability = { group = "Diagnostics", order = 20 },
    },
    {
      id = "diag.prev",
      mode = "n",
      lhs = "[d",
      rhs = function()
        vim.diagnostic.jump({ count = -1, float = true })
      end,
      desc = "Previous diagnostic",
      layer = "diagnostics",
      conflictPolicy = "error",
      discoverability = { group = "Diagnostics", order = 30 },
    },
    {
      id = "term.current",
      mode = "n",
      lhs = "<leader>tt",
      rhs = "<cmd>terminal<cr>",
      desc = "Terminal current",
      layer = "terminal",
      conflictPolicy = "error",
      discoverability = { group = "Terminal", order = 10 },
    },
    {
      id = "term.horizontal",
      mode = "n",
      lhs = "<leader>th",
      rhs = "<cmd>split | terminal<cr>",
      desc = "Terminal horizontal",
      layer = "terminal",
      conflictPolicy = "error",
      discoverability = { group = "Terminal", order = 20 },
    },
    {
      id = "term.vertical",
      mode = "n",
      lhs = "<leader>tv",
      rhs = "<cmd>vsplit | terminal<cr>",
      desc = "Terminal vertical",
      layer = "terminal",
      conflictPolicy = "error",
      discoverability = { group = "Terminal", order = 30 },
    },
    {
      id = "keys.index",
      mode = "n",
      lhs = "<leader>fk",
      rhs = "<cmd>JigKeys<cr>",
      desc = "Open keymap index",
      layer = "discoverability",
      conflictPolicy = "error",
      discoverability = { group = "Discoverability", order = 10 },
    },
  }
end

local function as_modes(mode)
  if type(mode) == "table" then
    return mode
  end
  return { mode }
end

local function check_required(entry, field)
  local value = entry[field]
  if value == nil then
    return false, "missing field: " .. field
  end
  if type(value) == "string" and value == "" then
    return false, "empty field: " .. field
  end
  return true, nil
end

function M.validate(entries)
  local errors = {}
  local ids = {}
  local collisions = {}

  for index, entry in ipairs(entries or {}) do
    local prefix = string.format("entry[%d]", index)

    for _, field in ipairs({
      "id",
      "mode",
      "lhs",
      "rhs",
      "desc",
      "layer",
      "conflictPolicy",
      "discoverability",
    }) do
      local ok, reason = check_required(entry, field)
      if not ok then
        table.insert(errors, prefix .. " " .. reason)
      end
    end

    if ids[entry.id] then
      table.insert(errors, prefix .. " duplicate id: " .. entry.id)
    end
    ids[entry.id] = true

    if not conflict_policies[entry.conflictPolicy] then
      table.insert(errors, prefix .. " invalid conflictPolicy: " .. tostring(entry.conflictPolicy))
    end

    if type(entry.rhs) ~= "string" and type(entry.rhs) ~= "function" then
      table.insert(errors, prefix .. " rhs must be string or function")
    end

    if type(entry.discoverability) ~= "table" then
      table.insert(errors, prefix .. " discoverability must be a table")
    elseif type(entry.discoverability.group) ~= "string" or entry.discoverability.group == "" then
      table.insert(errors, prefix .. " discoverability.group must be non-empty string")
    end

    for _, mode in ipairs(as_modes(entry.mode)) do
      local key = mode .. "|" .. entry.lhs
      local existing = collisions[key]
      if
        existing
        and existing.conflictPolicy ~= "allow-override"
        and entry.conflictPolicy ~= "allow-override"
      then
        table.insert(errors, prefix .. " duplicate mode+lhs without allow-override: " .. key)
      else
        collisions[key] = entry
      end

      if mode == "n" and forbidden_normal_mode[entry.lhs] then
        table.insert(errors, prefix .. " forbidden canonical mapping in defaults: " .. entry.lhs)
      end

      if
        mode == "n"
        and not vim.startswith(entry.lhs, "<leader>")
        and not non_leader_allowlist[entry.lhs]
      then
        table.insert(errors, prefix .. " non-leader mapping not allowed by policy: " .. entry.lhs)
      end
    end
  end

  return #errors == 0, errors
end

function M.defaults(opts)
  opts = opts or {}
  local safe_profile = opts.safe_profile
  if safe_profile == nil then
    safe_profile = vim.g.jig_safe_profile == true
  end

  local selected = {}
  for _, entry in ipairs(base_entries()) do
    if not (safe_profile and entry.layer == "navigation") then
      table.insert(selected, vim.deepcopy(entry))
    end
  end

  return selected
end

function M.apply(entries)
  local ok, errors = M.validate(entries)
  if not ok then
    error("invalid keymap registry: " .. table.concat(errors, "; "))
  end

  local opts = { noremap = true, silent = true }

  for _, entry in ipairs(entries) do
    local map_opts = vim.tbl_extend("force", opts, { desc = entry.desc })
    vim.keymap.set(entry.mode, entry.lhs, entry.rhs, map_opts)
  end
end

function M.runtime_index(entries)
  local index = {}
  for _, entry in ipairs(entries) do
    for _, mode in ipairs(as_modes(entry.mode)) do
      local map = vim.fn.maparg(entry.lhs, mode, false, true)
      index[entry.id .. "|" .. mode] = map
    end
  end
  return index
end

return M
