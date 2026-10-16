-- The homesteader's wardrobe (docs/PLAN_WARDROBE.md, D149 to D153). Garments are content
-- (data/content/garments.lua); the numbers that give a weight class its effect live here. The system is
-- src/sim/systems/wardrobe.lua. Clothes are small on purpose: the shelter is 40% and the camp 15% of the
-- night's heat, a full outfit is a few percent.
return {
  slots = { "head", "torso", "legs", "feet", "extra" }, -- slot ids in display and paint order
  slotWeight = { -- weight points a slot counts toward the outfit (the sum is 8)
    head = 1,
    torso = 3,
    legs = 2,
    feet = 1,
    extra = 1,
  },
  classes = { -- per weight point: `work` is added to the work-speed bonus, `cold` to the night's warmth need
    light = {
      work = 0.005, -- fraction per weight point: a full light outfit is +4% work speed by day
      cold = 0.0075, -- fraction per weight point: a full light outfit needs 6% more heat at night
    },
    mid = {
      work = 0, -- the baseline: no effect (an all-mid outfit multiplies by exactly 1)
      cold = 0,
    },
    heavy = {
      work = 0, -- heavy clothes give no work bonus and no penalty
      cold = -0.010, -- fraction per weight point: a full heavy outfit needs 8% less heat at night
    },
  },
  insulationFloor = 0.85, -- multiplier; clothes alone never cut the night's warmth need by more than 15%
  scale = { -- the largest magnitude any outfit reaches on an axis (the full half of the menu's meters); a test ties them to the numbers above
    work = 0.04, -- fraction: 8 weight points x classes.light.work
    cold = 0.08, -- fraction: the larger of 8 x light.cold (0.06) and 8 x -heavy.cold (0.08)
  },
  appliesNow = { -- when a Wear changes today's outfit at once instead of at the next dawn (between runs it always does)
    day = 1, -- game day of the run: only the first
    untilHour = 20, -- hour of that day (0..24): before the first evening
  },
  presets = { "warm", "cold" }, -- saved outfit names: the weather each is for
  autoColdNeed = 2, -- warmth (Weather.warmthNeed units; peak is needs.warmthPeak, 8) a coming night must need for the dawn auto-dress to wear the Cold preset: 25% of a full winter night, so autumn on is cold and the thaw and summer are warm
  unlocks = { -- threshold of each counting unlock, by garment id (a garment named here has a `%d` or a count in its hint)
    straw_hat = 2, -- kinds of crop harvested (the game has two crops today)
    tank_top = 3, -- summers lived through
    linen_shirt = 1, -- summers lived through
    denim_jacket = 5, -- trips to town
    wool_toque = 1, -- winters survived (lived through to the thaw), summed over the slot's runs
    wool_sweater = 2, -- winters survived
    wool_trousers = 3, -- winters survived
    down_parka = 4, -- winters survived
    trapper_hat = 1, -- cold snaps lived through to their last night
    snow_boots = 10, -- days spent in a frozen season (a winter is 7)
    scarf = 1, -- frosts: times the first freeze of a winter arrived
    shorts = 15, -- crops harvested (each harvest counts one)
    canvas_shoes = 5, -- fish species in the fish guide
    work_gloves = 3, -- machines standing at once at a dawn
    mittens = 30, -- trees felled
    oilskin_coat = 3, -- times rescued
    bandana = 1, -- times rescued
    felt_boots = 5, -- the run number reached
  },
}
