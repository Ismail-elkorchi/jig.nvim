local M = {}

M.defaults = {
  enabled = false,
  projects = {},
  policy = {
    default_decisions = {
      read = "allow",
      write = "ask",
      net = "ask",
      git = "ask",
      shell = "ask",
      unknown = "ask",
    },
    destructive_classes = {
      write = true,
      net = true,
      git = true,
      shell = true,
    },
    persistence_file = "policy.json",
  },
  logging = {
    evidence_file = "events.jsonl",
  },
  tasks = {
    metadata_file = "tasks.json",
    default_timeout_ms = 5000,
  },
  instructions = {
    precedence = { "project", "user", "global" },
    project_files = {
      "AGENTS.md",
      "CLAUDE.md",
      "GEMINI.md",
    },
    user_paths = {},
    global_paths = {},
  },
  observability = {
    budget_bytes = 120000,
    warning_ratio = 0.8,
  },
  mcp = {
    timeout_ms = 5000,
    config_files = {
      ".mcp.json",
      "mcp.json",
    },
    config_precedence = {
      ".mcp.json",
      "mcp.json",
    },
  },
  acp = {
    enabled = false,
    timeout_ms = 4000,
  },
}

local function normalize_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  local expanded = vim.fn.fnamemodify(path, ":p")
  local real = vim.uv.fs_realpath(expanded)
  local normalized = real or expanded
  normalized = normalized:gsub("\\", "/")
  return normalized:gsub("/+$", "")
end

local function current_root(opts)
  if opts and type(opts.root) == "string" and opts.root ~= "" then
    return normalize_path(opts.root)
  end

  local ok_root, root = pcall(require, "jig.nav.root")
  if ok_root and type(root.resolve) == "function" then
    local resolved = root.resolve({})
    if type(resolved) == "table" and type(resolved.root) == "string" then
      return normalize_path(resolved.root)
    end
  end

  return normalize_path(vim.uv.cwd())
end

local function merged_user(opts)
  if opts and type(opts.user) == "table" then
    return opts.user
  end

  if type(vim.g.jig_agent) == "table" then
    return vim.g.jig_agent
  end

  return {}
end

function M.get(opts)
  local cfg = vim.deepcopy(M.defaults)
  local user = merged_user(opts)
  cfg = vim.tbl_deep_extend("force", cfg, user)

  local root = current_root(opts)
  local projects = cfg.projects
  if type(projects) == "table" and root ~= nil then
    local project_cfg = projects[root]
    if type(project_cfg) == "table" then
      cfg = vim.tbl_deep_extend("force", cfg, project_cfg)
    end
  end

  cfg.root = root
  cfg.projects = nil
  return cfg
end

function M.is_enabled(opts)
  local cfg = M.get(opts)
  return cfg.enabled == true
end

function M.state_dir()
  return vim.fn.stdpath("state") .. "/jig/agent"
end

function M.normalize_path(path)
  return normalize_path(path)
end

return M
