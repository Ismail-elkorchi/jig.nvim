local lifecycle = require("jig.lsp.lifecycle")
local registry = require("jig.lsp.registry")

local M = {}

local function repo_root()
  if type(_G.__jig_repo_root) == "string" and _G.__jig_repo_root ~= "" then
    return _G.__jig_repo_root
  end
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h:h:h:h")
end

local function snapshot_path(opts)
  if opts and opts.snapshot_path and opts.snapshot_path ~= "" then
    return opts.snapshot_path
  end
  return vim.fn.stdpath("state") .. "/jig/lsp-harness-snapshot.json"
end

local function write_snapshot(path, payload)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(payload) }, path)
end

local function command_exists(name)
  return vim.fn.exists(":" .. name) == 2
end

local function safe_env()
  local env = vim.fn.environ()
  env.NVIM_APPNAME = "jig-safe"
  return env
end

local function run_safe_assertions()
  local root = repo_root()
  local result = vim
    .system({
      "nvim",
      "--headless",
      "-u",
      root .. "/init.lua",
      "+lua assert(vim.fn.exists(':JigLspHealth')==0)",
      "+lua assert(vim.fn.exists(':JigLspInfo')==0)",
      "+lua assert(vim.fn.exists(':JigLspSnapshot')==0)",
      "+lua assert(package.loaded['jig.lsp']==nil)",
      "+qa",
    }, {
      env = safe_env(),
      text = true,
    })
    :wait(10000)

  assert(result.code == 0, (result.stderr or "") .. (result.stdout or ""))

  return {
    code = result.code,
  }
end

local cases = {
  {
    id = "default-command-surface",
    run = function()
      assert(command_exists("JigLspHealth"), "JigLspHealth missing")
      assert(command_exists("JigLspInfo"), "JigLspInfo missing")
      assert(command_exists("JigLspSnapshot"), "JigLspSnapshot missing")
      return {
        JigLspHealth = true,
        JigLspInfo = true,
        JigLspSnapshot = true,
      }
    end,
  },
  {
    id = "registry-validation",
    run = function()
      local cfg = require("jig.lsp.config").get()
      local ok, errors = registry.validate(cfg.servers)
      assert(ok, table.concat(errors or {}, "; "))
      return {
        servers = vim.tbl_count(cfg.servers),
      }
    end,
  },
  {
    id = "failure-isolation",
    run = function()
      lifecycle.reset_for_test()

      local result = lifecycle.setup({
        notify = false,
        servers = {
          jig_missing = {
            enabled = true,
            binary = "__jig_missing_binary__",
            cmd = { "__jig_missing_binary__" },
            config = {},
          },
          jig_bad_config = {
            enabled = true,
            binary = "git",
            config = function()
              error("forced setup failure")
            end,
          },
          jig_disabled = {
            enabled = false,
            binary = "git",
            config = {},
          },
        },
      })

      assert(result.servers.jig_missing.status == "missing_binary", "missing binary not isolated")
      assert(result.servers.jig_bad_config.status == "config_error", "config error not isolated")
      assert(result.servers.jig_disabled.status == "disabled", "disabled state mismatch")

      return {
        jig_missing = result.servers.jig_missing,
        jig_bad_config = result.servers.jig_bad_config,
        jig_disabled = result.servers.jig_disabled,
      }
    end,
  },
  {
    id = "snapshot-export",
    run = function()
      local temp = vim.fn.tempname() .. ".json"
      local context = require("jig.lsp").context_snapshot()
      assert(type(context) == "table", "context snapshot must be a table")
      assert(type(context.servers) == "table", "context snapshot servers missing")
      assert(type(context.diagnostics) == "table", "context snapshot diagnostics missing")

      vim.cmd("JigLspSnapshot " .. vim.fn.fnameescape(temp))
      assert(vim.fn.filereadable(temp) == 1, "snapshot file missing")

      local payload = table.concat(vim.fn.readfile(temp), "\n")
      local decoded = vim.json.decode(payload)
      assert(type(decoded) == "table" and type(decoded.servers) == "table", "snapshot JSON invalid")

      vim.fn.delete(temp)

      return {
        diagnostics_total = decoded.diagnostics.total,
      }
    end,
  },
  {
    id = "safe-profile-isolation",
    run = function()
      return run_safe_assertions()
    end,
  },
}

function M.run(opts)
  local report = {
    harness = "headless-child-lsp",
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
  print("lsp-harness snapshot written: " .. path)

  if #failed > 0 then
    error("lsp harness failed: " .. table.concat(failed, ", "))
  end
end

return M
