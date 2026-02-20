local docs = require("jig.core.keymap_docs")
local panel = require("jig.core.keymap_panel")
local registry = require("jig.core.keymap_registry")

local M = {}

local function snapshot_path(opts)
  if opts and opts.snapshot_path and opts.snapshot_path ~= "" then
    return opts.snapshot_path
  end
  return vim.fn.stdpath("state") .. "/jig/keymap-harness-snapshot.json"
end

local function write_snapshot(path, payload)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(payload) }, path)
end

local function has_error(errors, fragment)
  for _, item in ipairs(errors or {}) do
    if string.find(item, fragment, 1, true) then
      return true
    end
  end
  return false
end

local cases = {
  {
    id = "schema-validation",
    run = function()
      local ok, errors = registry.validate(registry.defaults())
      assert(ok, table.concat(errors, "; "))
      return {
        entries = #registry.defaults(),
      }
    end,
  },
  {
    id = "conflict-detector",
    run = function()
      local fixture = {
        {
          id = "t.one",
          mode = "n",
          lhs = "<leader>zz",
          rhs = "<cmd>echo 1<cr>",
          desc = "one",
          layer = "test",
          conflictPolicy = "error",
          discoverability = { group = "Test" },
        },
        {
          id = "t.two",
          mode = "n",
          lhs = "<leader>zz",
          rhs = "<cmd>echo 2<cr>",
          desc = "two",
          layer = "test",
          conflictPolicy = "error",
          discoverability = { group = "Test" },
        },
      }

      local ok, errors = registry.validate(fixture)
      assert(ok == false, "duplicate mode+lhs should fail")
      assert(has_error(errors, "duplicate mode+lhs"), "duplicate error missing")
      return { errors = errors }
    end,
  },
  {
    id = "forbidden-defaults",
    run = function()
      local fixture = {
        {
          id = "t.forbidden",
          mode = "n",
          lhs = "w",
          rhs = "<cmd>echo bad<cr>",
          desc = "forbidden",
          layer = "test",
          conflictPolicy = "error",
          discoverability = { group = "Test" },
        },
      }

      local ok, errors = registry.validate(fixture)
      assert(ok == false, "forbidden canonical mapping should fail")
      assert(has_error(errors, "forbidden canonical mapping"), "forbidden mapping error missing")
      return { errors = errors }
    end,
  },
  {
    id = "runtime-forbidden-not-mapped",
    run = function()
      local forbidden = {
        "w",
        "e",
        "b",
        "0",
        "$",
        "/",
        "?",
        ":",
        "i",
        "a",
        "o",
        "O",
        "u",
        "p",
        "dd",
        "yy",
      }

      for _, lhs in ipairs(forbidden) do
        assert(vim.fn.maparg(lhs, "n") == "", "forbidden default was mapped: " .. lhs)
      end

      return { checked = forbidden }
    end,
  },
  {
    id = "runtime-registry-subset",
    run = function()
      local entries = registry.defaults()
      local index = registry.runtime_index(entries)

      local required = {
        "core.quit_all|n",
        "core.write|n",
        "nav.files|n",
        "keys.index|n",
      }

      for _, key in ipairs(required) do
        local map = index[key]
        assert(type(map) == "table" and map.lhs and map.lhs ~= "", "missing runtime map: " .. key)
      end

      return {
        checked = required,
      }
    end,
  },
  {
    id = "safe-profile-registry",
    run = function()
      local entries = registry.defaults({ safe_profile = true })
      for _, entry in ipairs(entries) do
        assert(entry.layer ~= "navigation", "safe profile must exclude navigation layer mappings")
      end
      return {
        entries = #entries,
      }
    end,
  },
  {
    id = "jigkeys-open-close",
    run = function()
      local state = panel.open(registry.defaults(), { width = 64 })
      assert(type(state) == "table" and vim.api.nvim_win_is_valid(state.win), "panel did not open")
      panel.close(state)
      assert(not vim.api.nvim_win_is_valid(state.win), "panel did not close")
      return {
        lines = #state.lines,
      }
    end,
  },
  {
    id = "docs-sync-gate",
    run = function()
      assert(docs.generate({ check = true }), "keymap docs are out of sync")
      return {
        markdown = "docs/keymaps.jig.nvim.md",
        vimdoc = "doc/jig-keymaps.txt",
      }
    end,
  },
}

function M.run(opts)
  local report = {
    harness = "headless-child-keymaps",
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    cases = {},
  }

  local failed = {}
  for _, case in ipairs(cases) do
    local ok, details = pcall(case.run)
    report.cases[case.id] = {
      ok = ok,
      details = ok and details or { error = details },
    }

    if not ok then
      table.insert(failed, case.id)
    end
  end

  report.summary = {
    passed = #failed == 0,
    failed_cases = failed,
  }

  local path = snapshot_path(opts)
  write_snapshot(path, report)
  print("keymap-harness snapshot written: " .. path)

  if #failed > 0 then
    error("keymap harness failed: " .. table.concat(failed, ", "))
  end
end

return M
