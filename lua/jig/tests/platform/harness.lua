local platform = require("jig.platform")
local root = require("jig.nav.root")

local M = {}

local function repo_root()
  if type(_G.__jig_repo_root) == "string" and _G.__jig_repo_root ~= "" then
    return _G.__jig_repo_root
  end
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h:h:h:h:h")
end

local function snapshot_path(opts)
  if opts and opts.snapshot_path and opts.snapshot_path ~= "" then
    return opts.snapshot_path
  end
  return vim.fn.stdpath("state") .. "/jig/platform-harness-snapshot.json"
end

local function write_snapshot(path, payload)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(payload) }, path)
end

local function normalize(path)
  return platform.path.normalize(path, { slash = true })
end

local cases = {
  {
    id = "os-and-stdpath-invariants",
    run = function()
      local detected = platform.detect()
      assert(type(detected.os.class) == "string" and detected.os.class ~= "", "os class missing")
      assert(type(detected.os.arch) == "string" and detected.os.arch ~= "", "os arch missing")
      assert(type(detected.stdpaths) == "table", "stdpaths missing")
      assert(detected.stdpaths.config ~= "", "stdpath config missing")
      assert(detected.stdpaths.data ~= "", "stdpath data missing")
      assert(detected.stdpaths.state ~= "", "stdpath state missing")
      assert(detected.stdpaths.cache ~= "", "stdpath cache missing")

      return {
        os_class = detected.os.class,
        arch = detected.os.arch,
        is_wsl = detected.os.is_wsl,
      }
    end,
  },
  {
    id = "path-join-normalize-roundtrip",
    run = function()
      local cwd = platform.fs.cwd({ slash = true })
      local joined = platform.path.join(cwd, "tests", "fixtures", "root_policy")
      local norm1 = normalize(joined)
      local norm2 = normalize(norm1)

      assert(norm1 == norm2, "normalize must be idempotent")
      assert(platform.path.is_absolute(norm1), "normalized path must be absolute")
      assert(platform.fs.is_dir(norm1), "joined fixture path must exist")

      local windows_sample = "C:\\Users\\dev\\repo\\src\\file.lua"
      local windows_slash = platform.path.to_slash(windows_sample)
      assert(
        windows_slash == "C:/Users/dev/repo/src/file.lua",
        "windows slash normalization mismatch"
      )
      assert(platform.path.basename(windows_sample) == "file.lua", "basename mismatch")

      return {
        cwd = cwd,
        joined = norm1,
        windows_sample = windows_slash,
      }
    end,
  },
  {
    id = "shell-detection-and-argv-strategy",
    run = function()
      local detected = platform.shell.detect()
      assert(type(detected.shell.kind) == "string", "shell kind missing")
      assert(type(detected.shells) == "table", "shell matrix missing")

      local one_liners = {
        bash = platform.shell.run_one_liner("bash", "printf ok"),
        fish = platform.shell.run_one_liner("fish", "printf ok"),
        pwsh = platform.shell.run_one_liner("pwsh", "Write-Output ok"),
        cmd = platform.shell.run_one_liner("cmd", "echo ok"),
      }

      for name, argv in pairs(one_liners) do
        assert(type(argv) == "table" and #argv >= 2, "argv strategy invalid for " .. name)
      end

      return {
        configured_kind = detected.shell.kind,
        shell_exists = detected.shell.exists,
      }
    end,
  },
  {
    id = "clipboard-non-fatal",
    run = function()
      local clipboard = platform.clipboard.detect()
      assert(type(clipboard.available) == "boolean", "clipboard flag invalid")
      assert(type(clipboard.hint) == "string", "clipboard hint invalid")
      return {
        available = clipboard.available,
        hint = clipboard.hint,
      }
    end,
  },
  {
    id = "root-detection-normalized-input",
    run = function()
      local fixture = repo_root()
        .. "/tests/fixtures/root_policy/workspace/src/nested/project/main.lua"
      local normalized = platform.path.normalize(fixture)

      local first = root.resolve({ path = fixture })
      local second = root.resolve({ path = normalized })

      assert(type(first.root) == "string" and first.root ~= "", "first root missing")
      assert(type(second.root) == "string" and second.root ~= "", "second root missing")
      assert(
        normalize(first.root) == normalize(second.root),
        "root mismatch across normalized inputs"
      )

      return {
        first_source = first.source,
        second_source = second.source,
        root = normalize(first.root),
      }
    end,
  },
}

function M.run(opts)
  local report = {
    harness = "headless-child-platform",
    generated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    cases = {},
  }

  local failed = {}
  for _, case in ipairs(cases) do
    local ok, details = pcall(case.run)
    report.cases[case.id] = {
      ok = ok,
      details = ok and details or { error = details },
    }

    if not ok then
      failed[#failed + 1] = case.id
    end
  end

  report.summary = {
    passed = #failed == 0,
    failed_cases = failed,
  }

  local path = snapshot_path(opts)
  write_snapshot(path, report)
  print("platform-harness snapshot written: " .. path)

  if #failed > 0 then
    error("platform harness failed: " .. table.concat(failed, ", "))
  end
end

return M
