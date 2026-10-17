-- Plain words for the bedtime notice and the morning report (D70, #159). The numbers come from the
-- Nightly report and the Needs accessors; the damage per shortfall comes from tuning, not from here.

local Journal = require("src.sim.systems.journal")
local Needs = require("src.sim.systems.needs")
local Nightly = require("src.sim.systems.nightly")
local SpoilText = require("src.ui.spoil_text")
local theme = require("src.ui.theme")

local NightText = {}

local function plural(n, word)
  return n == 1 and (n .. " " .. word) or (n .. " " .. word .. "s")
end

--- "3 Canned food, 2 Radish" from { [resource id] = amount }, ids sorted so the line is stable.
local function counts(world, map)
  local ids = {}
  for id in pairs(map) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  local parts = {}
  for _, id in ipairs(ids) do
    parts[#parts + 1] = string.format("%d %s", map[id], world.registry:get("resources", id).name:lower())
  end
  return table.concat(parts, ", ")
end

--- The toast at bedtime: what is being studied tonight.
function NightText.bedtime(world)
  local study = Nightly.bedtime(world)
  if not study then
    return "Bedtime. Nothing queued to study: pick an idea in the Journal"
  end
  local night = math.min(study.total, math.floor(study.nights) + 1)
  return string.format("Bedtime. Studying: %s, night %d of %d", study.name, night, study.total)
end

--- The morning report as lines of { text, color } (color nil = normal), and whether any line is
--- about spoilage (the card then offers the Pantry).
function NightText.morning(world, report)
  local needs = world.tuning.needs
  local lines, spoil = {}, false
  local function add(text, color)
    lines[#lines + 1] = { text = text, color = color }
  end

  add(string.format("Slept %s.", plural(math.max(1, math.floor(report.hours + 0.5)), "hour")))

  local study = report.study
  if study and study.learned then
    local where = Journal.kindOf(world, study.id) == "perks" and "from your next run" or "now in the Catalog"
    add(string.format("Finished studying %s: %s.", study.name, where), theme.colors.accent)
  elseif study then
    add(string.format("Studied %s: %.1f of %d nights.", study.name, study.to, study.total))
  else
    add("Nothing was queued to study.", theme.colors.textDim)
  end

  if report.calories > 0 then
    add(
      string.format(
        "Ate %d calories (%s). Food left: %.1f days.",
        report.calories,
        counts(world, report.ate),
        Needs.foodDays(world)
      )
    )
  end
  if report.hungry > 0 then
    add(
      string.format("Went hungry: -%d condition.", math.floor(report.hungry * needs.hungerDamage + 0.5)),
      theme.colors.danger
    )
  end

  if (report.thirsty or 0) > 0 then
    add(string.format("Went thirsty: -%d condition.", math.floor(report.thirstLost + 0.5)), theme.colors.danger)
  end

  local burned = counts(world, report.burned)
  if burned ~= "" then
    local text = "Burned " .. burned .. " for warmth"
    if report.electric > 0 then
      text = text .. " (plus electric heat)"
    end
    add(text .. ".")
  elseif report.electric > 0 then
    add("Electric heat kept the cold out.")
  end
  if report.cold > 0 then
    add(
      string.format("Too cold: -%d condition.", math.floor(report.cold * needs.coldDamage + 0.5)),
      theme.colors.danger
    )
  end

  if report.spoil then
    spoil = true
    add("Spoiled: " .. SpoilText.items(world, report.spoil.lost) .. ".", theme.colors.danger)
  end
  local raided = counts(world, report.raided)
  if raided ~= "" then
    add("Mice took " .. raided .. ".", theme.colors.danger)
  elseif report.caught > 0 then
    add("The cat caught a mouse in the night.")
  end
  if report.killed > 0 then
    add(string.format("A fox took %s.", plural(report.killed, "hen")), theme.colors.danger)
  end
  if (report.killedGoats or 0) > 0 then
    add(string.format("A coyote took %s.", plural(report.killedGoats, "goat")), theme.colors.danger)
  end
  if report.killed == 0 and (report.killedGoats or 0) == 0 and report.stopped > 0 then
    add("A fox tried the animals in the night. The fence held.")
  end

  local from, to = math.floor(report.conditionFrom + 0.5), math.floor(report.conditionTo + 0.5)
  if from ~= to then
    add(string.format("Condition %d to %d.", from, to), to < from and theme.colors.danger or nil)
  end
  return lines, spoil
end

return NightText
