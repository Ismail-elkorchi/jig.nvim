local platform = require("jig.platform")
local registry = require("jig.tools.registry")
local system = require("jig.tools.system")

local M = {}

local MANIFEST_SCHEMA = "jig-toolchain-manifest-v1"
local LOCK_SCHEMA = "jig-toolchain-lock-v1"

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function stdpaths()
  return {
    config = vim.fn.stdpath("config"),
    data = vim.fn.stdpath("data"),
    state = vim.fn.stdpath("state"),
  }
end

local function defaults(opts)
  local user = vim.g.jig_toolchain
  if type(user) ~= "table" then
    user = {}
  end

  local paths = stdpaths()
  opts = opts or {}

  local install_root = opts.install_root
    or user.install_root
    or (paths.data .. "/jig/toolchain/bin")
  local artifact_root = opts.artifact_root
    or user.artifact_root
    or (paths.state .. "/jig/toolchain/artifacts")

  return {
    timeout_ms = tonumber(opts.timeout_ms or user.timeout_ms) or 4000,
    install_root = install_root,
    artifact_root = artifact_root,
    manifest_path = opts.manifest_path
      or user.manifest_path
      or (paths.config .. "/jig-toolchain-manifest.json"),
    lockfile_path = opts.lockfile_path
      or user.lockfile_path
      or (paths.config .. "/jig-toolchain-lock.json"),
    rollback_path = opts.rollback_path
      or user.rollback_path
      or (paths.state .. "/jig/toolchain-lock.previous.json"),
    actor = opts.actor or "user",
    origin = opts.origin or "jig.toolchain",
  }
end

local function file_exists(path)
  return type(path) == "string" and path ~= "" and vim.uv.fs_stat(path) ~= nil
end

local function mkdir_parent(path)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
end

local function read_json(path)
  if not file_exists(path) then
    return nil, "missing_file"
  end
  local lines = vim.fn.readfile(path)
  local raw = table.concat(lines, "\n")
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    return nil, "invalid_json"
  end
  return decoded, nil
end

local function write_json(path, payload)
  mkdir_parent(path)
  vim.fn.writefile({ vim.json.encode(payload) }, path)
end

local function copy_file(src, dst)
  local content = vim.fn.readfile(src, "b")
  mkdir_parent(dst)
  vim.fn.writefile(content, dst, "b")
end

local function is_windows()
  return platform.os.is_windows()
end

local function normalize_path(path)
  if type(path) ~= "string" then
    return ""
  end
  return platform.path.normalize(path, { slash = false })
end

local function ensure_executable(path)
  if is_windows() then
    return
  end
  pcall(vim.uv.fs_chmod, path, 493) -- 0755
end

local function parse_version(value)
  local raw = tostring(value or "")
  local first = raw:match("(%d+%.%d+[%w%._%-+]*)")
  if first ~= nil then
    return first
  end
  return ""
end

local function detect_platform_label()
  local os_info = platform.os.detect()
  return string.format("%s-%s", tostring(os_info.class), tostring(os_info.arch))
end

local function default_probe_args(entry)
  if type(entry.probe_args) == "table" and #entry.probe_args > 0 then
    return vim.deepcopy(entry.probe_args)
  end
  return { "--version" }
end

local function probe_tool(executable, entry, cfg)
  local argv = { executable }
  for _, token in ipairs(default_probe_args(entry)) do
    table.insert(argv, tostring(token))
  end

  local result = system.run_sync(argv, {
    timeout_ms = cfg.timeout_ms,
    actor = cfg.actor,
    origin = cfg.origin .. ".probe",
    allow_network = false,
    cwd = vim.uv.cwd(),
  })

  local probe_output = table.concat({ result.stdout or "", result.stderr or "" }, "\n")
  local detected = parse_version(probe_output)

  return {
    ok = result.ok == true,
    argv = argv,
    result = result,
    output = probe_output,
    version = detected,
  }
end

local function expected_version(entry, probe)
  local pinned = tostring(entry.version or "")
  if pinned ~= "" then
    return pinned
  end
  return tostring(probe.version or "")
end

