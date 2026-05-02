-- Pyanodon mod suite compatibility
-- Adjusts technology research to use py-science-pack-1, making Transport Drones
-- available earlier in the Py progression where vanilla science packs come late.

-- Only activate when py-science-pack-1 exists (indicates Py suite is loaded)
if not data.raw.tool["py-science-pack-1"] then return end

local function set_tech_unit(name, count, ingredients)
  local tech = data.raw.technology[name]
  if not tech then return end
  tech.unit = {
    count = count,
    ingredients = ingredients,
    time = 30,
  }
end

-- Tier 1: Core system - automation + py-science-pack-1
-- Available very early in Py, before vanilla green science
local tier1 = {
  {"automation-science-pack", 1},
  {"py-science-pack-1", 1},
}

set_tech_unit("transport-system",          100, tier1)
set_tech_unit("transport-drone-speed-1",   100, tier1)
set_tech_unit("transport-drone-capacity-1", 100, tier1)
set_tech_unit("transport-depot-circuits",  200, tier1)

-- Tier 2: Mid progression - automation + logistic + py-science-pack-1
-- Green science is a significant Py milestone; these techs unlock alongside it
local tier2 = {
  {"automation-science-pack", 1},
  {"logistic-science-pack", 1},
  {"py-science-pack-1", 1},
}

set_tech_unit("transport-fluids",          200, tier2)
set_tech_unit("transport-buffering",       200, tier2)
set_tech_unit("transport-logistics",       200, tier2)
set_tech_unit("fast-road",                 200, tier2)
set_tech_unit("transport-drone-speed-2",   200, tier2)
set_tech_unit("transport-drone-capacity-2", 200, tier2)

-- Tier 3+: left at vanilla requirements (Py players have those packs by then)
