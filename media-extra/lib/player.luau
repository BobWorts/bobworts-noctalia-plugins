--!nonstrict

local Common = require("./common.luau")
local ConfigModule = require("./config.luau")

type Track = ConfigModule.Track

local Player = {}

local MAX_ARTISTS = 8
local MAX_ICON_CACHE_ENTRIES = 64
local ICON_CACHE_TTL_MS = 5 * 60 * 1000
local MAX_TRACK_MS = 7 * 24 * 60 * 60 * 1000
local MAX_RATE = 16
local DEFAULT_ICON = "music"
local DESKTOP_SUFFIX = ".desktop"

local COMMAND_NOCTALIA = "noctalia"
local COMMAND_BUSCTL = "busctl"
local COMMAND_GDBUS = "gdbus"
local COMMAND_GTK_LAUNCH = "gtk-launch"
local COMMAND_GIO = "gio"
local MEDIA_MESSAGE = "msg"
local MEDIA_NAMESPACE = "media"

local MPRIS_OBJECT_PATH = "/org/mpris/MediaPlayer2"
local MPRIS_INTERFACE = "org.mpris.MediaPlayer2"
local MPRIS_RAISE_METHOD = "org.mpris.MediaPlayer2.Raise"

local XDG_DEFAULT_DATA_HOME = "~/.local/share"
local XDG_DEFAULT_DATA_DIRS = "/usr/local/share:/usr/share"
local APPLICATIONS_DIR = "applications"
local FLATPAK_DEFAULT_USER_DIR = "~/.local/share/flatpak"
local FLATPAK_DEFAULT_SYSTEM_DIR = "/var/lib/flatpak"
local FLATPAK_EXPORTS = "exports/share/applications"

local VALID_STATUS = {
  Playing = true,
  Paused = true,
  Stopped = true,
}

local iconCache = Common.Cache.new(MAX_ICON_CACHE_ENTRIES, ICON_CACHE_TTL_MS)

local function failed(result)
  if result == nil or type(result) ~= "table" then
    return true
  end
  local code = result.exitCode
  return code ~= nil and code ~= 0
end

local function notifyFailure(translate, titleKey, bodyKey, variables)
  local title = variables and translate(titleKey, variables) or translate(titleKey)
  local body = variables and translate(bodyKey, variables) or translate(bodyKey)
  noctalia.notifyError(title, body)
end

local function finiteNumber(value, fallback)
  local numberValue = tonumber(value)
  if numberValue == nil or numberValue ~= numberValue
    or numberValue == math.huge or numberValue == -math.huge then
    return fallback
  end
  return numberValue
end

local function clamp(value, minimum, maximum)
  local numberValue = finiteNumber(value, minimum)
  if numberValue < minimum then
    return minimum
  end
  if numberValue > maximum then
    return maximum
  end
  return numberValue
end

local function clean(value)
  local text
  if type(value) == "string" then
    text = value
  elseif type(value) == "number" then
    text = tostring(value)
  else
    return ""
  end
  text = string.gsub(text, "[\r\n\t]+", " ")
  text = string.gsub(text, "%s+", " ")
  return noctalia.string.trim(text)
end

