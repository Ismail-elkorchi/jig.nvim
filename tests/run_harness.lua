local function repo_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h")
end

local ROOT = repo_root()
_G.__jig_repo_root = ROOT

package.path = string.format("%s/lua/?.lua;%s/lua/?/init.lua;", ROOT, ROOT) .. package.path
vim.opt.rtp:prepend(ROOT)

local function join(...)
  local parts = { ... }
  local out = table.concat(parts, "/")
  out = out:gsub("/+", "/")
  if ROOT:find("\\", 1, true) then
    out = out:gsub("/", "\\")
  end
  return out
end

local function write_json(path, payload)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(payload) }, path)
end

local function parse_args(argv)
  local suites = {}
  local all = false

  local index = 1
  while index <= #argv do
    local token = argv[index]
    if token == "--" then
      index = index + 1
    elseif token == "--all" then
      all = true
      index = index + 1
    elseif token == "--suite" then
      local value = argv[index + 1]
      if value == nil or value == "" then
        error("--suite requires a value")
      end
      suites[#suites + 1] = value
      index = index + 2
    else
      suites[#suites + 1] = token
      index = index + 1
    end
  end

  return {
    all = all,
    suites = suites,
  }
end

local function run_startup_smoke()
  assert(vim.g.jig_profile == "default", "default profile expected")
  assert(vim.fn.exists(":JigHealth") == 2, "JigHealth missing")
  assert(vim.fn.exists(":JigKeys") == 2, "JigKeys missing")
  assert(vim.fn.exists(":JigFiles") == 2, "JigFiles missing")
  assert(vim.fn.exists(":JigExec") == 2, "JigExec missing")
  assert(vim.fn.exists(":JigToolchainInstall") == 2, "JigToolchainInstall missing")
  assert(vim.fn.exists(":JigToolchainUpdate") == 2, "JigToolchainUpdate missing")
  assert(vim.fn.exists(":JigToolchainRestore") == 2, "JigToolchainRestore missing")
  assert(vim.fn.exists(":JigToolchainRollback") == 2, "JigToolchainRollback missing")
  assert(vim.fn.exists(":JigMcpTrust") == 0, "JigMcpTrust should be absent by default")
  assert(vim.fn.exists(":JigMcpList") == 0, "JigMcpList should be absent by default")
  assert(vim.fn.exists(":JigAgentContext") == 0, "JigAgentContext should be absent by default")
  assert(vim.fn.exists(":JigAgentApprovals") == 0, "JigAgentApprovals should be absent by default")
  assert(vim.fn.exists(":JigPatchReview") == 0, "JigPatchReview should be absent by default")
  assert(package.loaded["jig.agent"] == nil, "agent module should not autoload")

  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  local env = vim.fn.environ()
  env.XDG_CONFIG_HOME = join(tmp, "config")
  env.XDG_DATA_HOME = join(tmp, "data")
  env.XDG_STATE_HOME = join(tmp, "state")
  env.XDG_CACHE_HOME = join(tmp, "cache")
  env.NVIM_APPNAME = "jig-ci"
  local result = vim
    .system({ "nvim", "--headless", "-u", join(ROOT, "init.lua"), "+qa" }, {
      env = env,
      text = true,
    })
    :wait(10000)
  assert(result ~= nil and result.code == 0, "startup subprocess failed")
  assert(
    vim.fn.isdirectory(tmp .. "/data/jig-ci/lazy/lazy.nvim") == 0,
    "startup auto-install side effect"
  )
  assert(
    vim.fn.filereadable(tmp .. "/config/jig-ci/jig-toolchain-manifest.json") == 0,
    "startup auto-created toolchain manifest"
  )
  assert(
    vim.fn.filereadable(tmp .. "/config/jig-ci/jig-toolchain-lock.json") == 0,
    "startup auto-created toolchain lockfile"
  )
  vim.fn.delete(tmp, "rf")

  return {
    profile = vim.g.jig_profile,
    startup_side_effect = "none",
  }
end

local function run_cmdline_check()
  local ok, details = require("jig.ui.cmdline").open_close_check()
  assert(ok == true, "cmdline open/close check failed")
  return details
end

local SUITES = {
  startup = {
    run = run_startup_smoke,
  },
  cmdline = {
    run = run_cmdline_check,
  },
  ui = {
    module = "jig.tests.ui.harness",
    snapshot = join(ROOT, "tests/ui/snapshots/latest-headless.json"),
  },
  keymaps = {
    module = "jig.tests.keymaps.harness",
    snapshot = join(ROOT, "tests/keymaps/snapshots/latest-headless.json"),
  },
  docs = {
    module = "jig.tests.docs.harness",
    snapshot = join(ROOT, "tests/docs/snapshots/latest-headless.json"),
  },
  completion = {
    module = "jig.tests.completion.harness",
    snapshot = join(ROOT, "tests/completion/snapshots/latest-headless.json"),
  },
  nav = {
    module = "jig.tests.nav.harness",
    snapshot = join(ROOT, "tests/nav/snapshots/latest-headless.json"),
  },
  tools = {
    module = "jig.tests.tools.harness",
    snapshot = join(ROOT, "tests/tools/snapshots/latest-headless.json"),
  },
  lsp = {
    module = "jig.tests.lsp.harness",
    snapshot = join(ROOT, "tests/lsp/snapshots/latest-headless.json"),
  },
  agent = {
    module = "jig.tests.agent.harness",
    snapshot = join(ROOT, "tests/agent/snapshots/latest-headless.json"),
  },
  agent_ui = {
    module = "jig.tests.agent_ui.harness",
    snapshot = join(ROOT, "tests/agent_ui/snapshots/latest-headless.json"),
  },
  security = {
    module = "jig.tests.security.harness",
    snapshot = join(ROOT, "tests/security/snapshots/latest-headless.json"),
  },
  ops = {
    module = "jig.tests.ops.harness",
    snapshot = join(ROOT, "tests/ops/snapshots/latest-headless.json"),
  },
  perf = {
    module = "jig.tests.perf.harness",
    snapshot = join(ROOT, "tests/perf/snapshots/latest-headless.json"),
  },
  scorecard = {
    module = "jig.tests.scorecard.harness",
    snapshot = join(ROOT, "tests/scorecard/snapshots/latest-headless.json"),
  },
  pending = {
    module = "jig.tests.pending.harness",
    snapshot = join(ROOT, "tests/pending/snapshots/latest-headless.json"),
  },
  platform = {
    module = "jig.tests.platform.harness",
    snapshot = join(ROOT, "tests/platform/snapshots/latest-headless.json"),
  },
}

local DEFAULT_SUITES = {
  "startup",
  "cmdline",
  "ui",
  "keymaps",
  "docs",
  "completion",
  "nav",
  "tools",
  "security",
  "ops",
  "platform",
}

local function resolve_suites(parsed)
  if parsed.all == true or #parsed.suites == 0 then
    return vim.deepcopy(DEFAULT_SUITES)
  end

  local selected = {}
  for _, name in ipairs(parsed.suites) do
    if SUITES[name] == nil then
      error("unknown suite: " .. tostring(name))
    end
    selected[#selected + 1] = name
  end
  return selected
end

local function run_suite(name)
  local suite = SUITES[name]
  if suite.run ~= nil then
    local details = suite.run()
    return {
      ok = true,
      details = details,
    }
  end

  local module = require(suite.module)
  module.run({ snapshot_path = suite.snapshot })
  return {
    ok = true,
    details = {
      module = suite.module,
      snapshot = suite.snapshot,
    },
  }
end

local function main()
  require("jig")

  local parsed = parse_args(arg or {})
  local suites = resolve_suites(parsed)

  local report = {
    harness = "jig-cross-platform-runner",
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    suites = {},
  }

  local failed = {}
  for _, name in ipairs(suites) do
    local ok, outcome = pcall(run_suite, name)
    report.suites[name] = {
      ok = ok,
      details = ok and outcome.details or { error = outcome },
    }
    if not ok then
      failed[#failed + 1] = name
      vim.api.nvim_err_writeln(
        string.format("suite failed: %s -> %s", tostring(name), tostring(outcome))
      )
    end
  end

  report.summary = {
    passed = #failed == 0,
    failed_suites = failed,
  }

  local snapshot = join(ROOT, "tests/snapshots/latest-headless.json")
  write_json(snapshot, report)
  print("cross-platform harness snapshot written: " .. snapshot)

  if #failed > 0 then
    error("cross-platform harness failed: " .. table.concat(failed, ", "))
  end
end

local ok, err = pcall(main)
if not ok then
  vim.api.nvim_err_writeln(tostring(err))
  vim.cmd("cquit 1")
end

vim.cmd("qa")
