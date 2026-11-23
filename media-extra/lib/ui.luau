--!nonstrict

local ConfigModule = require("./config.luau")
local Text = require("./text.luau")

type Track = ConfigModule.Track
type Settings = ConfigModule.Config
type Layout = ConfigModule.Layout

local UI = {}

local TEXT_HEIGHT_PADDING = 8
local ART_RADIUS_MIN = 2
local ART_RADIUS_RATIO = 0.2
local GLYPH_PREVIOUS = "caret-left-filled"
local GLYPH_PLAY = "player-play-filled"
local GLYPH_PAUSE = "player-pause-filled"
local GLYPH_NEXT = "caret-right-filled"
local COLOR_PRIMARY = "primary"
local COLOR_PROGRESS_TRACK = "surface_container"
local SENTINEL = string.char(1)
local DEFAULT_IDLE_GLYPH = "music"
local DEFAULT_PLACEHOLDER_GLYPH = "music"

local PRESETS = {
  art_text_controls = { true, true, true },
  art_text = { true, true, false },
  text_controls = { false, true, true },
  art_controls = { true, false, true },
  art_only = { true, false, false },
  text_only = { false, true, false },
  controls_only = { false, false, true },
  custom = { false, false, false },
}

export type Model = {
  config: Settings,
  layout: Layout,
  record: Track?,
  status: string,
  label: string,
  visibleText: string,
  artworkPath: string?,
  playerIconPath: string?,
  idleIconPath: string?,
  progress: number,
  vertical: boolean,
  idleGlyph: string,
  placeholderGlyph: string,
  translate: (string, { [string]: string }?) -> string,
}

function UI.artRadius(shape, size)
  if shape == "circle" then
    return math.floor(size / 2)
  end
  if shape == "square" then
    return 0
  end
  return math.max(ART_RADIUS_MIN, math.floor(size * ART_RADIUS_RATIO))
end

function UI.resolve(settings, vertical)
  local preset = PRESETS[settings.layout] or PRESETS.art_text_controls
  local showArt = preset[1]
  local showText = preset[2]
  local showControls = preset[3]
  if settings.layout == "custom" then
    showArt = settings.show_artwork
    showText = settings.show_text
    showControls = settings.show_controls
  end
  if settings.controls_style == "none" then
    showControls = false
  end
  local textWidth = vertical and settings.vertical_text_width or settings.text_width
  local artSize = settings.art_size
  return {
    showArt = showArt,
    showText = showText,
    showControls = showControls,
    textWidth = textWidth,
    artSize = artSize,
    artRadius = UI.artRadius(settings.art_shape, artSize),
    artGap = settings.art_gap,
    buttonSize = settings.button_size,
    iconSize = settings.icon_size,
    textHeight = math.max(settings.button_size, settings.font_size + TEXT_HEIGHT_PADDING),
    columns = Text.columnsForWidth(textWidth, settings.font_size),
    vertical = vertical,
  }
end

function UI.idleGlyph(settings)
  if type(settings.idle_glyph) == "string" and settings.idle_glyph ~= "" then
    return settings.idle_glyph
  end
  return DEFAULT_IDLE_GLYPH
end

function UI.placeholderGlyph(settings)
  if type(settings.placeholder_glyph) == "string" and settings.placeholder_glyph ~= "" then
    return settings.placeholder_glyph
  end
  return DEFAULT_PLACEHOLDER_GLYPH
end

function UI.textKey(settings, record, vertical)
  local width = vertical and settings.vertical_text_width or settings.text_width
  local artists = ""
  if record ~= nil and type(record.artists) == "table" then
    artists = table.concat(record.artists, ",")
  end
  return table.concat({
    settings.layout,
    settings.text_format,
    settings.text_template,
    tostring(width),
    tostring(settings.font_size),
    settings.text_scroll,
    record and record.trackId or "",
    record and record.identity or "",
    record and record.title or "",
    artists,
    record and record.album or "",
  }, SENTINEL)
end

function UI.modelKey(model)
  local config = model.config
  local layout = model.layout
  return table.concat({
    config.layout,
    config.text_format,
    config.text_template,
    config.text_scroll,
    config.placeholder,
    config.idle_mode,
    config.progress_style,
    config.controls_style,
    tostring(layout.textWidth),
    tostring(layout.columns),
    tostring(layout.artSize),
    tostring(layout.artRadius),
    tostring(layout.artGap),
    tostring(layout.buttonSize),
    tostring(layout.iconSize),
    tostring(config.font_size),
    tostring(config.progress_thickness),
    tostring(model.vertical),
    model.status,
    model.label,
    model.visibleText,
    model.artworkPath or "",
    model.playerIconPath or "",
    model.idleIconPath or "",
    tostring(math.floor((model.progress or 0) * 1000)),
  }, SENTINEL)
end

local function imageNode(model, key, path)
  local size = model.layout.artSize
  return ui.image({
    key = key,
    path = path,
    width = size,
    height = size,
    radius = model.layout.artRadius,
    fit = "cover",
    onClick = "onPrimaryClick",
    onHover = "onHover",
  })
end

local function glyphButton(model, key, glyph, tooltip, click, size, glyphSize)
  return ui.button({
    key = key,
    glyph = glyph,
    glyphSize = math.min(glyphSize, size),
    width = size,
    height = size,
    variant = "ghost",
    tooltip = tooltip,
    onClick = click,
    onHover = "onHover",
  })
end

