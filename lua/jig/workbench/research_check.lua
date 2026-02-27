local M = {}

local function read(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  return table.concat(vim.fn.readfile(path), "\n")
end

local function count_pattern(text, pattern)
  local total = 0
  for _ in tostring(text):gmatch(pattern) do
    total = total + 1
  end
  return total
end

local function contains(text, needle)
  return tostring(text):find(needle, 1, true) ~= nil
end

function M.run(opts)
  opts = opts or {}
  local root = opts.root or _G.__jig_repo_root or vim.fn.getcwd()
  local workbench_doc = root .. "/docs/workbench.jig.nvim.md"
  local alignment_doc = root .. "/docs/roadmap/NEOVIM_ROADMAP_ALIGNMENT.md"

  local workbench = read(workbench_doc)
  local alignment = read(alignment_doc)
  local errors = {}

  if workbench == nil then
    errors[#errors + 1] = "missing docs/workbench.jig.nvim.md"
  end
  if alignment == nil then
    errors[#errors + 1] = "missing docs/roadmap/NEOVIM_ROADMAP_ALIGNMENT.md"
  end

  if #errors > 0 then
    return false, {
      errors = errors,
      checks = {},
    }
  end

  local checks = {}

  checks.r1_heading = contains(workbench, "## Top 5 Daily Loops")
  checks.r1_loop_count = count_pattern(workbench, "### Loop %d:") >= 5
  checks.r1_step_flow = contains(workbench, "Step-by-step flow")

  checks.r2_layout_heading = contains(workbench, "## Loop-to-Layout Mapping")
  checks.r2_layout_rows = contains(workbench, "| Loop | Minimum components |")
    and contains(workbench, "| 1 |")
    and contains(workbench, "| 5 |")

  checks.r3_component_heading = contains(workbench, "## Component Assembly and Headless Oracles")
  checks.r3_component_rows = contains(
    workbench,
    "| Component | Jig assembly (primitives) | Headless oracle |"
  ) and contains(workbench, "Navigation pane") and contains(workbench, "Main editing pane") and contains(
    workbench,
    "Terminal pane"
  )

  checks.r4_disconfirm_heading = contains(workbench, "## Disconfirming Constraints and Mitigations")
  checks.r4_disconfirm_count = count_pattern(workbench, "%- Constraint:") >= 2

  checks.r5_alignment_heading = contains(alignment, "# NEOVIM_ROADMAP_ALIGNMENT.md")
  checks.r5_vim_pack = contains(alignment, "vim.pack")
  checks.r5_vim_async = contains(alignment, "vim.async")
  checks.r5_ui_item = contains(alignment, "UI")
    or contains(alignment, "events")
    or contains(alignment, "cmdline")
  checks.r5_policy_sections = contains(alignment, "Adopt later")
    and contains(alignment, "Abstract now")
    and contains(alignment, "Intentionally not chasing")

  checks.sources_neovim = contains(workbench, "https://neovim.io/roadmap/")
  checks.sources_helix = contains(workbench, "https://helix-editor.com/")
  checks.sources_kakoune = contains(workbench, "https://github.com/mawww/kakoune")
    or contains(workbench, "https://kakoune.org/")
  checks.sources_tmux = contains(workbench, "https://github.com/tmux/tmux/wiki")
    or contains(workbench, "https://github.com/tmux/tmux")
  checks.sources_ollama = contains(workbench, "https://docs.ollama.com/openai")
  checks.sources_claude =
    contains(workbench, "https://docs.anthropic.com/en/docs/claude-code/llm-gateway")
  checks.sources_codex = contains(workbench, "https://github.com/openai/codex")

  for name, ok in pairs(checks) do
    if ok ~= true then
      errors[#errors + 1] = "failed " .. name
    end
  end

  return #errors == 0, {
    errors = errors,
    checks = checks,
  }
end

return M
