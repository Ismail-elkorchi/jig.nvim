local M = {}

local defaults = {
  servers = {
    lua_ls = {
      enabled = true,
      binary = "lua-language-server",
      cmd = { "lua-language-server" },
      filetypes = { "lua" },
      root_markers = {
        "jig.root",
        ".luarc.json",
        ".luarc.jsonc",
        ".git",
      },
      settings = {
        Lua = {
          diagnostics = {
            globals = { "vim" },
          },
          workspace = {
            checkThirdParty = false,
          },
          telemetry = {
            enable = false,
          },
        },
      },
      remediation = "Install lua-language-server, then run :JigLspHealth",
    },
    bashls = {
      enabled = true,
      binary = "bash-language-server",
      cmd = { "bash-language-server", "start" },
      filetypes = { "bash", "sh", "zsh" },
      root_markers = {
        "jig.root",
        ".git",
      },
      remediation = "Install bash-language-server, then run :JigLspHealth",
    },
  },
  diagnostics = {
    severity_sort = true,
    update_in_insert = false,
    underline = true,
    signs = true,
    virtual_text = {
      spacing = 2,
      source = "if_many",
    },
    float = {
      source = "if_many",
      border = "rounded",
      scope = "line",
    },
  },
  inlay_hints = {
    enabled = false,
  },
  format_on_save = {
    enabled = false,
    timeout_ms = 1000,
    allow_filetypes = {},
    deny_filetypes = {},
  },
}

function M.defaults()
  return vim.deepcopy(defaults)
end

function M.get(opts)
  opts = opts or {}
  local user = opts.user
  if user == nil then
    user = vim.g.jig_lsp
  end

  if type(user) ~= "table" then
    user = {}
  end

  return vim.tbl_deep_extend("force", M.defaults(), user)
end

return M
