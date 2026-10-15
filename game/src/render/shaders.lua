-- Shader manager: loads shaders/<name>.glsl, reloads them live (F6), and sends uniforms safely.
-- See docs/ASSETS.md for the shader list and guidelines.
-- A shader that fails to compile logs the error and keeps the last good version (or none),
-- so a typo while iterating never crashes the game.

local Shaders = {}

local cache = {} -- name -> { shader = Shader|nil, error = string|nil }

--- The source of shaders/<name>.glsl with each `#include "x"` line replaced by shaders/include/x.glsl
--- (one level deep; LÖVE's GLSL has no include of its own). Include files go after the uniforms, where
--- the shader writes the line, and before `effect`.
local function source(name)
  local code = assert(love.filesystem.read("shaders/" .. name .. ".glsl")) -- read() also returns a size
  return (
    code:gsub('#include%s+"([%w_]+)"', function(inc)
      return assert(love.filesystem.read("shaders/include/" .. inc .. ".glsl"))
    end)
  )
end

local function compile(name)
  local ok, result = pcall(function()
    return love.graphics.newShader(source(name))
  end)
  if ok then
    return result, nil
  end
  print("Shader '" .. name .. "' failed to compile:\n" .. tostring(result))
  return nil, tostring(result)
end

--- The compiled shader, or nil if it has never compiled.
function Shaders.get(name)
  local entry = cache[name]
  if not entry then
    local shader, err = compile(name)
    entry = { shader = shader, error = err }
    cache[name] = entry
  end
  return entry.shader
end

--- Recompile every loaded shader from disk, keeping the old one on failure.
function Shaders.reloadAll()
  for name, entry in pairs(cache) do
    local shader, err = compile(name)
    if shader then
      entry.shader = shader
    end
    entry.error = err
  end
end

--- Last compile error per shader name (for the debug overlay).
function Shaders.errors()
  local out = {}
  for name, entry in pairs(cache) do
    if entry.error then
      out[name] = entry.error
    end
  end
  return out
end

--- Send uniforms that the shader actually uses (GLSL drops unused ones, and sending those errors).
function Shaders.send(shader, values)
  for key, value in pairs(values) do
    if shader:hasUniform(key) then
      shader:send(key, value)
    end
  end
end

return Shaders
