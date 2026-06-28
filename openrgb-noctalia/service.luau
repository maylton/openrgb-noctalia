-- OpenRGB Noctalia v0.1.1
-- Headless Noctalia v5 service.
--
-- The service installs a tiny Noctalia theme bridge in the user's config.
-- That bridge sends the resolved primary color back to this service over IPC.
-- Album Aura and Nocky are also read directly so their palettes can be applied
-- without forcing every application template to refresh.

local PLUGIN_ID = "maylton/openrgb-noctalia"
local SERVICE_ENTRY = PLUGIN_ID .. ":sync"
local ALBUM_AURA_PALETTE = "AlbumAura"

local function cfg(key, fallback)
  local value = noctalia.getConfig(key)
  if value == nil then
    return fallback
  end
  return value
end

local function trim(value)
  if value == nil then
    return ""
  end
  return (tostring(value):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function shellQuote(value)
  return "'" .. tostring(value):gsub("'", "'\"'\"'") .. "'"
end

local function joinPath(left, right)
  if left:sub(-1) == "/" then
    return left .. right
  end
  return left .. "/" .. right
end

local home = noctalia.getenv("HOME") or "/tmp"
local xdgConfigHome = noctalia.getenv("XDG_CONFIG_HOME") or joinPath(home, ".config")
local xdgStateHome = noctalia.getenv("XDG_STATE_HOME") or joinPath(home, ".local/state")
local xdgRuntimeDir = noctalia.getenv("XDG_RUNTIME_DIR") or "/tmp"

local noctaliaConfigBase = noctalia.getenv("NOCTALIA_CONFIG_HOME")
local configDir
if noctaliaConfigBase ~= nil and noctaliaConfigBase ~= "" then
  configDir = joinPath(noctaliaConfigBase, "noctalia")
else
  configDir = joinPath(xdgConfigHome, "noctalia")
end

local stateDir = joinPath(xdgStateHome, "openrgb-noctalia")
local runtimeEnabledPath = joinPath(stateDir, "runtime-enabled.txt")
local logPath = joinPath(stateDir, "openrgb-noctalia.log")
local lastStatePath = joinPath(stateDir, "last-state.json")

local bridgeTemplatePath = joinPath(configDir, "templates/openrgb-noctalia-primary.txt.in")
local bridgeOutputPath = joinPath(configDir, "generated/openrgb-noctalia-primary.txt")
local bridgeConfigPath = joinPath(configDir, "openrgb-noctalia.toml")
local albumAuraPalettePath = joinPath(configDir, "palettes/" .. ALBUM_AURA_PALETTE .. ".json")
local nockyBridgePath = joinPath(xdgRuntimeDir, "nocky/album-aura.json")
local helperPath = joinPath(noctalia.pluginDir(), "apply_color.py")

local runtimeEnabled = true
local commandPending = false
local schemePending = false
local lastAppliedInput = ""
local lastAppliedOutput = ""
local lastSource = ""
local lastScheme = ""
local lastNockyRevision = ""
local lastAlbumAuraFingerprint = ""
local bootstrapped = false

local status = {
  available = false,
  enabled = false,
  master_enabled = true,
  runtime_enabled = true,
  state = "starting",
  source = "",
  scheme = "",
  input_color = "",
  output_color = "",
  corrected = false,
  error = "",
}

local function writeLog(message)
  local line = noctalia.formatTime("%Y-%m-%d %H:%M:%S") .. " | " .. tostring(message) .. "\n"
  local previous = ""
  if noctalia.fileExists(logPath) then
    previous = noctalia.readFile(logPath) or ""
  end
  if #previous > 120000 then
    previous = previous:sub(-60000)
  end
  noctalia.writeFile(logPath, previous .. line)
end

local function saveStatus()
  status.master_enabled = cfg("enabled", true) == true
  status.runtime_enabled = runtimeEnabled
  status.enabled = status.master_enabled and status.runtime_enabled
  noctalia.state.set("status", status)
  local encoded = noctalia.json.encode(status, true)
  if encoded ~= nil then
    noctalia.writeFile(lastStatePath, encoded .. "\n")
  end
end

local function notifyError(message)
  local mode = cfg("notifications", "errors")
  if mode ~= "off" then
    noctalia.notifyError(noctalia.tr("notify.error.title"), message)
  end
end

local function notifyChange(source, color)
  if cfg("notifications", "errors") == "changes" then
    noctalia.notify(
      noctalia.tr("notify.applied.title"),
      noctalia.tr("notify.applied.body", {
        source = source,
        color = "#" .. color,
      })
    )
  end
end

local function effectiveEnabled()
  return cfg("enabled", true) == true and runtimeEnabled
end

local function publishState(nextState, errorMessage)
  status.state = nextState
  status.error = errorMessage or ""
  saveStatus()
end

local function readRuntimeEnabled()
  if not noctalia.fileExists(runtimeEnabledPath) then
    runtimeEnabled = true
    return
  end
  runtimeEnabled = trim(noctalia.readFile(runtimeEnabledPath)) ~= "false"
end

local function writeRuntimeEnabled()
  noctalia.writeFile(runtimeEnabledPath, runtimeEnabled and "true\n" or "false\n")
  saveStatus()
end

local function normalizeColor(value)
  local color = trim(value):gsub("^#", ""):upper()
  if color:match("^[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$") then
    return color
  end
  return nil
end

local function payloadValue(payload)
  if type(payload) == "string" then
    return payload
  end
  if type(payload) == "table" then
    if payload[1] ~= nil then
      return tostring(payload[1])
    end
    if payload.color ~= nil then
      return tostring(payload.color)
    end
  end
  return ""
end

local function modePrimary(palette)
  if type(palette) ~= "table" then
    return nil
  end
  local variant = noctalia.isDarkMode() and palette.dark or palette.light
  if type(variant) ~= "table" then
    variant = palette.dark
  end
  if type(variant) ~= "table" then
    return nil
  end
  return normalizeColor(variant.mPrimary or variant.primary or "")
end

local function decodeJsonFile(path)
  if not noctalia.fileExists(path) then
    return nil
  end
  local decoded = noctalia.json.decode(noctalia.readFile(path) or "")
  if type(decoded) ~= "table" then
    return nil
  end
  return decoded
end

local function sourceAllowed(source)
  if source == "album-aura" and cfg("follow_album_aura", true) ~= true then
    return false
  end
  if source == "nocky" and cfg("follow_nocky", true) ~= true then
    return false
  end
  return true
end

local function applyColor(rawColor, source)
  local color = normalizeColor(rawColor)
  if color == nil then
    publishState("error", "Invalid RGB color: " .. tostring(rawColor))
    writeLog("invalid color from " .. tostring(source) .. ": " .. tostring(rawColor))
    notifyError(noctalia.tr("notify.error.invalid_color"))
    return
  end

  if not sourceAllowed(source) then
    publishState("ignored")
    return
  end

  if not effectiveEnabled() then
    publishState("disabled")
    return
  end

  if not noctalia.commandExists("openrgb") then
    status.available = false
    publishState("missing-dependency", "openrgb command not found")
    notifyError(noctalia.tr("notify.error.openrgb_missing"))
    return
  end

  if commandPending then
    return
  end

  if color == lastAppliedInput and source == lastSource then
    return
  end

  commandPending = true
  publishState("applying")

  local command = table.concat({
    "python3",
    shellQuote(helperPath),
    "--color", shellQuote(color),
    "--source", shellQuote(source),
    "--mode", shellQuote(cfg("openrgb_mode", "direct")),
    "--pastel-correction", cfg("pastel_correction", true) and "true" or "false",
    "--saturation-threshold", tostring(cfg("pastel_saturation_threshold", 0.45)),
    "--brightness-threshold", tostring(cfg("pastel_brightness_threshold", 0.85)),
    "--target-saturation", tostring(cfg("pastel_target_saturation", 0.65)),
    "--target-brightness", tostring(cfg("pastel_target_brightness", 0.85)),
    "--sdk-server", cfg("use_sdk_server", false) and "true" or "false",
    "--lock-file", shellQuote(joinPath(xdgRuntimeDir, "openrgb-noctalia.lock")),
  }, " ")

  local started = noctalia.runAsync(command, function(result)
    commandPending = false

    local decoded = noctalia.json.decode(result.stdout or "")
    if result.exitCode ~= 0 or type(decoded) ~= "table" or decoded.ok ~= true then
      local errorMessage = trim(result.stderr)
      if type(decoded) == "table" and decoded.error ~= nil then
        errorMessage = tostring(decoded.error)
      end
      if errorMessage == "" then
        errorMessage = "OpenRGB exited with code " .. tostring(result.exitCode)
      end
      publishState("error", errorMessage)
      writeLog("apply failed: " .. errorMessage)
      notifyError(errorMessage)
      return
    end

    lastAppliedInput = tostring(decoded.input_color or color)
    lastAppliedOutput = tostring(decoded.output_color or color)
    lastSource = source

    status.available = true
    status.source = source
    status.input_color = lastAppliedInput
    status.output_color = lastAppliedOutput
    status.corrected = decoded.corrected == true
    publishState("active")

    writeLog(
      source
        .. " #" .. lastAppliedInput
        .. " -> OpenRGB #" .. lastAppliedOutput
        .. (status.corrected and " (pastel corrected)" or " (exact)")
    )
    notifyChange(source, lastAppliedOutput)
  end, 30000)

  if not started then
    commandPending = false
    publishState("error", "Could not start the OpenRGB helper")
    notifyError(noctalia.tr("notify.error.helper_start"))
  end
end

local function applyAlbumAura()
  if cfg("follow_album_aura", true) ~= true then
    return
  end
  local palette = decodeJsonFile(albumAuraPalettePath)
  if palette == nil then
    return
  end
  local fingerprint = noctalia.json.encode(palette, false) or ""
  if fingerprint == lastAlbumAuraFingerprint then
    return
  end
  local color = modePrimary(palette)
  if color ~= nil then
    lastAlbumAuraFingerprint = fingerprint
    applyColor(color, "album-aura")
  end
end

local function applyNocky()
  if cfg("follow_nocky", true) ~= true then
    return
  end
  local bridge = decodeJsonFile(nockyBridgePath)
  if bridge == nil or bridge.active ~= true then
    return
  end

  local revision = tostring(bridge.palette_hash or bridge.revision or bridge.updated_at or "")
  if revision ~= "" and revision == lastNockyRevision then
    return
  end

  local palette = bridge.palette
  if type(palette) ~= "table" and type(bridge.palette_path) == "string" then
    palette = decodeJsonFile(bridge.palette_path)
  end

  local color = modePrimary(palette)
  if color ~= nil then
    lastNockyRevision = revision
    applyColor(color, "nocky")
  end
end

local function inspectScheme()
  if schemePending then
    return
  end
  schemePending = true

  local started = noctalia.runAsync("noctalia msg color-scheme-get", function(result)
    schemePending = false
    if result.exitCode ~= 0 then
      return
    end

    local scheme = trim(result.stdout)
    status.scheme = scheme

    if scheme == "custom " .. ALBUM_AURA_PALETTE then
      applyAlbumAura()
    elseif scheme ~= "" and scheme ~= lastScheme then
      -- Re-render only when the selected scheme changes. The dedicated bridge
      -- then sends the exact resolved primary color back through IPC.
      noctalia.runAsync("noctalia msg templates-apply")
    end

    lastScheme = scheme
    saveStatus()
  end)

  if not started then
    schemePending = false
  end
end

local BRIDGE_TEMPLATE = "{{ colors.primary.default.hex_stripped }}\n"

local BRIDGE_CONFIG = [[
# Managed by maylton/openrgb-noctalia.
# Remove the plugin with uninstall.sh to clean up this bridge.

[theme.templates.user.openrgb_noctalia]
input_path  = "./templates/openrgb-noctalia-primary.txt.in"
output_path = "./generated/openrgb-noctalia-primary.txt"
post_hook   = 'noctalia msg plugin maylton/openrgb-noctalia:sync all palette "{{ colors.primary.default.hex_stripped }}"'
]]

local function writeBridgeFiles()
  local changed = false

  if not noctalia.fileExists(bridgeTemplatePath)
      or (noctalia.readFile(bridgeTemplatePath) or "") ~= BRIDGE_TEMPLATE then
    noctalia.writeFile(bridgeTemplatePath, BRIDGE_TEMPLATE)
    changed = true
  end

  if not noctalia.fileExists(bridgeConfigPath)
      or (noctalia.readFile(bridgeConfigPath) or "") ~= BRIDGE_CONFIG then
    noctalia.writeFile(bridgeConfigPath, BRIDGE_CONFIG)
    changed = true
  end

  if changed then
    noctalia.runAsync("noctalia msg config-reload", function()
      noctalia.runAsync("noctalia msg templates-apply")
    end)
  elseif cfg("apply_on_startup", true) == true then
    noctalia.runAsync("noctalia msg templates-apply")
  end
end

local function ensureBridge(callback)
  local mkdirCommand = table.concat({
    "mkdir -p",
    shellQuote(stateDir),
    shellQuote(joinPath(configDir, "templates")),
    shellQuote(joinPath(configDir, "generated")),
  }, " ")

  local started = noctalia.runAsync(mkdirCommand, function(result)
    if result.exitCode ~= 0 then
      publishState("error", "Could not create plugin state/config directories")
      notifyError(noctalia.tr("notify.error.directories"))
      return
    end

    writeBridgeFiles()
    if callback ~= nil then
      callback()
    end
  end)

  if not started then
    publishState("error", "Could not initialize plugin directories")
    notifyError(noctalia.tr("notify.error.directories"))
  end
end

local function cleanupBridge()
  local command = table.concat({
    "rm -f",
    shellQuote(bridgeTemplatePath),
    shellQuote(bridgeOutputPath),
    shellQuote(bridgeConfigPath),
  }, " ")
  noctalia.runAsync(command, function()
    noctalia.runAsync("noctalia msg config-reload")
  end)
end

local function setRuntimeEnabled(value)
  runtimeEnabled = value == true
  writeRuntimeEnabled()
  if effectiveEnabled() then
    publishState("idle")
    noctalia.runAsync("noctalia msg templates-apply")
    applyNocky()
    applyAlbumAura()
  else
    publishState("disabled")
  end
end

function update()
  local interval = tonumber(cfg("poll_interval_ms", 1000)) or 1000
  if interval < 500 then
    interval = 500
  end
  noctalia.setUpdateInterval(interval)

  status.master_enabled = cfg("enabled", true) == true
  status.runtime_enabled = runtimeEnabled

  if not effectiveEnabled() then
    publishState("disabled")
    return
  end

  inspectScheme()
  applyNocky()
end

function onIpc(event, payload)
  if event == "palette" then
    applyColor(payloadValue(payload), "noctalia")
  elseif event == "apply" or event == "refresh" then
    lastAppliedInput = ""
    lastAppliedOutput = ""
    lastSource = ""
    lastNockyRevision = ""
    lastAlbumAuraFingerprint = ""
    noctalia.runAsync("noctalia msg templates-apply")
    inspectScheme()
    applyNocky()
    applyAlbumAura()
  elseif event == "toggle" then
    setRuntimeEnabled(not runtimeEnabled)
  elseif event == "enable" then
    setRuntimeEnabled(true)
  elseif event == "disable" then
    setRuntimeEnabled(false)
  elseif event == "status" then
    noctalia.log("openrgb-noctalia status: " .. (noctalia.json.encode(status, false) or "{}"))
  elseif event == "cleanup" then
    setRuntimeEnabled(false)
    cleanupBridge()
  else
    noctalia.log("openrgb-noctalia: unknown IPC event '" .. tostring(event) .. "'")
  end
end

readRuntimeEnabled()
status.available = noctalia.commandExists("openrgb")
noctalia.setUpdateInterval(1000)

ensureBridge(function()
  bootstrapped = true
  publishState(effectiveEnabled() and "idle" or "disabled")
end)
