--!nonstrict

local Config = {}

export type Track = {
  busName: string,
  identity: string,
  desktopEntry: string,
  status: string,
  trackId: string,
  title: string,
  artists: {string},
  album: string,
  url: string,
  artUrl: string,
  positionMs: number,
  lengthMs: number,
  rate: number,
}

export type Config = {
  layout: string,
  show_artwork: boolean,
  show_text: boolean,
  show_controls: boolean,
  text_format: string,
  text_template: string,
  text_width: number,
  art_size: number,
  art_shape: string,
  art_gap: number,
  placeholder: string,
  placeholder_glyph: string,
  idle_mode: string,
  idle_glyph: string,
  text_scroll: string,
  scroll_speed: number,
  font_size: number,
  marquee_gap: number,
  progress_style: string,
  progress_thickness: number,
  controls_style: string,
  button_size: number,
  icon_size: number,
  vertical_text_width: number,
  hide_when_no_media: boolean,
  hide_when_idle: boolean,
}

export type Layout = {
  showArt: boolean,
  showText: boolean,
  showControls: boolean,
  artSize: number,
  artRadius: number,
  artGap: number,
  textWidth: number,
  textHeight: number,
  columns: number,
  buttonSize: number,
  iconSize: number,
  vertical: boolean,
}

export type ArtworkSource = {
  kind: string,
  path: string?,
  url: string?,
  extension: string,
}

local function textValue(key, fallback)
  local raw = noctalia.getConfig(key)
  if type(raw) == "string" then
    return raw
  end
  return fallback
end

local function flag(key, fallback)
  local raw = noctalia.getConfig(key)
  if type(raw) == "boolean" then
    return raw
  end
  return fallback
end

local function number(key, fallback, minimum, maximum)
  local raw = noctalia.getConfig(key)
  if type(raw) ~= "number" or raw ~= raw then
    return fallback
  end
  return math.max(minimum, math.min(maximum, raw))
end

local function read()
  return {
    layout = textValue("layout", "art_text_controls"),
    show_artwork = flag("show_artwork", true),
    show_text = flag("show_text", true),
    show_controls = flag("show_controls", true),
    text_format = textValue("text_format", "artist_title"),
    text_template = textValue("text_template", "{artist} - {title}"),
    text_width = number("text_width", 140, 100, 320),
    art_size = number("art_size", 20, 8, 28),
    art_shape = textValue("art_shape", "rounded"),
    art_gap = number("art_gap", 6, 0, 24),
    placeholder = textValue("placeholder", "none"),
    placeholder_glyph = textValue("placeholder_glyph", "music"),
    idle_mode = textValue("idle_mode", "app_icon"),
    idle_glyph = textValue("idle_glyph", "music"),
    text_scroll = textValue("text_scroll", "always"),
    scroll_speed = number("scroll_speed", 8, 1, 30),
    font_size = number("font_size", 13, 10, 20),
    marquee_gap = number("marquee_gap", 3, 1, 12),
    progress_style = textValue("progress_style", "none"),
    progress_thickness = number("progress_thickness", 2, 1, 4),
    controls_style = textValue("controls_style", "all"),
    button_size = number("button_size", 22, 16, 28),
    icon_size = number("icon_size", 16, 10, 20),
    vertical_text_width = number("vertical_text_width", 28, 16, 80),
    hide_when_no_media = flag("hide_when_no_media", false),
    hide_when_idle = flag("hide_when_idle", false),
  }
end

Config.read = read

return Config
