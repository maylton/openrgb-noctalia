-- Control-center shortcut for maylton/openrgb-noctalia.

local SERVICE = "maylton/openrgb-noctalia:sync"

local function render(value)
  local status = value
  if type(status) ~= "table" then
    status = noctalia.state.get("status")
  end
  if type(status) ~= "table" then
    status = {
      enabled = false,
      state = "starting",
      output_color = "",
    }
  end

  local active = status.enabled == true and status.state ~= "error"
  shortcut.setLabel(active and noctalia.tr("shortcut.on") or noctalia.tr("shortcut.off"))
  shortcut.setIcon("palette")
  shortcut.setActive(active)
  shortcut.setEnabled(status.state ~= "missing-dependency")
end

function onClick()
  noctalia.runAsync(
    "noctalia msg plugin " .. SERVICE .. " all toggle"
  )
end

function onRightClick()
  noctalia.runAsync(
    "noctalia msg plugin " .. SERVICE .. " all apply"
  )
end

noctalia.state.watch("status", render)
render(noctalia.state.get("status"))
