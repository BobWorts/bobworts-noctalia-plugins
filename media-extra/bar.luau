--!nonstrict

local Common = require("./lib/common.luau")
local Artwork = require("./lib/artwork.luau")
local Config = require("./lib/config.luau")
local Player = require("./lib/player.luau")
local Text = require("./lib/text.luau")
local UI = require("./lib/ui.luau")

local UI_TICK_MS = 100
local OPTIMISTIC_MS = 1500

local state = {
  record = nil,
  lastPlayer = nil,
  hovered = false,
  hoverKeys = {},
  lastTick = 0,
  optimistic = nil,
  optimisticUntil = 0,
  cliWarned = false,
  textKey = "",
  renderKey = nil,
  vertical = false,
  disposed = false,
}

local cfg = nil
local columns = 16
local marquee = Text.newMarquee({ columns = 16, gap = 3, speed = 8 })
local dataDir = noctalia.pluginDataDir()
if dataDir == nil then
  Common.log("artwork.dir", "plugin data directory unavailable")
end

local render

local artwork = Artwork.new({
  dir = dataDir,
  onReady = function()
    render()
  end,
})

artwork:cleanup()
noctalia.setUpdateInterval(UI_TICK_MS)

local function translate(key, variables)
  if variables == nil then
    return noctalia.tr(key)
  end
  return noctalia.tr(key, variables)
end

local function notifyError(titleKey, bodyKey, variables)
  noctalia.notifyError(translate(titleKey, variables), translate(bodyKey, variables))
end

local function effectiveStatus(record)
  if record == nil then
    return "Stopped"
  end
  if state.optimistic ~= nil then
    if noctalia.nowMs() < state.optimisticUntil then
      return state.optimistic
    end
    state.optimistic = nil
  end
  return record.status
end

local function displayText(record)
  if record == nil then
    return ""
  end
  return Text.compose(record, cfg)
end

local COMMAND_KEYS = {
  toggle = "command.toggle",
  next = "command.next",
  previous = "command.previous",
  ["next-player"] = "command.next_player",
  ["previous-player"] = "command.previous_player",
}

local function reportCommandFailure(name)
  local label = translate(COMMAND_KEYS[name] or "command.unknown")
  notifyError("notify.command_failed.title", "notify.command_failed.body", { command = label })
end

local function sendCommand(name)
  if not Player.available() then
    if not state.cliWarned then
      state.cliWarned = true
      notifyError("notify.cli_missing.title", "notify.cli_missing.body")
    end
    return false
  end
  if not Player.send(name, reportCommandFailure) then
    reportCommandFailure(name)
    return false
  end
  return true
end

local function openPlayer()
  local record = state.record or state.lastPlayer
  if record == nil then
    notifyError("notify.no_player.title", "notify.no_player.body")
    return
  end
  Player.open(record, translate, true)
end

local function toggle()
  if state.record == nil then
    openPlayer()
    return
  end
  local playing = effectiveStatus(state.record) == "Playing"
  local nextStatus = playing and "Paused" or "Playing"
  if not sendCommand("toggle") then
    return
  end
  state.optimistic = nextStatus
  state.optimisticUntil = noctalia.nowMs() + OPTIMISTIC_MS
  render()
end

local function configureMarquee()
  if cfg == nil then
    return
  end
  local layout = UI.resolve(cfg, state.vertical)
  columns = layout.columns
  marquee:configure(columns, cfg.marquee_gap, cfg.scroll_speed)
end

local function loadConfig()
  cfg = Config.read()
  state.vertical = barWidget.isVertical()
  state.textKey = ""
  configureMarquee()
end

local function poll()
  local record = Player.snapshot()
  state.record = record
  if record ~= nil then
    state.lastPlayer = record
    if state.optimistic ~= nil and record.status == state.optimistic then
      state.optimistic = nil
    end
  else
    state.optimistic = nil
  end
  if cfg ~= nil and UI.resolve(cfg, state.vertical).showArt then
    artwork:set(record ~= nil and record.artUrl or "")
  end
  render()
end

local function idleModel(layout, status)
  local idleIconPath = nil
  if cfg.idle_mode == "app_icon" then
    idleIconPath = Player.iconPath(state.lastPlayer, cfg.art_size)
  end
  return {
    config = cfg,
    layout = layout,
    record = nil,
    status = status,
    label = "",
    visibleText = "",
    artworkPath = nil,
    playerIconPath = nil,
    idleIconPath = idleIconPath,
    progress = 0,
    vertical = state.vertical,
    idleGlyph = UI.idleGlyph(cfg),
    placeholderGlyph = UI.placeholderGlyph(cfg),
    translate = translate,
  }
