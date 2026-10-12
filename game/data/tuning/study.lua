-- Field Journal study (GDD §8.1). Per-item study lengths live in data/content/catalog.lua.
return {
  queueSize = 3, -- ideas the study queue holds at once
  nightHours = 8, -- hours in bed that count as one "night" of study; long winter nights study faster
  finishSlack = 0.01, -- nights; a study this close to done finishes (absorbs tick rounding at waking)
}
