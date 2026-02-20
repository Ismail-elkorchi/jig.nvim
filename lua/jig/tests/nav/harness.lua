local backend = require("jig.nav.backend")
local fallback = require("jig.nav.fallback")
local guardrails = require("jig.nav.guardrails")
local miller = require("jig.nav.miller")
local root = require("jig.nav.root")

local M = {}

local function repo_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h:h:h:h")
end

local function fixture_root()
  return repo_root() .. "/tests/fixtures/root_policy/workspace"
end

local function write_snapshot(path, payload)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(payload) }, path)
end

local function snapshot_path(opts)
  if opts and opts.snapshot_path and opts.snapshot_path ~= "" then
    return opts.snapshot_path
  end
  return vim.fn.stdpath("state") .. "/jig/nav-harness-snapshot.json"
end

local function with_globals(fn)
  local original_nav = vim.deepcopy(vim.g.jig_nav)
  local original_env = vim.env.JIG_ROOT
  local original_override = vim.g.jig_root_override

  local ok, result = pcall(fn)

  vim.g.jig_nav = original_nav
  vim.env.JIG_ROOT = original_env
  vim.g.jig_root_override = original_override
  backend._set_picker_for_test(nil)

  if not ok then
    error(result)
  end

  return result
end

local cases = {
  {
    id = "root-determinism",
    run = function()
      return with_globals(function()
        local fixture = fixture_root()
        vim.g.jig_nav = {
          markers = { "jig.root", ".git", "package.json" },
        }

        local nested = fixture .. "/src/nested/project/main.lua"
        local expected_nested = fixture .. "/src/nested/project"

        local outputs = {}
        for _ = 1, 5 do
          local resolved = root.resolve({ path = nested })
          table.insert(outputs, resolved.root)
        end

        for _, output in ipairs(outputs) do
          assert(output == expected_nested, "marker root mismatch")
        end

        local module_file = fixture .. "/src/module/file.lua"
        local resolved_module = root.resolve({ path = module_file })
        assert(resolved_module.root == fixture, "workspace root mismatch")

        vim.env.JIG_ROOT = fixture .. "/src"
        local env_resolved = root.resolve({ path = nested })
        assert(env_resolved.root == fixture .. "/src", "env root override mismatch")

        root.set(fixture)
        vim.env.JIG_ROOT = nil
        local cmd_resolved = root.resolve({ path = nested })
        assert(cmd_resolved.root == fixture, "command root override mismatch")

        return {
          nested = expected_nested,
          workspace = resolved_module.root,
          env_override = env_resolved.root,
          command_override = cmd_resolved.root,
        }
      end)
    end,
  },
  {
    id = "fallback-backend-behavior",
    run = function()
      return with_globals(function()
        local fixture = fixture_root()
        backend._set_picker_for_test({
          files = function()
            error("forced backend failure")
          end,
        })

        local result = backend.files({ root = fixture }, {
          select = false,
          candidate_cap = 5,
          cap = 5,
          ignore_globs = {},
        })

        assert(result.backend == "fallback", "expected fallback backend")
        assert(result.count <= 5, "fallback cap exceeded")

        return {
          backend = result.backend,
          count = result.count,
          cap = result.cap,
        }
      end)
    end,
  },
  {
    id = "latency-budget-smoke",
    run = function()
      return with_globals(function()
        local tmp = vim.fn.tempname()
        vim.fn.mkdir(tmp, "p")

        for i = 1, 250 do
          local file = string.format("%s/nav_%03d.txt", tmp, i)
          vim.fn.writefile({ "latency" }, file)
        end

        local started = vim.uv.hrtime()
        local result = backend.files({ root = tmp }, {
          select = false,
          candidate_cap = 60,
          cap = 60,
          ignore_globs = {},
        })
        local elapsed_ms = math.floor((vim.uv.hrtime() - started) / 1000000)

        vim.fn.delete(tmp, "rf")

        assert(result.count <= 60, "latency test candidate cap exceeded")
        assert(elapsed_ms <= 1500, "latency budget exceeded")

        return {
          elapsed_ms = elapsed_ms,
          count = result.count,
          cap = result.cap,
        }
      end)
    end,
  },
  {
    id = "candidate-cap-guardrail",
    run = function()
      return with_globals(function()
        local tmp = vim.fn.tempname()
        vim.fn.mkdir(tmp, "p")

        for i = 1, 30 do
          local file = string.format("%s/file_%02d.txt", tmp, i)
          vim.fn.writefile({ "x" }, file)
        end

        local items = fallback.list_files(tmp, {
          cap = 7,
          candidate_cap = 7,
          ignore_globs = {},
        })

        assert(#items <= 7, "candidate cap guardrail violated")

        local synthetic = {}
        for i = 1, 100 do
          table.insert(synthetic, "item-" .. i)
        end
        local capped = guardrails.cap_items(synthetic, 9)
        assert(#capped <= 9, "cap_items guardrail violated")

        vim.fn.delete(tmp, "rf")

        return {
          temp_dir = tmp,
          fallback_count = #items,
          synthetic_count = #capped,
        }
      end)
    end,
  },
  {
    id = "miller-mode-flag",
    run = function()
      return with_globals(function()
        local fixture = fixture_root()

        vim.g.jig_nav = { enable_miller = false }
        local ok_disabled, msg = miller.open({ root = fixture })
        assert(ok_disabled == false, "miller should be disabled by default")
        assert(msg == "miller mode disabled", "unexpected disabled message")

        vim.g.jig_nav = { enable_miller = true }
        local ok_enabled, state = miller.open({
          root = fixture,
          columns = 2,
          cap = 8,
        })
        assert(ok_enabled == true, "miller should open when enabled")
        assert(type(state) == "table" and #(state.windows or {}) >= 1, "miller windows missing")
        miller.close(state)

        return {
          disabled = ok_disabled,
          enabled_windows = #(state.windows or {}),
        }
      end)
    end,
  },
}

function M.run(opts)
  local report = {
    harness = "headless-child-nav",
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
  print("nav-harness snapshot written: " .. path)

  if #failed > 0 then
    error("nav harness failed: " .. table.concat(failed, ", "))
  end
end

return M
