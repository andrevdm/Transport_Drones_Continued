--Shared data interface between data and script, notably prototype names.

local data = {}

local quality_mod_active =
  (mods and mods["quality"])
  or (script and script.active_mods and script.active_mods["quality"])

data.drone_item_name = "transport-drone"
data.drone_stack_size = settings.startup["transport-drone-stack-size"] and settings.startup["transport-drone-stack-size"].value or 10
data.default_priority = 50
data.default_channel = -1
data.normal_quality = "normal"
data.quality_enabled = quality_mod_active ~= nil
data.quality_order_asc = data.quality_enabled and {"normal", "uncommon", "rare", "epic", "legendary"} or {"normal"}
data.quality_order_desc = data.quality_enabled and {"legendary", "epic", "rare", "uncommon", "normal"} or {"normal"}

data.drone_collision_mask = {"placeholder"}
data.variation_count = 50
data.special_variation_count = 10
data.transport_speed_technology = "transport-drone-speed"
data.transport_capacity_technology = "transport-drone-capacity"
data.transport_system_technology = "transport-system"
data.transport_logistics_technology = "transport-logistics"

data.quality_supply_inventory = {[0] = 80, [1] = 100, [2] = 125, [3] = 175, [5] = 250}
data.quality_drone_chest = {[0] = 5, [1] = 6, [2] = 7, [3] = 8, [5] = 10}

local quality_suffixes = {[0] = "", [1] = "-uncommon", [2] = "-rare", [3] = "-epic", [5] = "-legendary"}
data.quality_names = {"uncommon", "rare", "epic", "legendary"}

data.supply_key = function(item_name, quality)
  if not quality or quality == "normal" then return item_name end
  return item_name .. ":" .. quality
end
local function make_quality_names(base)
  local t = {}
  for level, suffix in pairs(quality_suffixes) do
    t[level] = base .. suffix
  end
  return t
end

data.drone_chest_name = make_quality_names("depot-drone-chest")
data.supply_chest_name = make_quality_names("supply-depot-chest")
data.supply_chest_name_logistic = make_quality_names("supply-depot-chest-logistic")
data.buffer_chest_name_logistic = make_quality_names("buffer-depot-chest-logistic")
data.active_chest_name = make_quality_names("active-depot-chest")
data.active_depot_fluid_name = "active-depot-fluid"
data.storage_chest_name = make_quality_names("storage-depot-chest")
data.storage_chest_name_logistic = make_quality_names("storage-depot-chest-logistic")
data.storage_depot_fluid_name = "storage-depot-fluid"
data.dispatcher_chest_name = make_quality_names("drone-dispatcher-chest")
data.quality_dispatcher_inventory = {[0] = 20, [1] = 24, [2] = 28, [3] = 32, [5] = 40}
data.quality_dispatcher_player_slots = {[0] = 10, [1] = 12, [2] = 14, [3] = 16, [5] = 20}

-- Multi-pipe variant name mappings (base <-> multi)
data.multi_pipe_variants = {
  ["fluid-depot"] = "fluid-depot-multi",
  ["request-depot"] = "request-depot-multi",
  ["buffer-depot"] = "buffer-depot-multi",
  ["fuel-depot"] = "fuel-depot-multi",
  [data.active_depot_fluid_name] = data.active_depot_fluid_name .. "-multi",
  [data.storage_depot_fluid_name] = data.storage_depot_fluid_name .. "-multi",
}
data.multi_pipe_base = {}
for base, multi in pairs(data.multi_pipe_variants) do
  data.multi_pipe_base[multi] = base
end

data.fuel_amount_per_drone = settings.startup["fuel-amount-per-drone"].value
data.fuel_consumption_per_meter = settings.startup["fuel-consumption-per-meter"].value
data.drone_fluid_capacity = settings.startup["drone-fluid-capacity"].value
data.drone_pollution_per_second = settings.startup["drone-pollution-per-second"].value
data.request_depot_fluid_capacity = settings.startup["request-depot-fluid-capacity"].value

return data
