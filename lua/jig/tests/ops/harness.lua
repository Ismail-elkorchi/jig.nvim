local fabric = require("jig.tests.fabric")

local M = {}

local function repo_root()
  return fabric.repo_root(5)
end

local function snapshot_path(opts)
  return fabric.snapshot_path(opts, vim.fn.stdpath("state") .. "/jig/ops-harness-snapshot.json")
end

local function base_env(tmp, appname)
  local env = vim.fn.environ()
  env.NVIM_APPNAME = appname
  env.XDG_CONFIG_HOME = tmp .. "/config"
  env.XDG_STATE_HOME = tmp .. "/state"
  env.XDG_DATA_HOME = tmp .. "/data"
  env.XDG_CACHE_HOME = tmp .. "/cache"
  return env
end

local function app_paths(env)
  local app = env.NVIM_APPNAME
  return {
    config = env.XDG_CONFIG_HOME .. "/" .. app,
    state = env.XDG_STATE_HOME .. "/" .. app,
    data = env.XDG_DATA_HOME .. "/" .. app,
  }
end

local function run_nvim(env, commands, timeout_ms)
  local argv = {
    "nvim",
    "--headless",
    "-u",
    repo_root() .. "/init.lua",
  }
  for _, cmd in ipairs(commands or {}) do
    argv[#argv + 1] = "+" .. cmd
  end
  argv[#argv + 1] = "+qa"

  local result = vim.system(argv, { env = env, text = true }):wait(timeout_ms or 20000)
  assert(result ~= nil, "nested nvim wait returned nil")
  return result
end

local function read_json(path)
  assert(vim.fn.filereadable(path) == 1, "expected file missing: " .. path)
  local data = table.concat(vim.fn.readfile(path), "\n")
  local ok, decoded = pcall(vim.json.decode, data)
  assert(ok and type(decoded) == "table", "invalid json at " .. path)
  return decoded
end

local function run_rollback_drill(appname)
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")

  local env = base_env(tmp, appname)
  local paths = app_paths(env)
  local lockfile = paths.config .. "/lazy-lock.json"
  local rollback = paths.state .. "/jig/lazy-lock.previous.json"

  local broken = {
    lockfile_version = 1,
    plugins = {
      ["demo.nvim"] = {
        branch = "edge",
        commit = "broken",
      },
    },
  }

  local known_good = {
    lockfile_version = 1,
    plugins = {
      ["demo.nvim"] = {
        branch = "stable",
        commit = "known-good",
      },
    },
  }

  vim.fn.mkdir(vim.fn.fnamemodify(lockfile, ":h"), "p")
  vim.fn.mkdir(vim.fn.fnamemodify(rollback, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(broken) }, lockfile)
  vim.fn.writefile({ vim.json.encode(known_good) }, rollback)

  local result = run_nvim(env, { "JigPluginRollback" }, 20000)
  assert(
    result.code == 0,
    "rollback command failed: " .. tostring(result.stderr) .. tostring(result.stdout)
  )

  local restored = read_json(lockfile)
  assert(vim.deep_equal(restored, known_good), "rollback did not restore known-good lockfile")

  local lazy_dir = paths.data .. "/lazy/lazy.nvim"
  assert(
    vim.fn.isdirectory(lazy_dir) == 0,
    "rollback drill caused startup auto-install side effect"
  )

  return {
    appname = appname,
    lockfile = lockfile,
    rollback = rollback,
    lazy_dir_present = vim.fn.isdirectory(lazy_dir) == 1,
  }
end

local cases = {
  {
    id = "channel-persistence",
    run = function()
      local tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")
      local env = base_env(tmp, "jig-ops-channel")
      local paths = app_paths(env)
      local channel_path = paths.state .. "/jig/channel.json"

      local set = run_nvim(env, { "JigChannel edge" }, 20000)
      assert(
        set.code == 0,
        "failed setting channel to edge: " .. tostring(set.stderr) .. tostring(set.stdout)
      )

      local channel_payload = read_json(channel_path)
      assert(channel_payload.channel == "edge", "persisted channel must be edge")

      local verify =
        run_nvim(env, { "lua assert(vim.g.jig_channel=='edge','channel not loaded')" }, 20000)
      assert(
        verify.code == 0,
        "channel persistence check failed: " .. tostring(verify.stderr) .. tostring(verify.stdout)
      )

      return {
        channel = channel_payload.channel,
        channel_path = channel_path,
      }
    end,
  },
  {
    id = "rollback-restore-without-lazy",
    run = function()
      return run_rollback_drill("jig-ops-no-lazy")
    end,
  },
  {
    id = "staged-break-rollback-drill",
    run = function()
      return run_rollback_drill("jig-ops")
    end,
  },
}

function M.run(opts)
  local report = fabric.run_cases(cases, {
    harness = "headless-child-ops",
  })

  local path = snapshot_path(opts)
  fabric.finalize(report, {
    snapshot_path = path,
    fail_label = "ops harness",
  })
  print("ops-harness snapshot written: " .. path)
end

return M
