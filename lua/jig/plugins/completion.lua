return {
  {
    "saghen/blink.cmp",
    version = "*",
    opts = {
      fuzzy = {
        -- Stability-first default: avoid native module failures on unsupported hosts.
        implementation = "lua",
      },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
      },
      cmdline = {
        -- Baseline-safe default: keep native ':' cmdline path stable.
        enabled = false,
      },
    },
  },
}
