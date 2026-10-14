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
    plan_marker = { placeholder = "plan_marker", w = 16, h = 16 }, -- dashed frame on a planned tile (D92 standing order, D102)
    cue_droplet = { placeholder = "cue_droplet", w = 7, h = 9 }, -- thirsty crop (D102)
    cue_ready = { placeholder = "cue_ready", w = 7, h = 7, variants = 2 }, -- ripe crop sparkle: 1 = small plus, 2 = star (D102)

    -- Objects
    brush = { placeholder = "brush", w = 16, h = 16 },
    rock = { placeholder = "rock", w = 16, h = 16 },
    log = { placeholder = "log", w = 16, h = 16 },
    junk = { placeholder = "junk", w = 16, h = 16 },
    tree = { placeholder = "tree", w = 16, h = 32 },
    truck = { placeholder = "truck", w = 32, h = 24 },
    trip_marker = { placeholder = "trip_marker", w = 11, h = 12 }, -- D101: arrow over the truck while a trip is ready
    folding_panel = { placeholder = "folding_panel", w = 16, h = 16 },
    smoker = { placeholder = "smoker", w = 16, h = 24 },
    campfire = { placeholder = "campfire", w = 16, h = 16 },
    woodshed = { placeholder = "woodshed", w = 32, h = 24 },
    wood_stove = { placeholder = "wood_stove", w = 16, h = 24 },
    camp = { placeholder = "camp", w = 32, h = 32 }, -- D82: 2x2 footprint
    shack = { placeholder = "shack", w = 48, h = 32 }, -- D82: 3x2 footprint

    -- Power network (GDD §7.5)
    solar_array = { placeholder = "solar_array", w = 32, h = 16 },
    battery_bank = { placeholder = "battery_bank", w = 16, h = 16 },
    wind_turbine = { placeholder = "wind_turbine", w = 16, h = 32 },
    micro_hydro = { placeholder = "micro_hydro", w = 16, h = 16 },
    generator = { placeholder = "generator", w = 16, h = 16 },
    electric_heater = { placeholder = "electric_heater", w = 16, h = 16 },
    lamp = { placeholder = "lamp", w = 16, h = 16 },
    chest_freezer = { placeholder = "chest_freezer", w = 16, h = 16 },

    -- Water ladder (GDD §5.3)
    well = { placeholder = "well", w = 16, h = 24 },
    hand_pump = { placeholder = "hand_pump", w = 16, h = 16 },
    cistern = { placeholder = "cistern", w = 32, h = 16 },
    dc_pump = { placeholder = "dc_pump", w = 16, h = 16 },
    drip_line = { placeholder = "drip_line", w = 16, h = 16 },
    roadside_stand = { placeholder = "roadside_stand", w = 32, h = 24 },
    chicken_coop = { placeholder = "chicken_coop", w = 32, h = 24 },
    goat_pen = { placeholder = "goat_pen", w = 32, h = 32 },
    cheese_press = { placeholder = "cheese_press", w = 16, h = 16 },
    auto_harvester = { placeholder = "auto_harvester", w = 16, h = 24 },

    -- Crops: one sprite per growth stage (1 = sprout ... 3 = ready)
    radish = { placeholder = "radish", w = 16, h = 16, variants = 3 },
    potato = { placeholder = "potato", w = 16, h = 16, variants = 3 },

    -- Actors
    homesteader = { placeholder = "homesteader", w = 16, h = 20 },
    cat = { placeholder = "cat", w = 14, h = 10 },
    cat_nap = { placeholder = "cat_nap", w = 14, h = 10 },
    hen = { placeholder = "hen", w = 10, h = 9 },
    goat = { placeholder = "goat", w = 14, h = 11 },

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
    icon_wx_clear = { placeholder = "icon_wx_clear", w = 12, h = 12 }, -- weather chip glyphs (D112)
    icon_wx_cloudy = { placeholder = "icon_wx_cloudy", w = 12, h = 12 },
    icon_wx_rain = { placeholder = "icon_wx_rain", w = 12, h = 12 },
    icon_wx_windy = { placeholder = "icon_wx_windy", w = 12, h = 12 },
    icon_wx_storm = { placeholder = "icon_wx_storm", w = 12, h = 12 },
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
    icon_cold = { placeholder = "icon_cold", w = 12, h = 12 },
    icon_axe = { placeholder = "icon_axe", w = 12, h = 12 },
    icon_campfire = { placeholder = "icon_campfire", w = 12, h = 12 },
    icon_woodshed = { placeholder = "icon_woodshed", w = 12, h = 12 },
    icon_camp = { placeholder = "icon_camp", w = 12, h = 12 },
    icon_shack = { placeholder = "icon_shack", w = 12, h = 12 },
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
    icon_well = { placeholder = "icon_well", w = 12, h = 12 },
    icon_hand_pump = { placeholder = "icon_hand_pump", w = 12, h = 12 },
    icon_cistern = { placeholder = "icon_cistern", w = 12, h = 12 },
    icon_dc_pump = { placeholder = "icon_dc_pump", w = 12, h = 12 },
    icon_drip_line = { placeholder = "icon_drip_line", w = 12, h = 12 },
    icon_cat = { placeholder = "icon_cat", w = 12, h = 12 },
    icon_shelter_cat = { placeholder = "icon_cat", w = 12, h = 12 },
    icon_roadside_stand ={ placeholder = "icon_roadside_stand", w = 12, h = 12 },
    icon_stand_sign = { placeholder = "icon_roadside_stand", w = 12, h = 12 },
    icon_stand_cooler = { placeholder = "icon_roadside_stand", w = 12, h = 12 },
    icon_stand_display = { placeholder = "icon_roadside_stand", w = 12, h = 12 },
    icon_hen = { placeholder = "icon_hen", w = 12, h = 12 },
    icon_egg = { placeholder = "icon_egg", w = 12, h = 12 },
    icon_chicken_coop = { placeholder = "icon_chicken_coop", w = 12, h = 12 },
    icon_chicken_feed = { placeholder = "icon_chicken_feed", w = 12, h = 12 },
    icon_chicken_fence = { placeholder = "icon_chicken_fence", w = 12, h = 12 },
    icon_goat = { placeholder = "icon_goat", w = 12, h = 12 },
    icon_milk = { placeholder = "icon_milk", w = 12, h = 12 },
    icon_hay = { placeholder = "icon_hay", w = 12, h = 12 },
    icon_cheese = { placeholder = "icon_cheese", w = 12, h = 12 },
    icon_goat_pen = { placeholder = "icon_goat_pen", w = 12, h = 12 },
    icon_goat_trailer = { placeholder = "icon_goat_trailer", w = 12, h = 12 },
    icon_cheese_press = { placeholder = "icon_cheese_press", w = 12, h = 12 },
    icon_auto_harvester = { placeholder = "icon_auto_harvester", w = 12, h = 12 },
    icon_fuel = { placeholder = "icon_fuel", w = 12, h = 12 },
    icon_fuel_can = { placeholder = "icon_fuel", w = 12, h = 12 },
    icon_hail = { placeholder = "icon_hail", w = 12, h = 12 },
    icon_drought = { placeholder = "icon_drought", w = 12, h = 12 },
    icon_locust = { placeholder = "icon_locust", w = 12, h = 12 },
    icon_frost = { placeholder = "icon_frost", w = 12, h = 12 },
    icon_hail_netting = { placeholder = "icon_hail_netting", w = 12, h = 12 },
    icon_straw_mulch = { placeholder = "icon_straw_mulch", w = 12, h = 12 },
    icon_row_covers = { placeholder = "icon_row_covers", w = 12, h = 12 },
    icon_frost_cloth = { placeholder = "icon_frost_cloth", w = 12, h = 12 },

    -- Fishing mini-game
    bobber = { placeholder = "bobber", w = 8, h = 10 },
  },
}