local function normalizeArtists(value)
  local artists = {}
  local function add(item)
    local name = clean(item)
    if name == "" or #artists >= MAX_ARTISTS then
      return
    end
    artists[#artists + 1] = name
  end
  if type(value) == "table" then
    for _, item in ipairs(value) do
      add(item)
    end
    return artists
  end
  if type(value) == "string" then
    for item in value:gmatch("[^;]+") do
      add(item)
    end
  end
  return artists
end

local function normalize(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local status = "Stopped"
  local rawStatus = raw.status
  if type(rawStatus) == "string" and VALID_STATUS[rawStatus] then
    status = rawStatus
  end
  local rate = finiteNumber(raw.rate, 1)
  if rate < 0 then
    rate = 0
  end
  if rate > MAX_RATE then
    rate = MAX_RATE
  end
  local record = {
    busName = clean(raw.busName),
    identity = clean(raw.identity),
    desktopEntry = clean(raw.desktopEntry or raw.desktop_entry),
    status = status,
    trackId = clean(raw.trackId or raw.track_id),
    title = clean(raw.title),
    artists = normalizeArtists(raw.artists),
    album = clean(raw.album),
    artUrl = clean(raw.artUrl or raw.art_url),
    positionMs = clamp(raw.positionMs or raw.position_ms, 0, MAX_TRACK_MS),
    lengthMs = clamp(raw.lengthMs or raw.length_ms, 0, MAX_TRACK_MS),
    rate = rate,
  }
  local hasContent = record.trackId ~= ""
    or record.title ~= ""
    or record.album ~= ""
    or record.artUrl ~= ""
    or #record.artists > 0
  if not hasContent then
    return nil
  end
  return record
end

function Player.available()
  return noctalia.commandExists(COMMAND_NOCTALIA)
end

function Player.snapshot()
  local record = normalize(noctalia.mediaPlayer())
  return record, true
end

function Player.progress(record)
  if record == nil or (record.lengthMs or 0) <= 0 then
    return 0
  end
  local position = clamp(record.positionMs, 0, record.lengthMs)
  return position / record.lengthMs
end

local function splitList(value, separator)
  local parts = {}
  for part in value:gmatch("([^" .. separator .. "]+)") do
    if part ~= "" then
      parts[#parts + 1] = part
    end
  end
  return parts
end

local function dataHome()
  local configured = noctalia.getenv("XDG_DATA_HOME")
  if configured ~= nil then
    return noctalia.expandPath(configured)
  end
  return noctalia.expandPath(XDG_DEFAULT_DATA_HOME)
end

local function dataDirs()
  local configured = noctalia.getenv("XDG_DATA_DIRS")
  local value = configured or XDG_DEFAULT_DATA_DIRS
  local parts = splitList(value, ":")
  local directories = {}
  for _, part in ipairs(parts) do
    directories[#directories + 1] = noctalia.expandPath(part)
  end
  return directories
end

local function validDesktopId(value)
  if value == "" or #value > 255 then
    return false
  end
  if value:sub(1, 1) == "-" then
    return false
  end
  if value:find("/", 1, true) ~= nil then
    return false
  end
  if value:find("\\", 1, true) ~= nil then
    return false
  end
  if value:find("..", 1, true) ~= nil then
    return false
  end
  if value:find("%c") ~= nil then
    return false
  end
  return true
end

local function flatpakDirs()
  local userDir = noctalia.getenv("FLATPAK_USER_DIR") or FLATPAK_DEFAULT_USER_DIR
  local systemDir = noctalia.getenv("FLATPAK_SYSTEM_DIR") or FLATPAK_DEFAULT_SYSTEM_DIR
  return {
    noctalia.expandPath(userDir) .. "/" .. FLATPAK_EXPORTS,
    noctalia.expandPath(systemDir) .. "/" .. FLATPAK_EXPORTS,
  }
end

local function desktopId(entry)
  if type(entry) ~= "string" then
    return ""
  end
  local value = entry
  if value:sub(-#DESKTOP_SUFFIX):lower() == DESKTOP_SUFFIX then
    value = value:sub(1, -#DESKTOP_SUFFIX - 1)
  end
  if not validDesktopId(value) then
    return ""
  end
  return value
end

local function applicationDirs()
  local directories = {}
  local seen = {}
  local function add(path)
    if path == "" or seen[path] then
      return
    end
    seen[path] = true
    directories[#directories + 1] = path
  end
  add(dataHome() .. "/" .. APPLICATIONS_DIR)
  for _, directory in ipairs(dataDirs()) do
    add(directory .. "/" .. APPLICATIONS_DIR)
  end
  for _, directory in ipairs(flatpakDirs()) do
    add(directory)
  end
  return directories
end

local function desktopFile(entry)
  local id = desktopId(entry)
  if id == "" then
    return nil
  end
  for _, directory in ipairs(applicationDirs()) do
    local path = directory .. "/" .. id .. DESKTOP_SUFFIX
    if noctalia.fileExists(path) then
      return path
    end
  end
  return nil
end

local function busSuffix(busName)
  if busName == nil or busName == "" then
    return ""
  end
  return busName:match("MediaPlayer2%.(.+)$") or busName:match("%.([^%.]+)$") or ""
end

local function iconKey(record)
  local key = clean(record.desktopEntry)
  if key:sub(-#DESKTOP_SUFFIX):lower() == DESKTOP_SUFFIX then
    key = key:sub(1, -#DESKTOP_SUFFIX - 1)
  end
  if key == "" then
    key = clean(record.identity):lower():gsub("%s+", "")
  end
  if key == "" then
    key = busSuffix(record.busName)
  end
  if key == "" then
    key = DEFAULT_ICON
  end
  return key
end

function Player.iconPath(record, size)
  if record == nil then
    return nil
  end
  local name = iconKey(record)
  local key = name .. "@" .. tostring(size)
  local cached = iconCache:get(key)
  if cached ~= nil then
    if cached == false then
      return nil
    end
    if noctalia.fileExists(cached) then
      return cached
    end
    iconCache:delete(key)
  end
  local path = noctalia.appIconPath(name, size)
  if path ~= nil and noctalia.fileExists(path) then
    iconCache:set(key, path)
    return path
  end
  iconCache:set(key, false)
  return nil
end

function Player.send(name, onFailure)
  if not noctalia.commandExists(COMMAND_NOCTALIA) then
    return false
  end
  return noctalia.runAsync({
    COMMAND_NOCTALIA,
    MEDIA_MESSAGE,
    MEDIA_NAMESPACE,
    name,
  }, function(result)
    if failed(result) then
      local code = type(result) == "table" and result.exitCode or "nil"
      Common.log("player.command." .. tostring(name), tostring(code))
      if onFailure ~= nil then
        onFailure(name)
      end
    end
  end)
end

local function launchWithGio(id, translate)
  if not noctalia.commandExists(COMMAND_GIO) then
    return false
  end
  local desktop = desktopFile(id)
  if desktop == nil then
    return false
  end
  return noctalia.runAsync({ COMMAND_GIO, "launch", desktop }, function(result)
    if failed(result) then
      Common.log("player.launch.gio", desktop)
      notifyFailure(translate, "notify.launch_failed.title", "notify.launch_failed.body", { player = id })
    end
  end)
end

local function launchDirect(entry, translate)
  local id = desktopId(entry)
  if id == "" then
    return false
  end
  if noctalia.commandExists(COMMAND_GTK_LAUNCH) then
    local accepted = noctalia.runAsync({ COMMAND_GTK_LAUNCH, id }, function(result)
      if failed(result) then
        Common.log("player.launch.gtk", id)
        if not launchWithGio(id, translate) then
          notifyFailure(translate, "notify.launch_failed.title", "notify.launch_failed.body", { player = id })
        end
      end
    end)
    if accepted then
      return true
    end
  end
  return launchWithGio(id, translate)
end

local function launch(record, translate)
  if record ~= nil then
    local entry = clean(record.desktopEntry)
    if entry == "" then
      entry = clean(record.identity):lower():gsub("%s+", "")
    end
    if entry ~= "" and launchDirect(entry, translate) then
      return true
    end
  end
  Common.log("player.launch", "no target")
  notifyFailure(translate, "notify.no_launch_target.title", "notify.no_launch_target.body", {
    player = record ~= nil and record.identity or "media player",
  })
  return false
end

local function raiseWithGdbus(bus, fallback)
  if not noctalia.commandExists(COMMAND_GDBUS) then
    fallback()
    return
  end
  local accepted = noctalia.runAsync({
    COMMAND_GDBUS, "call", "--session", "--dest", bus,
    "--object-path", MPRIS_OBJECT_PATH,
    "--method", MPRIS_RAISE_METHOD,
  }, function(result)
    if failed(result) then
      Common.log("player.raise.gdbus", bus)
      fallback()
    end
  end)
  if not accepted then
    fallback()
  end
end

local function raiseWindow(record, translate)
  local bus = record.busName
  if bus == "" then
    return false
  end
  local function fallback()
    launch(record, translate)
  end
  if noctalia.commandExists(COMMAND_BUSCTL) then
    local accepted = noctalia.runAsync({
      COMMAND_BUSCTL, "--user", "call", bus,
      MPRIS_OBJECT_PATH,
      MPRIS_INTERFACE,
      "Raise",
    }, function(result)
      if failed(result) then
        Common.log("player.raise.busctl", bus)
        raiseWithGdbus(bus, fallback)
      end
    end)
    if accepted then
      return true
    end
  end
  if noctalia.commandExists(COMMAND_GDBUS) then
    local accepted = noctalia.runAsync({
      COMMAND_GDBUS, "call", "--session", "--dest", bus,
      "--object-path", MPRIS_OBJECT_PATH,
      "--method", MPRIS_RAISE_METHOD,
    }, function(result)
      if failed(result) then
        Common.log("player.raise.gdbus", bus)
        fallback()
      end
    end)
    if accepted then
      return true
    end
  end
  return false
end

function Player.open(record, translate, canRaise)
  if record == nil then
    notifyFailure(translate, "notify.no_player.title", "notify.no_player.body")
    return
  end
  if canRaise ~= false and raiseWindow(record, translate) then
    return
  end
  launch(record, translate)
end

return Player
