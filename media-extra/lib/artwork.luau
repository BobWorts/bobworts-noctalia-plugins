--!nonstrict

local Common = require("./common.luau")
local ConfigModule = require("./config.luau")

type ArtworkSource = ConfigModule.ArtworkSource

local Artwork = {}
Artwork.__index = Artwork

local ARTWORK_RETRY_MS = 60 * 1000
local MAX_ARTWORK_CACHE_ENTRIES = 128
local ARTWORK_CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000
local ARTWORK_MAX_AGE_SECONDS = 7 * 24 * 60 * 60
local ARTWORK_PREFIX = "art-"
local ARTWORK_DEFAULT_EXTENSION = "jpg"
local ARTWORK_SLOTS = 2
local ARTWORK_EXTENSIONS = {
  png = true,
  jpg = true,
  jpeg = true,
  webp = true,
  gif = true,
  avif = true,
}
local FILE_SCHEME_PREFIX = "file:"
local HTTP_PREFIX = "http://"
local HTTPS_PREFIX = "https://"
local HOME_PREFIX = "~/"

local counter = 0

local function invalidSource()
  return {
    kind = "invalid",
    path = nil,
    extension = ARTWORK_DEFAULT_EXTENSION,
  }
end

local function extensionOf(value)
  local path = value:gsub("[?#].*$", "")
  local extension = path:match("%.([%w]+)$")
  if extension == nil then
    return ARTWORK_DEFAULT_EXTENSION
  end
  extension = extension:lower()
  if ARTWORK_EXTENSIONS[extension] == true then
    return extension
  end
  return ARTWORK_DEFAULT_EXTENSION
end

local function localSource(path)
  if path == "" then
    return invalidSource()
  end
  return {
    kind = "local",
    path = path,
    extension = extensionOf(path),
  }
end

