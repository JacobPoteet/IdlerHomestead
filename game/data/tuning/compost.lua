-- Compost and the manure loop (PLAN_DEPTH 8.4, D181, D185). Every number is a reasoned first guess for the M9 balance pass.
-- Hens and goats make muck in their house; the Tend chores rake it into the ledger as manure, a compost bin draws it
-- from the ledger on its own (no haul task), crop residue and spoiled food go into the bin too, the bin turns raw
-- material into compost over days, and a Fertilize task spreads compost on the worst worn field tile (Soil.add).
return {
  henMuck = 0.4, -- manure units one hen makes a game day (a flock of six: about two and a half)
  goatMuck = 1.5, -- manure units one goat makes a game day (three goats: about four and a half)
  muckCap = 12, -- units of muck a house holds before it makes no more (a flock that is never tended wastes it, never overflows)
  residuePerHarvest = 1, -- raw units a harvest adds to a bin on its own (stalks and trimmings; the bin with the most room takes them)
  spoilShare = 0.5, -- share of a spoiled food unit that reaches the bin as raw material (#169: spoilage is partly recovered, not wiped)
  startAt = 4, -- raw units in a bin that start a batch
  batchRaw = 12, -- most raw units one batch takes
  yield = 0.5, -- compost units made per raw unit (whole units: a batch of 12 makes 6)
  hours = 48, -- in-game hours a batch takes (two days)
  compostFertility = 0.3, -- 0..1 fertility one compost unit adds to the tile it is spread on (fast, but under a full recovery: two units rebuild a worn tile)
  fertilizeBelow = 0.55, -- fertility under which the idle routine spreads compost on a field tile (it takes the lowest-fertility one first)
  fertilizeMax = 0.95, -- fertility from which a player tap no longer spreads compost (a full tile gains nothing)
  fertilizeTime = 2.5, -- seconds of work to spread one unit of compost at 1x efficiency
}