local function artNode(model)
  if model.artworkPath ~= nil and model.artworkPath ~= "" then
    return imageNode(model, "artwork", model.artworkPath)
  end
  if model.config.placeholder == "app_icon" and model.playerIconPath ~= nil then
    return imageNode(model, "artwork-icon", model.playerIconPath)
  end
  if model.config.placeholder == "glyph" then
    return glyphButton(
      model,
      "artwork-glyph",
      model.placeholderGlyph,
      model.label,
      "onPrimaryClick",
      model.layout.artSize,
      model.layout.iconSize
    )
  end
  return nil
end

local function idleNode(model)
  if model.config.idle_mode == "hidden" then
    return nil
  end
  local label = model.translate("tooltip.idle")
  if model.config.idle_mode == "app_icon" and model.idleIconPath ~= nil then
    return imageNode(model, "idle-icon", model.idleIconPath)
  end
  return glyphButton(
    model,
    "idle-glyph",
    model.idleGlyph,
    label,
    "onPrimaryClick",
    model.layout.artSize,
    model.layout.iconSize
  )
end

local function textNode(model)
  if model.label == "" or model.visibleText == "" then
    return nil
  end
  local showProgress = model.config.progress_style == "bar"
    and model.record ~= nil
    and (model.record.lengthMs or 0) > 0
  local thickness = model.config.progress_thickness
  local buttonHeight = model.layout.textHeight
  if showProgress then
    buttonHeight = math.max(model.config.font_size, model.layout.textHeight - thickness - 1)
  end
  local button = ui.button({
    key = "track-text",
    text = model.visibleText,
    variant = "ghost",
    contentAlign = "start",
    fontSize = model.config.font_size,
    width = model.layout.textWidth,
    height = buttonHeight,
    tooltip = model.label,
    onClick = "onPrimaryClick",
    onHover = "onHover",
  })
  if not showProgress then
    return button
  end
  return ui.column({
    key = "text-stack",
    gap = 1,
    align = "start",
    height = model.layout.textHeight,
    onHover = "onHover",
  }, {
    button,
    ui.progress({
      key = "progress",
      progress = model.progress,
      fill = COLOR_PRIMARY,
      track = COLOR_PROGRESS_TRACK,
      width = model.layout.textWidth,
      height = thickness,
      radius = math.max(1, math.floor(thickness / 2)),
    }),
  })
end

local function controls(model)
  local nodes = {}
  local style = model.config.controls_style
  local showPrevious, showPlayPause, showNext
  if style == "all" then
    showPrevious, showPlayPause, showNext = true, true, true
  elseif style == "play_pause" then
    showPrevious, showPlayPause, showNext = false, true, false
  elseif style == "prev_next" then
    showPrevious, showPlayPause, showNext = true, false, true
  else
    return nodes
  end
  local size = model.layout.buttonSize
  local icon = math.min(model.layout.iconSize, size)
  if showPrevious then
    nodes[#nodes + 1] = ui.button({
      key = "previous",
      glyph = GLYPH_PREVIOUS,
      glyphSize = icon,
      width = size,
      height = size,
      variant = "ghost",
      tooltip = model.translate("tooltip.previous"),
      onClick = "onPrevious",
      onHover = "onHover",
    })
  end
  if showPlayPause then
    nodes[#nodes + 1] = ui.button({
      key = "play-pause",
      glyph = model.status == "Playing" and GLYPH_PAUSE or GLYPH_PLAY,
      glyphSize = icon,
      width = size,
      height = size,
      variant = "ghost",
      tooltip = model.translate(model.status == "Playing" and "tooltip.pause" or "tooltip.play"),
      onClick = "onToggle",
      onHover = "onHover",
    })
  end
  if showNext then
    nodes[#nodes + 1] = ui.button({
      key = "next",
      glyph = GLYPH_NEXT,
      glyphSize = icon,
      width = size,
      height = size,
      variant = "ghost",
      tooltip = model.translate("tooltip.next"),
      onClick = "onNext",
      onHover = "onHover",
    })
  end
  return nodes
end

local function spacer(model)
  return ui.box({
    key = "art-gap",
    width = model.vertical and 1 or model.layout.artGap,
    height = model.vertical and model.layout.artGap or 1,
    opacity = 0,
  })
end

local function root(model, nodes)
  local props = {
    key = "media-extra",
    gap = 0,
    align = "center",
    onHover = "onHover",
  }
  if model.vertical then
    return ui.column(props, nodes)
  end
  return ui.row(props, nodes)
end

function UI.build(model)
  if model.record == nil then
    local nodes = {}
    local idle = idleNode(model)
    if idle ~= nil then
      nodes[#nodes + 1] = idle
    end
    if #nodes == 0 then
      return nil
    end
    return root(model, nodes)
  end

  local nodes = {}
  local art = model.layout.showArt and artNode(model) or nil
  local label = model.layout.showText and textNode(model) or nil
  local controlNodes = model.layout.showControls and controls(model) or {}

  if art ~= nil then
    nodes[#nodes + 1] = art
  end
  if art ~= nil and (label ~= nil or #controlNodes > 0) and model.layout.artGap > 0 then
    nodes[#nodes + 1] = spacer(model)
  end
  if label ~= nil then
    nodes[#nodes + 1] = label
  end
  for _, node in ipairs(controlNodes) do
    nodes[#nodes + 1] = node
  end

  if #nodes == 0 then
    return nil
  end
  return root(model, nodes)
end

return UI
