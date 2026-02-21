local backend = require("jig.nav.backend")
local fallback = require("jig.nav.fallback")
local guardrails = require("jig.nav.guardrails")
local miller = require("jig.nav.miller")
local root = require("jig.nav.root")
local platform_path = require("jig.platform.path")
local nav_fixture = require("jig.tests.fixtures.nav_repo")

local M = {}

local function repo_root()
  if type(_G.__jig_repo_root) == "string" and _G.__jig_repo_root ~= "" then
    return _G.__jig_repo_root
  end
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h:h:h:h")
end

local function fixture_root()
  return repo_root() .. "/tests/fixtures/root_policy/workspace"
end

local function normalize(value)
  return platform_path.normalize(value, { slash = true })
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
        local expected_env_suffix = "/src"

        local outputs = {}
        for _ = 1, 5 do
          local resolved = root.resolve({ path = nested })
          table.insert(outputs, {
            root = normalize(resolved.root),
            source = resolved.source,
          })
        end

        for _, output in ipairs(outputs) do
          assert(output.root == outputs[1].root, "marker root is not deterministic")
          assert(output.source == outputs[1].source, "marker source is not deterministic")
        end
        assert(outputs[1].source == "markers", "marker source mismatch")
        assert(outputs[1].root ~= nil and outputs[1].root ~= "", "marker root is empty")

        local module_file = fixture .. "/src/module/file.lua"
        local module_once = root.resolve({ path = module_file })
        local module_twice = root.resolve({ path = module_file })
        assert(
          normalize(module_once.root) == normalize(module_twice.root),
          "workspace root is not deterministic"
        )
        assert(module_once.source == module_twice.source, "workspace source is not deterministic")

        vim.env.JIG_ROOT = fixture .. "/src"
        local env_resolved = root.resolve({ path = nested })
        assert(env_resolved.source == "env", "env override source mismatch")
        assert(
          vim.endswith(normalize(env_resolved.root), expected_env_suffix),
          "env root suffix mismatch"
        )

        local set_ok, set_value = root.set(fixture)
        assert(set_ok == true, tostring(set_value))
        vim.env.JIG_ROOT = nil
        local cmd_resolved = root.resolve({ path = nested })
        assert(cmd_resolved.source == "command", "command override source mismatch")
        assert(
          normalize(cmd_resolved.root) == normalize(vim.g.jig_root_override),
          "command root mismatch"
        )

        return {
          nested = outputs[1].root,
          workspace = normalize(module_once.root),
          env_override = normalize(env_resolved.root),
          command_override = normalize(cmd_resolved.root),
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
    id = "large-fixture-tier-guardrail",
    run = function()
      return with_globals(function()
        local generated = nav_fixture.generate({
          tier = "large",
          base_dir = repo_root() .. "/tests/fixtures/generated/nav_harness",
        })

        local result = backend.files({ root = generated.root }, {
          select = false,
          candidate_cap = 75,
          cap = 75,
          ignore_globs = { "build/**", "node_modules/**" },
        })

        assert(type(result) == "table", "large fixture backend result missing")
        assert(result.count > 0, "large fixture produced no candidates")
        assert(result.count <= 75, "large fixture candidate cap exceeded")

        return {
          tier = generated.tier,
          files = generated.files,
          reused = generated.reused,
          count = result.count,
          cap = result.cap,
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