local function fileSource(text)
  local rest = text:sub(#FILE_SCHEME_PREFIX + 1)
  rest = rest:gsub("[?#].*$", "")
  local authority = ""
  local path
  if rest:sub(1, 2) == "//" then
    rest = rest:sub(3)
    if rest:sub(1, 1) == "/" then
      path = rest
    else
      local foundAuthority, foundPath = rest:match("^([^/]*)(/.*)$")
      if foundAuthority == nil or foundPath == nil then
        return invalidSource()
      end
      authority = foundAuthority
      path = foundPath
    end
  else
    if rest:sub(1, 1) ~= "/" then
      return invalidSource()
    end
    path = rest
  end
  if authority ~= "" and authority:lower() ~= "localhost" then
    return invalidSource()
  end
  return localSource(noctalia.string.urlDecode(path))
end

local function classify(value)
  if type(value) ~= "string" or value == "" then
    return invalidSource()
  end
  local text = value
  local lower = text:lower()

  if lower:sub(1, #FILE_SCHEME_PREFIX) == FILE_SCHEME_PREFIX then
    return fileSource(text)
  end

  if text:sub(1, 1) == "/" then
    return localSource(text)
  end

  if text:sub(1, #HOME_PREFIX) == HOME_PREFIX then
    return localSource(noctalia.expandPath(text))
  end

  if lower:sub(1, #HTTP_PREFIX) == HTTP_PREFIX
    or lower:sub(1, #HTTPS_PREFIX) == HTTPS_PREFIX then
    return {
      kind = "remote",
      path = text,
      extension = extensionOf(text),
    }
  end

  return invalidSource()
end

local function isUsable(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  local info = noctalia.fileInfo(path)
  if info == nil or info.isDir == true then
    return false
  end
  local size = tonumber(info.size)
  if size ~= nil and size <= 0 then
    return false
  end
  return true
end

local function retryExpired(failedAt, nowMs)
  return failedAt == nil or nowMs - failedAt >= ARTWORK_RETRY_MS
end

function Artwork.new(options)
  local source = options or {}
  counter = counter + 1
  local self = setmetatable({}, Artwork)
  self.dir = source.dir
  self.onReady = source.onReady or function() end
  self.tag = tostring(math.floor(noctalia.nowMs())) .. "-"
    .. tostring(counter) .. "-"
    .. tostring(math.random(100000, 999999))
  self.url = ""
  self.file = nil
  self.fileUrl = nil
  self.revision = 0
  self.slot = 0
  self.pending = false
  self.failed = {}
  self.cache = Common.Cache.new(MAX_ARTWORK_CACHE_ENTRIES, ARTWORK_CACHE_TTL_MS)
  return self
end

function Artwork:ready()
  self.onReady()
end

function Artwork:path()
  if self.file == nil then
    return nil
  end
  if isUsable(self.file) then
    return self.file
  end
  self.file = nil
  self.fileUrl = nil
  return nil
end

function Artwork:fail(url)
  self.failed[url] = noctalia.nowMs()
  self.pending = false
  self:ready()
end

function Artwork:set(value)
  local url = type(value) == "string" and value or ""
  if url == self.url then
    if self.pending then
      return
    end
    if self.file ~= nil and self.fileUrl == url then
      if isUsable(self.file) then
        return
      end
      self.file = nil
      self.fileUrl = nil
    end
    if url == "" then
      return
    end
    if not retryExpired(self.failed[url], noctalia.nowMs()) then
      return
    end
    self.failed[url] = nil
  else
    self.url = url
    self.revision = self.revision + 1
    self.pending = false
    if url == "" then
      self.file = nil
      self.fileUrl = nil
      self:ready()
      return
    end
    -- Keep the previous file on purpose. A new download must not flash an icon.
  end

  local source = classify(url)
  if source.kind == "invalid" then
    self:fail(url)
    return
  end

  if source.kind == "local" then
    local path = source.path
    if path ~= nil and isUsable(path) then
      self.file = path
      self.fileUrl = url
      self.pending = false
      self.failed[url] = nil
      self.cache:set(url, path)
    else
      self:fail(url)
      return
    end
    self:ready()
    return
  end

  local cached = self.cache:get(url)
  if cached ~= nil then
    if isUsable(cached) then
      self.file = cached
      self.fileUrl = url
      self.pending = false
      self.failed[url] = nil
      self:ready()
      return
    end
    self.cache:delete(url)
  end

  if self.dir == nil or self.dir == "" then
    self:fail(url)
    return
  end

  local nextSlot = (self.slot + 1) % ARTWORK_SLOTS
  local function destinationFor(slot)
    return self.dir .. "/" .. ARTWORK_PREFIX .. self.tag
      .. "-" .. tostring(slot) .. "." .. source.extension
  end
  local destination = destinationFor(nextSlot)
  if destination == self.file then
    nextSlot = (nextSlot + 1) % ARTWORK_SLOTS
    destination = destinationFor(nextSlot)
  end
  self.slot = nextSlot
  self.pending = true
  self.revision = self.revision + 1
  local revision = self.revision
  noctalia.removeFile(destination)

  local accepted = noctalia.download(url, destination, function(success)
    if revision ~= self.revision then
      return
    end
    self.pending = false
    if not success then
      self:fail(url)
      return
    end
    local info = noctalia.fileInfo(destination)
    if info == nil or info.isDir == true or (tonumber(info.size) or 0) <= 0 then
      Common.log("artwork.empty", url)
      self:fail(url)
      return
    end
    self.file = destination
    self.fileUrl = url
    self.failed[url] = nil
    self.cache:set(url, destination)
    self:ready()
  end)

  if not accepted then
    self:fail(url)
  end
end

function Artwork:cleanup()
  local nowMs = noctalia.nowMs()
  for url, failedAt in pairs(self.failed) do
    if nowMs - failedAt >= ARTWORK_RETRY_MS then
      self.failed[url] = nil
    end
  end
  if self.dir == nil or self.dir == "" then
    return
  end
  local entries = noctalia.listDir(self.dir)
  if entries == nil then
    return
  end
  local now = nowMs / 1000
  for _, name in ipairs(entries) do
    if name:sub(1, #ARTWORK_PREFIX) == ARTWORK_PREFIX then
      local path = self.dir .. "/" .. name
      local info = noctalia.fileInfo(path)
      if info ~= nil and info.mtime ~= nil
        and now - info.mtime > ARTWORK_MAX_AGE_SECONDS then
        noctalia.removeFile(path)
      end
    end
  end
end

function Artwork:dispose()
  self.revision = self.revision + 1
  self.pending = false
  self.file = nil
  self.fileUrl = nil
  if self.dir == nil or self.dir == "" then
    return
  end
  local entries = noctalia.listDir(self.dir)
  if entries == nil then
    return
  end
  local prefix = ARTWORK_PREFIX .. self.tag .. "-"
  for _, name in ipairs(entries) do
    if name:sub(1, #prefix) == prefix then
      noctalia.removeFile(self.dir .. "/" .. name)
    end
  end
end

return Artwork
