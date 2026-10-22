-- Money, catalog, deliveries, truck trips (GDD §6).
return {
  deliveryFee = 3, -- $ per catalog order delivered to the drop-off
  deliveryHour = 7, -- in-game hour orders arrive (the day after ordering)
  tripCost = 20, -- kWh of truck charge one trip to town uses
  cargoCapacity = 40, -- units of goods the truck can sell per trip
  priceDriftMin = 0.8, -- weekly price multiplier range per good (min)
  priceDriftMax = 1.25, -- weekly price multiplier range per good (max)
  daysPerWeek = 7, -- in-game days between price changes and new specials
  specialsPerWeek = 2, -- catalog items on sale each week
  specialDiscount = 0.7, -- price multiplier for weekly specials
  saturation = { -- shared town demand for one good, the truck and the stand together (D196, PLAN_DEPTH 9.1)
    freeUnits = 12, -- units of one good the town takes at full price before the price starts to drop (a mixed load of 40 stays above it)
    step = 0.04, -- price multiplier lost per unit sold past freeUnits (4 percent a unit)
    minMult = 0.4, -- floor on the price multiplier; the town always pays at least this share of the price (no penalties)
    recoveryPerDay = 6, -- units of saturation the town forgets each morning (a good sold in a load is back at full price in a few days)
  },
  marketDay = { -- the last day of each season (D196, PLAN_DEPTH 9.4): the town is busier
    enabled = true, -- tuning switch: false turns market day off
    standTrafficMult = 2, -- multiplier on the stand's daily cap
    truckPriceMult = 1.25, -- multiplier on what the truck load sells for in town
  },
}