end

local function buildModel()
  if cfg == nil then
    return nil
  end

  local vertical = barWidget.isVertical()
  if vertical ~= state.vertical then
    state.vertical = vertical
    configureMarquee()
    state.textKey = ""
  end

  local record = state.record
  local status = effectiveStatus(record)
  local layout = UI.resolve(cfg, state.vertical)

  if record == nil then
    if cfg.hide_when_no_media or cfg.hide_when_idle then
      return nil
    end
    return idleModel(layout, status)
  end

  if cfg.hide_when_idle and status ~= "Playing" then
    return nil
  end

  local label = displayText(record)
  local signature = UI.textKey(cfg, record, state.vertical)
  if signature ~= state.textKey then
    marquee:setText(label, signature)
    state.textKey = signature
  else
    marquee:replace(label, signature)
  end

  local visibleText = label
  if cfg.text_scroll == "never" then
    visibleText = Text.truncate(label, layout.columns)
  else
    visibleText = marquee:window()
  end

  local artworkPath = nil
  if layout.showArt then
    artworkPath = artwork:path()
  end

  local playerIconPath = nil
  if layout.showArt and cfg.placeholder == "app_icon" then
    playerIconPath = Player.iconPath(record, cfg.art_size)
  end

  return {
    config = cfg,
    layout = layout,
    record = record,
    status = status,
    label = label,
    visibleText = visibleText,
    artworkPath = artworkPath,
    playerIconPath = playerIconPath,
    idleIconPath = nil,
    progress = Player.progress(record),
    vertical = state.vertical,
    idleGlyph = UI.idleGlyph(cfg),
    placeholderGlyph = UI.placeholderGlyph(cfg),
    translate = translate,
  }
end

render = function()
  if cfg == nil or state.disposed then
    return
  end
  local model = buildModel()
  if model == nil then
    if state.renderKey ~= "hidden" then
      state.renderKey = "hidden"
      barWidget.setVisible(false)
    end
    return
  end
  local key = UI.modelKey(model)
  if key == state.renderKey then
    return
  end
  state.renderKey = key
  local tree = UI.build(model)
  if tree == nil then
    barWidget.setVisible(false)
    return
  end
  barWidget.setVisible(true)
  barWidget.render(tree)
end

local function updateImpl()
  if state.disposed then
    return
  end
  if cfg == nil then
    loadConfig()
    state.lastTick = noctalia.nowMs()
    poll()
    return
  end

  local now = noctalia.nowMs()
  poll()

  if state.optimistic ~= nil and now >= state.optimisticUntil then
    state.optimistic = nil
  end

  local delta = now - state.lastTick
  state.lastTick = now
  if delta > 1000 then
    delta = 1000
  end

  local layout = UI.resolve(cfg, state.vertical)
  local active = state.record ~= nil and layout.showText and cfg.text_scroll ~= "never"
    and (cfg.text_scroll == "always" or state.hovered)
  if active then
    marquee:advance(delta)
    render()
  end
end

local function onHoverImpl(value, key)
  local active = value == true or value == "true"
  key = key or "root"
  if active then
    state.hoverKeys[key] = true
  else
    state.hoverKeys[key] = nil
  end
  state.hovered = next(state.hoverKeys) ~= nil
  if not state.hovered and cfg ~= nil and cfg.text_scroll == "hover" then
    marquee:reset()
  end
end

local function onIpcImpl(event)
  if event == "dump" then
    Common.log("dump", tostring(noctalia.json.encode({
      record = state.record,
      config = cfg,
      status = effectiveStatus(state.record),
      vertical = state.vertical,
      textKey = state.textKey,
    })))
  elseif event == "refresh" then
    poll()
  elseif event == "toggle" then
    toggle()
  elseif event == "next" then
    sendCommand("next")
  elseif event == "previous" then
    sendCommand("previous")
  elseif event == "next-player" then
    sendCommand("next-player")
  elseif event == "previous-player" then
    sendCommand("previous-player")
  elseif event == "open" then
    openPlayer()
  end
end

local function onExitImpl()
  if state.disposed then
    return
  end
  state.disposed = true
  artwork:dispose()
end

function update()
  updateImpl()
end

function onHover(value, key)
  onHoverImpl(value, key)
end

function onPrimaryClick()
  openPlayer()
end

function onClick()
  openPlayer()
end

function onPrevious()
  sendCommand("previous")
end

function onNext()
  sendCommand("next")
end

function onToggle()
  toggle()
end

function onConfigChanged()
  loadConfig()
  render()
end

function onIpc(event)
  onIpcImpl(event)
end

function onExit()
  onExitImpl()
end
