--!nonstrict

local Text = {}

local ELLIPSIS = "…"
local MIN_TEXT_COLUMNS = 2
local FONT_WIDTH_RATIO = 0.62

Text.LAYOUTS = {
  artist_title = "{artist} - {title}",
  title_artist = "{title} - {artist}",
  title = "{title}",
  artist = "{artist}",
  album_title = "{album} - {title}",
}

local function clean(value)
  if type(value) ~= "string" then
    return ""
  end
  return noctalia.string.trim(value)
end

local function formatDuration(milliseconds)
  local total = math.max(0, math.floor((milliseconds or 0) / 1000))
  local hours = math.floor(total / 3600)
  local minutes = math.floor((total % 3600) / 60)
  local seconds = total % 60
  if hours > 0 then
    return string.format("%d:%02d:%02d", hours, minutes, seconds)
  end
  return string.format("%d:%02d", minutes, seconds)
end

local function substitute(template, values)
  local result = template
  for token, value in pairs(values) do
    result = result:gsub("{" .. token .. "}", function()
      return value
    end)
  end
  result = result:gsub("%s+", " ")
  return noctalia.string.trim(result)
end

function Text.compose(record, settings)
  if type(record) ~= "table" then
    return ""
  end
  local format = settings.text_format
  local template = Text.LAYOUTS[format]
  if template == nil and format == "custom" then
    template = settings.text_template
  end
  if template == nil or template == "" then
    template = Text.LAYOUTS.artist_title
  end
  local artists = record.artists
  if type(artists) ~= "table" then
    artists = {}
  end
  local values = {
    title = clean(record.title),
    artist = clean(artists[1]),
    artists = clean(table.concat(artists, ", ")),
    album = clean(record.album),
    player = clean(record.identity),
    position = formatDuration(record.positionMs or 0),
    length = formatDuration(record.lengthMs or 0),
  }
  return substitute(template, values)
end

local function charWidth(code)
  if code == 0 then
    return 0
  end
  if code < 32 or (code >= 0x7F and code < 0xA0) then
    return 0
  end
  if code >= 0x1100 and (
    code <= 0x115F
    or code == 0x2329
    or code == 0x232A
    or (code >= 0x2E80 and code <= 0xA4CF and code ~= 0x303F)
    or (code >= 0xAC00 and code <= 0xD7A3)
    or (code >= 0xF900 and code <= 0xFAFF)
    or (code >= 0xFE10 and code <= 0xFE19)
    or (code >= 0xFE30 and code <= 0xFE6F)
    or (code >= 0xFF00 and code <= 0xFF60)
    or (code >= 0xFFE0 and code <= 0xFFE6)
    or (code >= 0x1F1E6 and code <= 0x1F1FF)
    or (code >= 0x1F300 and code <= 0x1F64F)
    or (code >= 0x1F680 and code <= 0x1F6FF)
    or (code >= 0x1F900 and code <= 0x1F9FF)
    or (code >= 0x20000 and code <= 0x3FFFD)
  ) then
    return 2
  end
  return 1
end

local function toCells(text)
  if type(text) ~= "string" or text == "" then
    return {}
  end
  local cells = {}
  local source = text :: string
  local ok = pcall(function()
    for _, code in utf8.codes(source) do
      cells[#cells + 1] = {
        char = utf8.char(code),
        width = charWidth(code),
      }
    end
  end)
  if ok then
    return cells
  end
  cells = {}
  for index = 1, #source do
    cells[#cells + 1] = {
      char = source:sub(index, index),
      width = 1,
    }
  end
  return cells
end

local function widthOf(cells)
  local total = 0
  for _, cell in ipairs(cells) do
    total = total + cell.width
  end
  return total
end

function Text.truncate(text, columns)
  if type(text) ~= "string" or text == "" then
    return ""
  end
  local limit = math.max(0, math.floor(columns or 0))
  if limit < MIN_TEXT_COLUMNS then
    return ""
  end
  local cells = toCells(text)
  if widthOf(cells) <= limit then
    return text
  end
  local result = {}
  local used = 0
  for _, cell in ipairs(cells) do
    if used + cell.width > limit - 1 then
      break
    end
    result[#result + 1] = cell.char
    used = used + cell.width
  end
  result[#result + 1] = ELLIPSIS
  return table.concat(result)
end

function Text.columnsForWidth(width, fontSize)
  local size = math.max(1, fontSize or 13)
  return math.max(MIN_TEXT_COLUMNS, math.floor((width or 0) / (size * FONT_WIDTH_RATIO)))
end

local Marquee = {}
Marquee.__index = Marquee

function Marquee.new(options)
  local self = setmetatable({}, Marquee)
  local source = options or {}
  self.columns = math.max(MIN_TEXT_COLUMNS, math.floor(source.columns or 16))
  self.gap = math.max(1, math.floor(source.gap or 3))
  self.speed = math.max(1, source.speed or 8)
  self.source = ""
  self.key = nil
  self.cells = {}
  self.offset = 0
  self.accumulator = 0
  return self
end

function Marquee:configure(columns, gap, speed)
  self.columns = math.max(MIN_TEXT_COLUMNS, math.floor(columns or self.columns))
  self.gap = math.max(1, math.floor(gap or self.gap))
  self.speed = math.max(1, speed or self.speed)
end

function Marquee:reset()
  self.offset = 0
  self.accumulator = 0
end

function Marquee:setText(text, key)
  self.source = text or ""
  self.key = key
  self.cells = toCells(self.source)
  self:reset()
end

function Marquee:replace(text, key)
  if text == self.source then
    return
  end
  if key ~= nil and key == self.key then
    self.source = text
    self.cells = toCells(text)
    return
  end
  self.key = key
  self:setText(text, key)
end

function Marquee:advance(deltaMs)
  if #self.cells == 0 then
    return false
  end
  local before = self.offset
  self.accumulator = self.accumulator + math.max(0, deltaMs or 0)
  local step = 1000 / self.speed
  while self.accumulator >= step do
    self.accumulator = self.accumulator - step
    self.offset = self.offset + 1
  end
  local cycle = widthOf(self.cells) + self.gap
  if cycle > 0 then
    self.offset = self.offset % cycle
  end
  return self.offset ~= before
end

function Marquee:window()
  if #self.cells == 0 then
    return ""
  end
  local total = widthOf(self.cells)
  if total <= self.columns then
    return self.source
  end
  local cycle = total + self.gap
  local offset = self.offset % cycle
  local parts = {}
  local used = 0
  local index = 1
  local skipped = 0
  while index <= #self.cells and skipped < offset do
    skipped = skipped + self.cells[index].width
    index = index + 1
  end
  while used < self.columns do
    if index > #self.cells then
      local gap = math.min(self.gap, self.columns - used)
      if gap <= 0 then
        break
      end
      parts[#parts + 1] = string.rep(" ", gap)
      used = used + gap
      index = 1
    else
      local cell = self.cells[index]
      if used + cell.width > self.columns then
        break
      end
      parts[#parts + 1] = cell.char
      used = used + cell.width
      index = index + 1
    end
  end
  return table.concat(parts)
end

Text.newMarquee = function(options)
  return Marquee.new(options)
end

return Text
