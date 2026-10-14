-- Day/night lighting from tuning.visuals.lightKeys (hour -> tint, light).

local Lighting = {}

local function lerp(a, b, t)
  return a + (b - a) * t
end

--- Map a real hour onto the hour the keyframes were authored for, so the authored dawn and dusk
--- land on today's sunrise and sunset (long winter nights, short summer ones).
function Lighting.remap(hour, sunrise, sunset, keySunrise, keySunset)
  if hour >= sunrise and hour <= sunset then
    return keySunrise + (hour - sunrise) * (keySunset - keySunrise) / (sunset - sunrise)
  end
  -- Night: sunset .. next sunrise maps onto keySunset .. keySunrise + 24.
  local since = hour >= sunset and hour - sunset or hour + 24 - sunset
  local mapped = keySunset + since * (keySunrise + 24 - keySunset) / (sunrise + 24 - sunset)
  return mapped >= 24 and mapped - 24 or mapped
end

--- Returns tint {r, g, b}, light level, and daylight 0..1 (night = 0, full day = 1).
function Lighting.at(hour, keys)
  local a, b = keys[1], keys[#keys]
  for i = 1, #keys - 1 do
    if hour >= keys[i].hour and hour <= keys[i + 1].hour then
      a, b = keys[i], keys[i + 1]
      break
    end
  end
  local span = b.hour - a.hour
  local t = span > 0 and (hour - a.hour) / span or 0
  local tint = { lerp(a.tint[1], b.tint[1], t), lerp(a.tint[2], b.tint[2], t), lerp(a.tint[3], b.tint[3], t) }
  local light = lerp(a.light, b.light, t)
  local minLight, maxLight = math.huge, -math.huge
  for _, k in ipairs(keys) do
    minLight, maxLight = math.min(minLight, k.light), math.max(maxLight, k.light)
  end
  local daylight = maxLight > minLight and (light - minLight) / (maxLight - minLight) or 1
  return tint, light, daylight
end

--- The sun's place for shadows: `side` runs -1 at sunrise to +1 at sunset (shadows fall away from it) and
--- `elevation` is 0 on the horizon to 1 at noon. Returns nil at night.
function Lighting.sun(hour, sunrise, sunset)
  if hour <= sunrise or hour >= sunset then
    return nil
  end
  local t = (hour - sunrise) / (sunset - sunrise)
  return (t - 0.5) * 2, math.sin(math.pi * t)
end

return Lighting
