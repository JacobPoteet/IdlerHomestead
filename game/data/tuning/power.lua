-- Power network (GDD §7.5). Per-object output, storage and draw live in data/content/objects.lua.
-- Sunrise and sunset per season live in tuning.time.daylight.
return {
  seasonalOutput = { -- season id -> solar output multiplier (low sun and snow on the panels in winter)
    spring = 1,
    summer = 1,
    autumn = 0.85,
    winter = 0.5,
  },
  curves = { -- source curve -> season id -> multiplier on the source's peak kW (solar uses seasonalOutput and the sun's arc)
    wind = { spring = 0.8, summer = 0.45, autumn = 0.8, winter = 1 }, -- windiest when the sun is weakest
    hydro = { spring = 1, summer = 0.5, autumn = 0.8, winter = 0.6 }, -- creek flow: spring melt high, summer low, winter under ice
  },
  wind = { -- the wind model behind turbines: a random target each in-game hour, eased toward
    floor = 0.2, -- share of a turbine's seasonal output you still get in a dead calm (0..1)
    start = 0.5, -- wind strength a new run begins with (0..1)
    easeHours = 2, -- in-game hours the wind takes to move to its next hourly target (smooths the gusts)
  },
  -- Priority tiers, first served first (D46). Real tiers are sink groups (a sink names its tier in
  -- content); the charge tiers fill batteries from spare generation. The player can reorder.
  defaultOrder = { "heating", "pumps", "freezer", "lights", "machines", "bank", "truck" }, -- tier ids in the order a new run serves them
  tierNames = { -- tier id -> label in the power panel
    heating = "Heating",
    pumps = "Pumps",
    freezer = "Freezer",
    lights = "Lights",
    machines = "Machines",
    bank = "Battery bank",
    truck = "Truck charging",
  },
  chargeTiers = { -- charge tier id -> true when it fills the vehicle battery (the truck), false for home batteries
    bank = false,
    truck = true,
  },
  truckReserveKwh = 24, -- kWh the truck keeps for a trip: it lends the homestead only charge above this (above economy.tripCost)
  refreshHours = 1 / 60, -- in-game hours of the step Power.refresh solves for (battery rate limits are scaled by it); a minute, close to one tick
  overdrawEpsilon = 0.0001, -- kW below which a shortfall counts as none (rounding)
  fullFraction = 0.99, -- battery charge fraction counted as full for the "power.full" event
  refullFraction = 0.9, -- battery charge fraction it must drop below before it can announce full again
}
