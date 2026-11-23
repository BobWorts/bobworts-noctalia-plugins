--!nonstrict
local Common = {}

local PREFIX = "[media-extra] "

function Common.log(scope, message)
  noctalia.log(PREFIX .. tostring(scope) .. ": " .. tostring(message))
end

local Cache = {}
Cache.__index = Cache

function Cache.new(maxEntries, ttlMs)
  local self = setmetatable({}, Cache)
  self.maxEntries = math.max(1, math.floor(maxEntries or 64))
  self.ttlMs = math.max(0, math.floor(ttlMs or 0))
  self.entries = {}
  self.order = {}
  return self
end

function Cache:touch(key)
  for index, current in ipairs(self.order) do
    if current == key then
      table.remove(self.order, index)
      break
    end
  end
  table.insert(self.order, 1, key)
end

function Cache:get(key)
  local entry = self.entries[key]
  if entry == nil then
    return nil
  end
  if self.ttlMs > 0 and entry.expiresAt <= noctalia.nowMs() then
    self:delete(key)
    return nil
  end
  self:touch(key)
  return entry.value
end

function Cache:set(key, value)
  local expiresAt = 0
  if self.ttlMs > 0 then
    expiresAt = noctalia.nowMs() + self.ttlMs
  end
  self.entries[key] = {
    value = value,
    expiresAt = expiresAt,
  }
  self:touch(key)
  while #self.order > self.maxEntries do
    local oldest = table.remove(self.order)
    self.entries[oldest] = nil
  end
end

function Cache:delete(key)
  self.entries[key] = nil
  for index, current in ipairs(self.order) do
    if current == key then
      table.remove(self.order, index)
      return
    end
  end
end

Common.Cache = Cache

return Common
