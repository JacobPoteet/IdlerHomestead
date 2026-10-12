-- Shader manager: loads shaders/<name>.glsl, reloads them live (F6), and sends uniforms safely.
-- See docs/ASSETS.md for the shader list and guidelines.
-- A shader that fails to compile logs the error and keeps the last good version (or none),
-- so a typo while iterating never crashes the game.

local Shaders = {}

local cache = {} -- name -> { shader = Shader|nil, error = string|nil }

local function compile(name)
  local path = "shaders/" .. name .. ".glsl"
  local ok, result = pcall(function()
    local code = assert(love.filesystem.read(path)) -- read() also returns a size; pass only the code
    return love.graphics.newShader(code)
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