local function sha256_file(path)
  if not file_exists(path) then
    return ""
  end
  local lines = vim.fn.readfile(path, "b")
  local payload = table.concat(lines, "\n")
  local digest = vim.fn.sha256(payload)
  if type(digest) ~= "string" or digest == "" then
    return ""
  end
  return "sha256:" .. digest
end

local function sanitize_filename_token(value)
  return tostring(value or ""):gsub("[^%w%._%-]", "_")
end

local function artifact_extension(entry)
  local executable = tostring(entry.executable or "")
  local suffix = executable:match("(%.[%w]+)$")
  if suffix ~= nil then
    return suffix
  end
  return ""
end

local function artifact_path(cfg, entry, version)
  local filename = string.format(
    "%s-%s%s",
    sanitize_filename_token(entry.name),
    sanitize_filename_token(version),
    artifact_extension(entry)
  )
  return normalize_path(cfg.artifact_root .. "/" .. filename)
end

local function normalize_manifest_tool(entry)
  if type(entry) ~= "table" then
    return nil
  end

  local name = tostring(entry.name or "")
  if name == "" then
    return nil
  end

  local mode = tostring(entry.mode or "system")
  if mode ~= "system" and mode ~= "managed" then
    mode = "system"
  end

  local executable = tostring(entry.executable or name)
  local source = tostring(entry.source or (mode == "managed" and "local-artifact" or "system-path"))

  local normalized = {
    name = name,
    mode = mode,
    executable = executable,
    source = source,
    version = tostring(entry.version or ""),
    source_path = tostring(entry.source_path or ""),
    platform = tostring(entry.platform or "any"),
    checksum = tostring(entry.checksum or ""),
    probe_args = default_probe_args(entry),
  }

  return normalized
end

local function sorted_registry_tools()
  local names = {}
  for name in pairs(registry.tools) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

function M.default_manifest(opts)
  local cfg = defaults(opts)
  local tools = {}

  for _, name in ipairs(sorted_registry_tools()) do
    local spec = registry.get(name)
    local executable = spec and spec.executables and spec.executables[1] or name
    tools[#tools + 1] = {
      name = name,
      mode = "system",
      executable = executable,
      source = "system-path",
      version = "",
      platform = "any",
      checksum = "",
      probe_args = { "--version" },
    }
  end

  return {
    schema = MANIFEST_SCHEMA,
    generated_at = now_iso(),
    install_root = cfg.install_root,
    tools = tools,
  }
end

