local M = {
  brand = "Jig",
  repo_slug = "jig.nvim",
  appname = "jig",
  safe_appname = "jig-safe",
  namespace = "jig",
  help_tag_prefix = "jig",
}

function M.command(name)
  return M.brand .. name
end

function M.augroup(name)
  return M.brand .. name
end

function M.highlight(name)
  return M.brand .. name
end

return M
