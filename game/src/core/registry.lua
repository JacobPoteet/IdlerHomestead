-- Content registry: loads and validates definitions from data/content/<kind>.lua.
--
-- Each content file returns an array of definitions, each with a unique string `id`.
-- data/content/init.lua lists the kinds to load. data/schemas.lua describes each kind's
-- fields; definitions with missing, mistyped, or unknown fields fail at load time.
--
-- Schema field spec: "string" | "number" | "boolean" | "table", optionally suffixed with "?"
-- for optional fields (e.g. "number?").

local Registry = {}
Registry.__index = Registry

function Registry.new()
  return setmetatable({ kinds = {} }, Registry)
end

local function validate(kind, def, schema, index)
  local where = string.format("%s[%d] (%s)", kind, index, tostring(def.id))
  if type(def.id) ~= "string" or def.id == "" then
    error(where .. ": missing string 'id'", 0)
  end
  for field, spec in pairs(schema) do
    local expected, optional = spec:match("^(%a+)(%??)$")
    assert(expected, "Bad schema spec '" .. spec .. "' for " .. kind .. "." .. field)
    local value = def[field]
    if value == nil then
      if optional == "" then
        error(where .. ": missing required field '" .. field .. "'", 0)
      end
    elseif type(value) ~= expected then
      error(string.format("%s: field '%s' should be %s, got %s", where, field, expected, type(value)), 0)
    end
  end
  for field in pairs(def) do
    if field ~= "id" and schema[field] == nil then
      error(where .. ": unknown field '" .. tostring(field) .. "' (typo, or add it to the schema)", 0)
    end
  end
end

-- Reading a field that isn't in the schema errors (catches typos in system code);
-- optional schema fields that are absent read as nil. Adding new fields errors; existing
-- fields stay assignable so a future debug panel can tweak content values live.
local function guard(def, schema, path)
  setmetatable(def, {
    __index = function(_, key)
      if key ~= "id" and schema[key] == nil then
        error(string.format("'%s' is not a field of %s", tostring(key), path), 2)
      end
      return nil
    end,
    __newindex = function(_, key)
      error(string.format("Cannot add field '%s' to %s", tostring(key), path), 2)
    end,
  })
end

--- Register a list of definitions for a kind, validated against a schema.
function Registry:addKind(kind, defs, schema)
  assert(not self.kinds[kind], "Content kind '" .. kind .. "' already registered")
  assert(type(defs) == "table", "Content kind '" .. kind .. "' must be an array of definitions")
  assert(type(schema) == "table", "No schema for content kind '" .. kind .. "'")
  local entry = { list = {}, byId = {} }
  for i, def in ipairs(defs) do
    validate(kind, def, schema, i)
    if entry.byId[def.id] then
      error(string.format("%s: duplicate id '%s'", kind, def.id), 0)
    end
    guard(def, schema, kind .. "." .. def.id)
    entry.byId[def.id] = def
    entry.list[#entry.list + 1] = def
  end
  self.kinds[kind] = entry
end

--- Load every kind listed in data/content/init.lua using data/schemas.lua.
function Registry:loadAll()
  local schemas = require("data.schemas")
  for _, kind in ipairs(require("data.content.init")) do
    self:addKind(kind, require("data.content." .. kind), schemas[kind])
  end
  return self
end

local function entryFor(self, kind)
  local entry = self.kinds[kind]
  if not entry then
    error("Unknown content kind '" .. tostring(kind) .. "'", 3)
  end
  return entry
end

--- Get a definition; errors if it doesn't exist.
function Registry:get(kind, id)
  local def = entryFor(self, kind).byId[id]
  if not def then
    error(string.format("Unknown %s id '%s'", kind, tostring(id)), 2)
  end
  return def
end

function Registry:has(kind, id)
  local entry = self.kinds[kind]
  return entry ~= nil and entry.byId[id] ~= nil
end

--- All definitions of a kind, in file order. Do not modify the returned list.
function Registry:all(kind)
  return entryFor(self, kind).list
end

return Registry
