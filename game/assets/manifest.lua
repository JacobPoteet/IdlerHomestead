-- Asset manifest (GDD §9.2): every sprite the game draws is looked up here by id, so swapping
-- placeholder art for real art never touches game code.
--
-- A sprite entry is either
--   { placeholder = "painterName", w, h }                 drawn procedurally at startup
--   { file = "assets/sprites/sheet.png", x, y, w, h }     a region of an image
-- Optional: variants = n  -> ids "name_1".."name_n" (for files: laid out left to right)
--
-- Anchoring: object sprites are drawn with their bottom-left at the bottom-left of the object's
-- footprint, so tall sprites (trees) extend upward. Actor sprites are drawn bottom-centre at the
-- actor's feet. See docs/ASSETS.md for the full art list.
return {
  sprites = {
    -- Terrain (16x16)
    grass = { placeholder = "grass", w = 16, h = 16, variants = 4 },
    road = { placeholder = "road", w = 16, h = 16, variants = 2 },
    tilled_dry = { placeholder = "tilled_dry", w = 16, h = 16 },
    tilled_wet = { placeholder = "tilled_wet", w = 16, h = 16 },
    ford_stones = { placeholder = "ford_stones", w = 16, h = 16 },
    plan_marker = { placeholder = "plan_marker", w = 16, h = 16 },

    -- Objects
    brush = { placeholder = "brush", w = 16, h = 16 },
    rock = { placeholder = "rock", w = 16, h = 16 },
    log = { placeholder = "log", w = 16, h = 16 },
    junk = { placeholder = "junk", w = 16, h = 16 },
    tree = { placeholder = "tree", w = 16, h = 32 },
    truck = { placeholder = "truck", w = 32, h = 24 },
    folding_panel = { placeholder = "folding_panel", w = 16, h = 16 },
    smoker = { placeholder = "smoker", w = 16, h = 24 },
    campfire = { placeholder = "campfire", w = 16, h = 16 },
    chopping_block = { placeholder = "chopping_block", w = 16, h = 16 },
    woodshed = { placeholder = "woodshed", w = 32, h = 24 },
    wood_stove = { placeholder = "wood_stove", w = 16, h = 24 },

    -- Power network (GDD §7.5)
    solar_array = { placeholder = "solar_array", w = 32, h = 16 },
    battery_bank = { placeholder = "battery_bank", w = 16, h = 16 },
    wind_turbine = { placeholder = "wind_turbine", w = 16, h = 32 },
    micro_hydro = { placeholder = "micro_hydro", w = 16, h = 16 },
    generator = { placeholder = "generator", w = 16, h = 16 },
    electric_heater = { placeholder = "electric_heater", w = 16, h = 16 },
    lamp = { placeholder = "lamp", w = 16, h = 16 },
    chest_freezer = { placeholder = "chest_freezer", w = 16, h = 16 },

    -- Crops: one sprite per growth stage (1 = sprout ... 3 = ready)
    radish = { placeholder = "radish", w = 16, h = 16, variants = 3 },
    potato = { placeholder = "potato", w = 16, h = 16, variants = 3 },

    -- Actors
    homesteader = { placeholder = "homesteader", w = 16, h = 20 },

    -- UI icons (12x12)
    icon_money = { placeholder = "icon_money", w = 12, h = 12 },
    icon_food = { placeholder = "icon_food", w = 12, h = 12 },
    icon_water = { placeholder = "icon_water", w = 12, h = 12 },
    icon_wood = { placeholder = "icon_wood", w = 12, h = 12 },
    icon_stone = { placeholder = "icon_stone", w = 12, h = 12 },
    icon_scrap = { placeholder = "icon_scrap", w = 12, h = 12 },
    icon_seed_radish = { placeholder = "icon_seed_radish", w = 12, h = 12 },
    icon_seed_potato = { placeholder = "icon_seed_potato", w = 12, h = 12 },
    icon_heart = { placeholder = "icon_heart", w = 12, h = 12 },
    icon_battery = { placeholder = "icon_battery", w = 12, h = 12 },
    icon_crate = { placeholder = "icon_crate", w = 12, h = 12 },
    icon_rod = { placeholder = "icon_rod", w = 12, h = 12 },
    icon_smoked_fish = { placeholder = "icon_smoked_fish", w = 12, h = 12 },
    icon_bait = { placeholder = "icon_bait", w = 12, h = 12 },
    icon_radish = { placeholder = "icon_seed_radish", w = 12, h = 12 },
    icon_potato = { placeholder = "icon_seed_potato", w = 12, h = 12 },
    icon_canned_food = { placeholder = "icon_food", w = 12, h = 12 },
    -- One icon per fish species (same painter, tinted per species)
    icon_creek_chub = { placeholder = "fish_icon", w = 12, h = 12 },
    icon_sunfish = { placeholder = "fish_icon", w = 12, h = 12 },
    icon_brook_trout = { placeholder = "fish_icon", w = 12, h = 12 },
    icon_smallmouth_bass = { placeholder = "fish_icon", w = 12, h = 12 },
    icon_channel_catfish = { placeholder = "fish_icon", w = 12, h = 12 },
    icon_rainbow_trout = { placeholder = "fish_icon", w = 12, h = 12 },
    icon_golden_trout = { placeholder = "fish_icon", w = 12, h = 12 },
    icon_unknown = { placeholder = "icon_unknown", w = 12, h = 12 },
    icon_note_blank = { placeholder = "icon_note_blank", w = 12, h = 12 },
    icon_spoiled = { placeholder = "fish_icon", w = 12, h = 12 },
    icon_firewood = { placeholder = "icon_firewood", w = 12, h = 12 },
    icon_seasoned_firewood = { placeholder = "icon_seasoned_firewood", w = 12, h = 12 },
    icon_cold = { placeholder = "icon_cold", w = 12, h = 12 },
    icon_axe = { placeholder = "icon_axe", w = 12, h = 12 },
    icon_campfire = { placeholder = "icon_campfire", w = 12, h = 12 },
    icon_woodshed = { placeholder = "icon_woodshed", w = 12, h = 12 },
    icon_wood_stove = { placeholder = "icon_wood_stove", w = 12, h = 12 },
    icon_smoker = { placeholder = "icon_smoker", w = 12, h = 12 },
    icon_folding_panel = { placeholder = "icon_folding_panel", w = 12, h = 12 },
    icon_solar_array = { placeholder = "icon_folding_panel", w = 12, h = 12 },
    icon_battery_bank = { placeholder = "icon_battery", w = 12, h = 12 },
    icon_wind_turbine = { placeholder = "icon_wind_turbine", w = 12, h = 12 },
    icon_micro_hydro = { placeholder = "icon_micro_hydro", w = 12, h = 12 },
    icon_generator = { placeholder = "icon_generator", w = 12, h = 12 },
    icon_electric_heater = { placeholder = "icon_electric_heater", w = 12, h = 12 },
    icon_lamp = { placeholder = "icon_lamp", w = 12, h = 12 },
    icon_chest_freezer = { placeholder = "icon_chest_freezer", w = 12, h = 12 },
    icon_fuel = { placeholder = "icon_fuel", w = 12, h = 12 },
    icon_fuel_can = { placeholder = "icon_fuel", w = 12, h = 12 },

    -- Fishing mini-game
    bobber = { placeholder = "bobber", w = 8, h = 10 },
  },
}
