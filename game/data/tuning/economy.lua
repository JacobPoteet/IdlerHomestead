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
}
