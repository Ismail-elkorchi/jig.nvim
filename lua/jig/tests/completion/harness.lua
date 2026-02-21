local fabric = require("jig.tests.fabric")

local M = {}

local function snapshot_path(opts)
  return fabric.snapshot_path(
    opts,
    vim.fn.stdpath("state") .. "/jig/completion-harness-snapshot.json"
  )
end

local function completion_spec()
  local specs = require("jig.plugins.completion")
  assert(type(specs) == "table" and #specs >= 1, "completion plugin spec missing")
  local first = specs[1]
  assert(type(first.opts) == "table", "completion opts missing")
  return first.opts
end

local cases = {
  {
    id = "completion-policy-defaults",
    run = function()
      local opts = completion_spec()
      assert(opts.fuzzy and opts.fuzzy.implementation == "lua", "lua fuzzy fallback required")
      assert(
        opts.cmdline and opts.cmdline.enabled == false,
        "cmdline completion must stay disabled"
      )
      return {
        fuzzy = opts.fuzzy.implementation,
        cmdline_enabled = opts.cmdline.enabled,
      }
    end,
  },
  {
    id = "completion-fallback-smoke",
    run = function()
      local candidates = {
        "alpha",
        "alpine",
        "application",
        "beta",
        "gamma",
      }
      local started = vim.uv.hrtime()
      local matched = vim.fn.matchfuzzy(candidates, "alp")
      local elapsed_ms = math.floor((vim.uv.hrtime() - started) / 1000000)

      assert(
        type(matched) == "table" and #matched >= 1,
        "fallback fuzzy completion returned no candidates"
      )
      assert(elapsed_ms <= 300, "fallback completion latency budget exceeded")

      local ok_blink = pcall(require, "blink.cmp")
      return {
        elapsed_ms = elapsed_ms,
        matched = #matched,
        blink_loaded = ok_blink,
      }
    end,
  },
}

function M.run(opts)
  local report = fabric.run_cases(cases, {
    harness = "headless-child-completion",
  })

  local path = snapshot_path(opts)
  fabric.finalize(report, {
    snapshot_path = path,
    fail_label = "completion harness",
  })
  print("completion-harness snapshot written: " .. path)
end

return M
