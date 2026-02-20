local cfg = require("jig.nav.config")

local M = {}

local function system(args, opts)
  local result = vim.system(args, opts or { text = true }):wait(3000)
  if result.code ~= 0 then
    return nil, result.stderr or ""
  end
  return result.stdout or "", nil
end

local function count_nul_bytes(chunk)
  local count = 0
  for i = 1, #chunk do
    if chunk:byte(i) == 0 then
      count = count + 1
    end
  end
  return count
end

function M.is_git_repo(root)
  local _, err = system({ "git", "-C", root, "rev-parse", "--is-inside-work-tree" })
  return err == nil
end

function M.git_file_count(root)
  local output, err = system({ "git", "-C", root, "ls-files", "-z" }, { text = false })
  if err then
    return nil
  end
  return count_nul_bytes(output)
end

function M.effective_cap(root, opts)
  local config = opts or cfg.get()
  local cap = config.candidate_cap
  local info = {
    cap = cap,
    large_repo = false,
    file_count = nil,
  }

  if not M.is_git_repo(root) then
    return info
  end

  local count = M.git_file_count(root)
  info.file_count = count

  if count and count > config.large_repo_threshold then
    info.large_repo = true
    info.cap = math.min(config.large_repo_cap, cap)
  end

  return info
end

function M.cap_items(items, cap)
  local out = {}
  local max_items = math.max(1, cap)
  local limit = math.min(#items, max_items)
  for i = 1, limit do
    out[i] = items[i]
  end
  return out, #items > limit
end

function M.rg_glob_args(opts)
  local config = opts or cfg.get()
  local args = {}
  for _, glob in ipairs(config.ignore_globs or {}) do
    table.insert(args, "--glob")
    table.insert(args, glob)
  end
  return args
end

return M
