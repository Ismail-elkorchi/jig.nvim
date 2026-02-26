local M = {}

M.defaults = {
  startup = {
    trace_env = "JIG_TRACE_STARTUP_NET",
    strict_env = "JIG_STRICT_STARTUP_NET",
    fixture_env = "JIG_TEST_STARTUP_NET_ATTEMPT",
    trace_file = "startup-net-trace.jsonl",
    deny_network_by_default = true,
    startup_allowlist = {},
    network_commands = {
      "curl",
      "wget",
      "http",
      "https",
      "httpie",
      "nc",
      "ncat",
      "telnet",
      "ssh",
      "scp",
      "sftp",
      "ftp",
    },
    git_network_subcommands = {
      clone = true,
      fetch = true,
      pull = true,
      push = true,
      ls_remote = true,
      ["ls-remote"] = true,
      submodule = true,
      remote = true,
    },
    package_manager_commands = {
      npm = { install = true, update = true, add = true },
      yarn = { add = true, upgrade = true, install = true },
      pnpm = { add = true, install = true, update = true },
      pip = { install = true },
      pip3 = { install = true },
      gem = { install = true, update = true },
      cargo = { install = true },
      go = { get = true, install = true },
      apt = { install = true, upgrade = true, update = true },
      ["apt-get"] = { install = true, upgrade = true, update = true },
      brew = { install = true, upgrade = true, update = true },
      pacman = { s = true, syu = true },
      winget = { install = true, upgrade = true },
      choco = { install = true, upgrade = true },
    },
  },
  exec_safety = {
    mode = "deny",
    destructive_commands = {
      rm = true,
      rmdir = true,
      del = true,
      erase = true,
      format = true,
      mkfs = true,
      dd = true,
    },
    destructive_git = {
      reset_hard = true,
      clean_force = true,
      clean_force_dirs = true,
      push_force = true,
      branch_delete_force = true,
    },
    shell_patterns = {
      "rm%s+%-rf",
      "git%s+reset%s+%-%-hard",
      "git%s+clean%s+%-fd",
      "git%s+push%s+%-%-force",
      "dd%s+if=",
      "mkfs",
      "format%s+",
      "del%s+/",
      "rd%s+/s",
    },
  },
  mcp_trust = {
    state_file = "mcp_trust.json",
    default_source_state = {
      ["project-config"] = "ask",
      ["user-config"] = "ask",
      ["builtin"] = "allow",
      ["unknown"] = "ask",
    },
    high_risk_actions = {
      write = true,
      net = true,
      shell = true,
      git = true,
      unknown = true,
    },
  },
  gate = {
    enabled = true,
    outside_root_confirmation = "JIG-ALLOW-OUTSIDE-ROOT",
    prompt_injection_patterns = {
      "ignore previous instructions",
      "ignore all previous instructions",
      "system prompt",
      "developer prompt",
      "call tool",
      "execute command",
      "run shell",
      "curl ",
      "wget ",
      "exfiltrate",
      "send secrets",
    },
  },
}

local function deep_merge(dst, src)
  return vim.tbl_deep_extend("force", dst, src or {})
end

function M.get()
  local cfg = vim.deepcopy(M.defaults)
  if type(vim.g.jig_security) == "table" then
    cfg = deep_merge(cfg, vim.g.jig_security)
  end
  return cfg
end

function M.state_dir()
  return vim.fn.stdpath("state") .. "/jig/security"
end

function M.path(name)
  local dir = M.state_dir()
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. name
end

return M