local function normalize_manifest(doc, cfg)
  if type(doc) ~= "table" then
    return nil, "manifest must be a JSON object"
  end

  local schema = tostring(doc.schema or "")
  if schema ~= "" and schema ~= MANIFEST_SCHEMA then
    return nil, "unsupported manifest schema: " .. schema
  end

  local tools = {}
  for _, raw in ipairs(doc.tools or {}) do
    local normalized = normalize_manifest_tool(raw)
    if normalized == nil then
      return nil, "manifest tools include invalid entry"
    end
    tools[#tools + 1] = normalized
  end

  if #tools == 0 then
    return nil, "manifest tools list cannot be empty"
  end

  return {
    schema = MANIFEST_SCHEMA,
    install_root = tostring(doc.install_root or cfg.install_root),
    tools = tools,
  },
    nil
end

local function load_manifest(cfg, opts)
  opts = opts or {}
  local existing, reason = read_json(cfg.manifest_path)
  if existing == nil then
    if opts.create_if_missing ~= true then
      return nil, "manifest_missing"
    end
    local manifest = M.default_manifest(cfg)
    write_json(cfg.manifest_path, manifest)
    return normalize_manifest(manifest, cfg)
  end
  if reason ~= nil then
    return nil, reason
  end
  return normalize_manifest(existing, cfg)
end

local function backup_lockfile(cfg)
  if not file_exists(cfg.lockfile_path) then
    return false
  end
  copy_file(cfg.lockfile_path, cfg.rollback_path)
  return true
end

local function managed_destination(cfg, entry)
  local filename = entry.executable
  if is_windows() and filename:sub(-4):lower() ~= ".cmd" and filename:sub(-4):lower() ~= ".exe" then
    filename = filename .. ".cmd"
  end
  return normalize_path(cfg.install_root .. "/" .. filename)
end

local function resolve_system_executable(entry)
  local executable = platform.executable_path(entry.executable)
  if executable ~= "" then
    return executable
  end
  return ""
end

local function install_tool(entry, manifest, cfg)
  local tool = {
    name = entry.name,
    mode = entry.mode,
    source = entry.source,
    platform = detect_platform_label(),
    checksum = "",
    install_root = manifest.install_root,
    probe_args = vim.deepcopy(entry.probe_args),
    executable = "",
    provenance = {
      source_path = "",
      command = cfg.origin,
    },
  }

  if entry.mode == "managed" then
    if entry.source_path == "" or not file_exists(entry.source_path) then
      return nil,
        string.format(
          "tool %s managed source_path missing: %s",
          entry.name,
          entry.source_path ~= "" and entry.source_path or "<empty>"
        )
    end
    local destination = managed_destination(cfg, entry)
    copy_file(entry.source_path, destination)
    ensure_executable(destination)
    tool.executable = destination
    tool.provenance.source_path = normalize_path(entry.source_path)
    tool.checksum = entry.checksum ~= "" and entry.checksum or sha256_file(destination)
  else
    local executable = resolve_system_executable(entry)
    if executable == "" then
      return nil,
        string.format("tool %s executable not found in PATH: %s", entry.name, entry.executable)
    end
    tool.executable = normalize_path(executable)
    if entry.checksum ~= "" then
      tool.checksum = entry.checksum
    end
  end

  local probe = probe_tool(tool.executable, entry, cfg)
  if probe.ok ~= true then
    return nil, string.format("tool %s probe failed: %s", entry.name, tostring(probe.result.reason))
  end

  local expected = expected_version(entry, probe)
  if expected == "" then
    return nil, string.format("tool %s version probe returned empty output", entry.name)
  end

  if entry.version ~= "" and expected ~= probe.version then
    return nil,
      string.format(
        "tool %s version mismatch (expected %s, probed %s)",
        entry.name,
        entry.version,
        probe.version
      )
  end

  tool.version = expected
  tool.detected_version = probe.version
  tool.probe_output = vim.trim(probe.output)
  if entry.mode == "managed" then
    local archived = artifact_path(cfg, entry, expected)
    copy_file(tool.executable, archived)
    ensure_executable(archived)
    tool.provenance.archive_path = archived
  end

  return tool, nil
end

local function write_lockfile(cfg, manifest, tools, action)
  local os_info = platform.os.detect()
  local lock = {
    schema = LOCK_SCHEMA,
    generated_at = now_iso(),
    install_root = manifest.install_root,
    provenance = {
      action = action,
      manifest_path = cfg.manifest_path,
      lockfile_path = cfg.lockfile_path,
      actor = cfg.actor,
      origin = cfg.origin,
      host = {
        os_class = os_info.class,
        arch = os_info.arch,
      },
    },
    tools = tools,
  }

  write_json(cfg.lockfile_path, lock)
  return lock
end

local function run_manifest_apply(action, opts)
  local cfg = defaults(opts)
  local manifest, manifest_err = load_manifest(cfg, { create_if_missing = action ~= "restore" })
  if manifest == nil then
    return {
      ok = false,
      action = action,
      reason = manifest_err,
      errors = { "manifest load failed: " .. tostring(manifest_err) },
      manifest_path = cfg.manifest_path,
      lockfile_path = cfg.lockfile_path,
      rollback_path = cfg.rollback_path,
      install_root = cfg.install_root,
      tools = {},
    }
  end

  cfg.install_root = manifest.install_root
  vim.fn.mkdir(cfg.install_root, "p")
  vim.fn.mkdir(cfg.artifact_root, "p")

  local backed_up = backup_lockfile(cfg)
  local tools = {}
  local errors = {}

  for _, entry in ipairs(manifest.tools) do
    local installed, install_err = install_tool(entry, manifest, cfg)
    if installed then
      tools[#tools + 1] = installed
    else
      errors[#errors + 1] = install_err
    end
  end

  local lock = nil
  if #errors == 0 then
    lock = write_lockfile(cfg, manifest, tools, action)
  end

  return {
    ok = #errors == 0,
    action = action,
    reason = #errors == 0 and nil or "apply_failed",
    manifest_path = cfg.manifest_path,
    lockfile_path = cfg.lockfile_path,
    rollback_path = cfg.rollback_path,
    install_root = cfg.install_root,
    backed_up = backed_up,
    errors = errors,
    tools = tools,
    lock = lock,
  }
end

local function load_lockfile(cfg)
  local lock, reason = read_json(cfg.lockfile_path)
  if lock == nil then
    return nil, reason
  end
  if type(lock.tools) ~= "table" then
    return nil, "lockfile tools missing"
  end
  return lock, nil
end

local function restore_tool(tool, cfg)
  local entry = vim.deepcopy(tool)
  local errors = {}

  if entry.mode == "managed" then
    local archive_path = type(entry.provenance) == "table"
        and tostring(entry.provenance.archive_path or "")
      or ""
    local source_path = type(entry.provenance) == "table"
        and tostring(entry.provenance.source_path or "")
      or ""
    local restore_source = archive_path
    if restore_source == "" or not file_exists(restore_source) then
      restore_source = source_path
    end

    if restore_source == "" or not file_exists(restore_source) then
      errors[#errors + 1] = string.format(
        "tool %s restore source missing: archive=%s source=%s",
        tostring(entry.name),
        archive_path,
        source_path
      )
    else
      copy_file(restore_source, entry.executable)
      ensure_executable(entry.executable)
    end
  end

  local probe = probe_tool(entry.executable, entry, cfg)
  entry.probe_ok = probe.ok
  entry.probe_version = probe.version
  entry.probe_output = vim.trim(probe.output)

  if probe.ok ~= true then
    errors[#errors + 1] = string.format("tool %s probe failed during restore", tostring(entry.name))
  elseif tostring(entry.version or "") ~= tostring(probe.version or "") then
    errors[#errors + 1] = string.format(
      "tool %s version drift: expected %s got %s",
      tostring(entry.name),
      tostring(entry.version),
      tostring(probe.version)
    )
  end

  return entry, errors
end

function M.install(opts)
  return run_manifest_apply("install", opts)
end

function M.update(opts)
  return run_manifest_apply("update", opts)
end

function M.restore(opts)
  local cfg = defaults(opts)
  local lock, lock_err = load_lockfile(cfg)
  if lock == nil then
    return {
      ok = false,
      action = "restore",
      reason = lock_err,
      errors = { "lockfile load failed: " .. tostring(lock_err) },
      manifest_path = cfg.manifest_path,
      lockfile_path = cfg.lockfile_path,
      rollback_path = cfg.rollback_path,
      install_root = cfg.install_root,
      tools = {},
    }
  end

  local checked = {}
  local errors = {}
  for _, tool in ipairs(lock.tools or {}) do
    local restored, tool_errors = restore_tool(tool, cfg)
    checked[#checked + 1] = restored
    for _, item in ipairs(tool_errors) do
      errors[#errors + 1] = item
    end
  end

  return {
    ok = #errors == 0,
    action = "restore",
    reason = #errors == 0 and nil or "restore_failed",
    manifest_path = cfg.manifest_path,
    lockfile_path = cfg.lockfile_path,
    rollback_path = cfg.rollback_path,
    install_root = tostring(lock.install_root or cfg.install_root),
    tools = checked,
    errors = errors,
    lock = lock,
  }
end

function M.rollback(opts)
  local cfg = defaults(opts)
  if not file_exists(cfg.rollback_path) then
    return {
      ok = false,
      action = "rollback",
      reason = "rollback_missing",
      errors = { "rollback lockfile missing: " .. cfg.rollback_path },
      manifest_path = cfg.manifest_path,
      lockfile_path = cfg.lockfile_path,
      rollback_path = cfg.rollback_path,
      install_root = cfg.install_root,
      tools = {},
    }
  end

  copy_file(cfg.rollback_path, cfg.lockfile_path)
  local restored = M.restore(vim.tbl_extend("force", opts or {}, cfg))
  restored.action = "rollback"
  return restored
end

function M.health_report(opts)
  local cfg = defaults(opts)
  local lock, lock_err = load_lockfile(cfg)

  if lock == nil then
    return {
      ok = false,
      lockfile_present = false,
      reason = lock_err,
      drift_count = 0,
      tools = {},
      lockfile_path = cfg.lockfile_path,
      manifest_path = cfg.manifest_path,
      install_root = cfg.install_root,
    }
  end

  local tools = {}
  local drift_count = 0
  for _, tool in ipairs(lock.tools or {}) do
    local probe = probe_tool(tool.executable, tool, cfg)
    local drift = probe.ok ~= true or tostring(probe.version or "") ~= tostring(tool.version or "")
    if drift then
      drift_count = drift_count + 1
    end
    tools[#tools + 1] = {
      name = tool.name,
      expected_version = tool.version,
      detected_version = probe.version,
      executable = tool.executable,
      source = tool.source,
      mode = tool.mode,
      checksum = tool.checksum,
      drift = drift,
      probe_ok = probe.ok,
      reason = probe.ok and nil or (probe.result and probe.result.reason or "probe_failed"),
    }
  end

  return {
    ok = true,
    lockfile_present = true,
    schema = lock.schema,
    lockfile_generated_at = lock.generated_at,
    lockfile_path = cfg.lockfile_path,
    manifest_path = cfg.manifest_path,
    install_root = tostring(lock.install_root or cfg.install_root),
    drift_count = drift_count,
    tools = tools,
  }
end

local function fmt_errors(errors)
  if type(errors) ~= "table" then
    return {}
  end
  local lines = {}
  for _, item in ipairs(errors) do
    lines[#lines + 1] = "- " .. tostring(item)
  end
  return lines
end

function M.render_action_lines(report)
  local lines = {
    string.format("Jig toolchain action: %s", tostring(report.action or "unknown")),
    string.rep("=", 64),
    string.format("ok: %s", tostring(report.ok == true)),
    string.format("manifest_path: %s", tostring(report.manifest_path or "")),
    string.format("lockfile_path: %s", tostring(report.lockfile_path or "")),
    string.format("rollback_path: %s", tostring(report.rollback_path or "")),
    string.format("install_root: %s", tostring(report.install_root or "")),
    string.format("backup_created: %s", tostring(report.backed_up == true)),
  }

  if report.reason then
    lines[#lines + 1] = string.format("reason: %s", tostring(report.reason))
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "tools:"
  for _, tool in ipairs(report.tools or {}) do
    lines[#lines + 1] = string.format(
      "- %s mode=%s version=%s executable=%s",
      tostring(tool.name),
      tostring(tool.mode or ""),
      tostring(tool.version or tool.probe_version or ""),
      tostring(tool.executable or "")
    )
  end

  if #(report.errors or {}) > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "errors:"
    vim.list_extend(lines, fmt_errors(report.errors))
  end

  return lines
end

function M.render_health_lines(report)
  local lines = {
    "Jig toolchain drift report",
    string.rep("=", 64),
    string.format("lockfile_present: %s", tostring(report.lockfile_present == true)),
    string.format("lockfile_path: %s", tostring(report.lockfile_path or "")),
    string.format("manifest_path: %s", tostring(report.manifest_path or "")),
    string.format("install_root: %s", tostring(report.install_root or "")),
    string.format("drift_count: %d", tonumber(report.drift_count) or 0),
  }

  if report.lockfile_generated_at then
    lines[#lines + 1] =
      string.format("lockfile_generated_at: %s", tostring(report.lockfile_generated_at))
  end

  if report.lockfile_present ~= true then
    lines[#lines + 1] =
      "lockfile missing. Run :JigToolchainInstall to create or refresh lock state explicitly."
    return lines
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "tools:"
  for _, tool in ipairs(report.tools or {}) do
    if tool.drift then
      lines[#lines + 1] = string.format(
        "- %s drift expected=%s detected=%s executable=%s",
        tostring(tool.name),
        tostring(tool.expected_version or ""),
        tostring(tool.detected_version or "<probe-failed>"),
        tostring(tool.executable or "")
      )
    else
      lines[#lines + 1] = string.format(
        "- %s ok version=%s executable=%s",
        tostring(tool.name),
        tostring(tool.expected_version or ""),
        tostring(tool.executable or "")
      )
    end
  end

  return lines
end

return M
