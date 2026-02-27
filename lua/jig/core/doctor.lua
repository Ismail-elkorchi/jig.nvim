local brand = require("jig.core.brand")
local channel_state = require("jig.core.channel")

local M = {}

local function cmd_verbose_map(opts)
  local lhs = opts.args
  -- boundary: allow-vim-api
  -- Justification: command execution must use Neovim command API for provenance helpers.
  vim.api.nvim_cmd({
    cmd = "verbose",
    args = { "map", lhs },
  }, {})
end

local function cmd_verbose_set(opts)
  local option = opts.args
  -- boundary: allow-vim-api
  -- Justification: command execution must use Neovim command API for provenance helpers.
  vim.api.nvim_cmd({
    cmd = "verbose",
    args = { "set", option .. "?" },
  }, {})
end

local function cmd_health()
  vim.cmd("checkhealth jig")
  vim.cmd("checkhealth provider")
end

local function cmd_bisect_guide()
  vim.notify(
    "Bisect workflow: disable half modules, restart, repeat. See docs/troubleshooting.jig.nvim.md",
    vim.log.levels.INFO
  )
end

local function repo_root()
  local source = debug.getinfo(1, "S").source
  if vim.startswith(source, "@") then
    source = source:sub(2)
  end
  return vim.fn.fnamemodify(source, ":p:h:h:h:h")
end

local function resolve_git_dir(root)
  local dotgit = vim.fs.joinpath(root, ".git")
  if vim.fn.isdirectory(dotgit) == 1 then
    return vim.fs.normalize(dotgit), "git_dir"
  end

  if vim.fn.filereadable(dotgit) ~= 1 then
    return nil, "missing_dotgit"
  end

  local first_line = (vim.fn.readfile(dotgit)[1] or "")
  local target = first_line:match("^gitdir:%s*(.+)%s*$")
  if target == nil then
    return nil, "invalid_git_pointer"
  end

  if vim.fs.isabspath(target) then
    return vim.fs.normalize(target), "gitdir_pointer"
  end

  return vim.fs.normalize(vim.fs.joinpath(root, target)), "gitdir_pointer"
end

local function read_ref_from_packed_refs(git_dir, ref_name)
  local packed = vim.fs.joinpath(git_dir, "packed-refs")
  if vim.fn.filereadable(packed) ~= 1 then
    return nil
  end

  for _, line in ipairs(vim.fn.readfile(packed)) do
    if line ~= "" and not vim.startswith(line, "#") and not vim.startswith(line, "^") then
      local hash, name = line:match("^(%x+)%s+(.+)$")
      if hash ~= nil and name == ref_name then
        return hash
      end
    end
  end

  return nil
end

local function resolve_head_sha(root)
  local git_dir, git_source = resolve_git_dir(root)
  if git_dir == nil then
    return "unknown", git_source
  end

  local head_path = vim.fs.joinpath(git_dir, "HEAD")
  if vim.fn.filereadable(head_path) ~= 1 then
    return "unknown", "missing_head"
  end

  local head_line = vim.trim(vim.fn.readfile(head_path)[1] or "")
  if head_line == "" then
    return "unknown", "empty_head"
  end

  local ref_name = head_line:match("^ref:%s*(.+)$")
  if ref_name ~= nil then
    local ref_file = vim.fs.joinpath(git_dir, ref_name)
    local hash = nil
    if vim.fn.filereadable(ref_file) == 1 then
      hash = vim.trim(vim.fn.readfile(ref_file)[1] or "")
    end
    if hash == nil or hash == "" then
      hash = read_ref_from_packed_refs(git_dir, ref_name)
    end
    if hash ~= nil and hash ~= "" then
      return hash:sub(1, 12), ref_name
    end
    return "unknown", "unresolved_ref"
  end

  if head_line:match("^[0-9a-fA-F]+$") then
    return head_line:sub(1, 12), "detached_head"
  end

  return "unknown", "invalid_head"
end

local function collect_version_report()
  local root = repo_root()
  local version = vim.version()
  local uname = (vim.uv or vim.loop).os_uname()
  local commit, commit_source = resolve_head_sha(root)
  local channel = channel_state.load()

  return {
    jig = {
      brand = brand.brand,
      commit = commit,
      commit_source = commit_source,
      profile = tostring(vim.g.jig_profile or "unknown"),
      appname = tostring(vim.g.jig_appname or vim.env.NVIM_APPNAME or "nvim"),
    },
    neovim = string.format("%d.%d.%d", version.major, version.minor, version.patch),
    os = {
      sysname = tostring(uname.sysname or ""),
      release = tostring(uname.release or ""),
      machine = tostring(uname.machine or ""),
    },
    channel = {
      value = tostring(channel.channel or channel_state.default()),
      source = tostring(channel.source or "default"),
      path = tostring(channel.path or channel_state.path()),
      error = channel.error and tostring(channel.error) or nil,
    },
    stdpath = {
      config = vim.fn.stdpath("config"),
      data = vim.fn.stdpath("data"),
      state = vim.fn.stdpath("state"),
      cache = vim.fn.stdpath("cache"),
    },
  }
end

local function cmd_version()
  local report = collect_version_report()
  vim.g.jig_version_last = report

  local lines = {
    string.format("%s Version Report", report.jig.brand),
    string.rep("=", 18),
    string.format("jig.commit=%s", report.jig.commit),
    string.format("jig.commit_source=%s", report.jig.commit_source),
    string.format("jig.profile=%s", report.jig.profile),
    string.format("jig.appname=%s", report.jig.appname),
    string.format("neovim.version=%s", report.neovim),
    string.format("os=%s %s (%s)", report.os.sysname, report.os.release, report.os.machine),
    string.format(
      "channel=%s (source=%s path=%s)",
      report.channel.value,
      report.channel.source,
      report.channel.path
    ),
    string.format("stdpath.config=%s", report.stdpath.config),
    string.format("stdpath.data=%s", report.stdpath.data),
    string.format("stdpath.state=%s", report.stdpath.state),
    string.format("stdpath.cache=%s", report.stdpath.cache),
  }

  if report.channel.error ~= nil then
    lines[#lines + 1] = string.format("channel.error=%s", report.channel.error)
  end

  print(table.concat(lines, "\n"))
end

function M.setup()
  -- boundary: allow-vim-api
  -- Justification: user command registration is a Neovim host boundary operation.
  vim.api.nvim_create_user_command(brand.command("Health"), cmd_health, {
    desc = "Run Jig and provider health checks",
  })

  vim.api.nvim_create_user_command(brand.command("VerboseMap"), cmd_verbose_map, {
    nargs = 1,
    desc = "Show keymap provenance via :verbose map <lhs>",
  })

  vim.api.nvim_create_user_command(brand.command("VerboseSet"), cmd_verbose_set, {
    nargs = 1,
    desc = "Show option provenance via :verbose set <option>?",
  })

  vim.api.nvim_create_user_command(brand.command("BisectGuide"), cmd_bisect_guide, {
    desc = "Show deterministic bisect guidance",
  })

  vim.api.nvim_create_user_command(brand.command("Version"), cmd_version, {
    desc = "Print deterministic Jig/Neovim/environment support report",
  })
end

return M
