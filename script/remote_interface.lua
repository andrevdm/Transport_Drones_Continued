local transport_drone = require("script/transport_drone")
local depot_common = require("script/depot_common")
local road_network = require("script/road_network")
local transport_technologies = require("script/transport_technologies")
local shared = require("shared")
local depot_base = require("script/depot_base")

local channels_match = depot_base.channels_match
local fuel_amount_per_drone = shared.fuel_amount_per_drone

local state_names =
{
  [1] = "going_to_supply",
  [2] = "return_to_requester",
  [4] = "delivering_fuel",
  [5] = "delivering_item",
  [6] = "delivering_drones",
  [7] = "returning_drones"
}

local mode_names =
{
  [1] = "item",
  [2] = "fluid"
}

-- Tier 1: Network queries

local get_network_ids = function()
  local ids = {}
  for id in pairs(road_network.get_networks()) do
    ids[#ids + 1] = id
  end
  return ids
end

local get_network_item_supply = function(network_id, item_name)
  local network = road_network.get_network_by_id(network_id)
  if not network then return 0 end
  local supply = network.item_supply[item_name]
  if not supply then return 0 end
  local total = 0
  for _, count in pairs(supply) do
    total = total + count
  end
  return total
end

local get_network_items = function(network_id)
  local network = road_network.get_network_by_id(network_id)
  if not network then return {} end
  local result = {}
  for name, depots in pairs(network.item_supply) do
    local total = 0
    for _, count in pairs(depots) do
      total = total + count
    end
    if total > 0 then
      result[name] = total
    end
  end
  return result
end

local get_network_details = function(network_id)
  local network = road_network.get_network_by_id(network_id)
  if not network then return nil end

  local depot_counts = {}
  local total = 0
  for category, depots in pairs(network.depots) do
    local count = 0
    for _ in pairs(depots) do
      count = count + 1
    end
    depot_counts[category] = count
    total = total + count
  end

  local item_types = 0
  for _, supply in pairs(network.item_supply) do
    local has_supply = false
    for _, count in pairs(supply) do
      if count > 0 then has_supply = true; break end
    end
    if has_supply then item_types = item_types + 1 end
  end

  return {
    depot_count = total,
    depot_counts = depot_counts,
    item_types = item_types,
  }
end

local get_supply_breakdown = function(network_id, item_name)
  local network = road_network.get_network_by_id(network_id)
  if not network then return {} end
  local supply = network.item_supply[item_name]
  if not supply then return {} end

  local result = {}
  for depot_index, count in pairs(supply) do
    local depot = depot_common.get_depot_by_index(depot_index)
    local entry = { available = count }
    if depot and depot.entity.valid then
      entry.position = { x = depot.entity.position.x, y = depot.entity.position.y }
      entry.entity_name = depot.entity.name
    end
    result[depot_index] = entry
  end
  return result
end

local get_node_network_id = function(surface_index, x, y)
  local node = road_network.get_node(surface_index, x, y)
  return node and node.id or 0
end

-- Tier 2: Depot queries

local get_all_depots = function()
  local indices = {}
  for index, depot in pairs(depot_common.get_all_depots()) do
    if depot.entity.valid then
      indices[#indices + 1] = index
    end
  end
  return indices
end

local get_depots_by_type = function(type_name)
  local indices = {}
  for index, depot in pairs(depot_common.get_all_depots()) do
    if depot.entity.valid and depot.entity.name == type_name then
      indices[#indices + 1] = index
    end
  end
  return indices
end

local get_depot_info = function(index)
  local depot = depot_common.get_depot_by_index(tostring(index))
  if not depot then return nil end
  if not depot.entity.valid then return nil end

  local info = {
    entity = depot.entity,
    type = depot.entity.name,
    network_id = depot.network_id,
    item = depot.item or nil,
    priority = depot.priority,
    base_priority = depot.base_priority,
    channel = depot.channel,
    base_channel = depot.base_channel,
  }

  -- Request/buffer/fuel depots (have drones)
  if depot.drones then
    info.active_drones = depot.get_active_drone_count and depot:get_active_drone_count() or 0
    info.drone_count = depot.get_drone_item_count and depot:get_drone_item_count() or 0
    info.current_amount = depot.get_current_amount and depot:get_current_amount() or 0
    info.fuel_amount = depot.get_fuel_amount and depot:get_fuel_amount() or 0
    info.fuel_on_the_way = depot.fuel_on_the_way or 0
    info.storage_limit = depot.storage_limit or nil
    info.ignore_capacity_bonus = depot.ignore_capacity_bonus or false
    info.full_stack_only = depot.full_stack_only or false
  end

  -- Supply/mining/fluid/buffer depots (have to_be_taken)
  if depot.to_be_taken and depot.get_available_item_count and depot.item then
    info.available_count = depot:get_available_item_count(depot.item)
  end

  -- Supply depots
  if depot.allow_bots ~= nil then
    info.allow_bots = depot.allow_bots
  end

  return info
end

local get_depot_internal = function(index)
  local depot = depot_common.get_depot_by_index(tostring(index))
  if not depot then return nil end
  if not depot.entity.valid then return nil end

  local info = {
    index = depot.index,
    type = depot.entity.name,
    bucket_index = depot.bucket_index,
    network_id = depot.network_id,
    node_position = depot.node_position,
    priority = depot.priority,
    base_priority = depot.base_priority,
    channel = depot.channel,
    base_channel = depot.base_channel,
    supply_threshold = depot.supply_threshold,
    circuit_threshold = depot.circuit_threshold,
    position = { x = depot.entity.position.x, y = depot.entity.position.y },
    has_circuit_writer = (depot.circuit_writer and depot.circuit_writer.valid) or false,
    has_circuit_reader = (depot.circuit_reader and depot.circuit_reader.valid) or false,
    priority_signal = depot.priority_signal,
  }

  -- Drone-bearing depots
  if depot.drones then
    info.drone_count = depot.get_drone_item_count and depot:get_drone_item_count() or 0
    info.active_drone_count = depot.get_active_drone_count and depot:get_active_drone_count() or 0
    info.fuel_amount = depot.get_fuel_amount and depot:get_fuel_amount() or 0
    info.fuel_on_the_way = depot.fuel_on_the_way or 0
    info.storage_limit = depot.storage_limit
    info.ignore_capacity_bonus = depot.ignore_capacity_bonus or false
    info.full_stack_only = depot.full_stack_only or false
    info.circuit_limit = depot.circuit_limit
    info.requested_drones = depot.requested_drones
    info.drones_on_the_way = depot.drones_on_the_way
    info.drones_returning = depot.drones_returning
    info.player_slots = depot.player_slots

    -- Central dispatch (dispatcher depots)
    if depot.central_dispatch_enabled ~= nil then
      info.central_dispatch_enabled = depot.central_dispatch_enabled
      info.central_dispatch_percent = depot.central_dispatch_percent
    end
  end

  -- Supplier depots
  if depot.to_be_taken then
    local tbt = {}
    for k, v in pairs(depot.to_be_taken) do
      tbt[k] = v
    end
    info.to_be_taken = tbt
  end

  if depot.allow_bots ~= nil then
    info.allow_bots = depot.allow_bots
  end

  -- Requester depots
  if depot.item ~= nil then
    info.item = depot.item or nil
  end
  if depot.mode then
    info.mode = mode_names[depot.mode]
  end

  return info
end

-- Backward-compatible wrapper
local get_depot_by_index = function(index)
  local depot = depot_common.get_depot_by_index(tostring(index))
  if not depot then return nil end
  return {
    entity_name = depot.entity.valid and depot.entity.name or nil,
    allow_bots = depot.allow_bots or false,
    priority = depot.priority,
    base_priority = depot.base_priority,
    channel = depot.channel,
    base_channel = depot.base_channel,
  }
end

-- Tier 3: Drone queries

local get_all_drones = function()
  local indices = {}
  for index, drone in pairs(transport_drone.get_all_drones()) do
    if drone.entity.valid then
      indices[#indices + 1] = index
    end
  end
  return indices
end

local get_drone_info = function(index)
  local drone = transport_drone.get_drone(tostring(index))
  if not drone then return nil end
  if not drone.entity.valid then return nil end

  return {
    entity = drone.entity,
    state = state_names[drone.state] or "unknown",
    held_item = drone.held_item or nil,
    held_count = drone.held_count or 0,
    quality = drone.quality or "normal",
    request_depot_index = drone.request_depot and drone.request_depot.index or nil,
    supply_depot_index = drone.supply_depot and drone.supply_depot.index or nil,
    requested_item = drone.requested_item or nil,
    requested_count = drone.requested_count or 0,
    fuel_amount = drone.fuel_amount or nil,
    target_depot_index = drone.target_depot and drone.target_depot.index or nil,
    failed_command_count = drone.failed_command_count or 0,
    tick_created = drone.tick_created or nil,
    position = { x = drone.entity.position.x, y = drone.entity.position.y },
  }
end

-- Tier 4: Write operations

local set_allow_bots = function(index, value)
  local depot = depot_common.get_depot_by_index(tostring(index))
  if depot and depot.set_allow_bots then
    depot:set_allow_bots(value)
    return true
  end
  return false
end

local set_depot_priority = function(index, value)
  local depot = depot_common.get_depot_by_index(tostring(index))
  if not depot then return false end
  value = math.max(0, math.min(100, math.floor(value)))
  depot.base_priority = value
  depot.priority = value
  depot:mark_bucket_dirty()
  return true
end

local set_storage_limit = function(index, value)
  local depot = depot_common.get_depot_by_index(tostring(index))
  if not depot or not depot.drones then return false end
  if value and value > 0 then
    depot.storage_limit = math.floor(value)
  else
    depot.storage_limit = nil
  end
  return true
end

local set_ignore_capacity_bonus = function(index, value)
  local depot = depot_common.get_depot_by_index(tostring(index))
  if not depot or not depot.drones then return false end
  depot.ignore_capacity_bonus = value or nil
  return true
end

local set_full_stack_only = function(index, value)
  local depot = depot_common.get_depot_by_index(tostring(index))
  if not depot or not depot.drones then return false end
  depot.full_stack_only = value or nil
  return true
end

local set_depot_channel = function(index, value)
  local depot = depot_common.get_depot_by_index(tostring(index))
  if not depot then return false end
  value = math.floor(value)
  depot.base_channel = value
  depot.channel = value
  return true
end

-- Tier 5: Diagnostics

local diagnose_depot = function(index)
  local depot = depot_common.get_depot_by_index(tostring(index))
  if not depot then return { failure_reason = "depot not found" } end
  if not depot.entity.valid then return { failure_reason = "entity invalid" } end

  local name = depot.entity.name
  local is_requester = (name == "request-depot" or name == "buffer-depot")
  local is_fuel = (name == "fuel-depot")
  local is_active = (name == "active-depot")

  if not is_requester and not is_fuel and not is_active then
    return { failure_reason = "not a request/buffer/fuel/active depot", type = name }
  end

  local result = { type = name }

  if not depot.drones then
    result.failure_reason = "no drones table"
    return result
  end

  local drone_count = depot.get_drone_item_count and depot:get_drone_item_count() or 0
  local active_count = depot.get_active_drone_count and depot:get_active_drone_count() or 0
  local fuel = depot.get_fuel_amount and depot:get_fuel_amount() or 0

  result.drone_count = drone_count
  result.active_drones = active_count
  result.fuel_amount = fuel
  result.fuel_per_drone = fuel_amount_per_drone
  result.network_id = depot.network_id
  result.channel = depot.channel
  result.bucket_index = depot.bucket_index

  result.can_spawn = drone_count > active_count
  if not result.can_spawn then
    result.failure_reason = "no available drone (all " .. drone_count .. " active)"
    return result
  end

  result.has_fuel = fuel >= fuel_amount_per_drone
  if not result.has_fuel then
    result.fuel_on_the_way = depot.fuel_on_the_way or 0
    result.failure_reason = "insufficient fuel (" .. string.format("%.0f", fuel) .. " < " .. fuel_amount_per_drone .. ")"
    return result
  end

  if is_fuel then
    result.failure_reason = "fuel depot dispatches reactively on request"
    return result
  end

  if is_active then
    -- Active depot: check if chest has items
    local item_count = 0
    if depot.item_chest and depot.item_chest.valid then
      local inv = depot.item_chest.get_inventory(defines.inventory.chest)
      if inv then
        for _, item in pairs(inv.get_contents()) do
          item_count = item_count + item.count
        end
      end
    end
    result.chest_item_count = item_count
    if item_count == 0 then
      result.failure_reason = "no items in chest"
    else
      result.failure_reason = "has " .. item_count .. " items - should be pushing"
    end
    return result
  end

  -- Request/buffer specific
  local item = depot.item
  result.item = item
  result.has_item = item and true or false
  if not item then
    result.failure_reason = "no item set"
    return result
  end

  result.circuit_limit = depot.circuit_limit
  result.circuit_enabled = depot.circuit_limit ~= 0
  if depot.circuit_limit == 0 then
    result.failure_reason = "disabled by circuit (circuit_limit=0)"
    return result
  end

  -- should_order calculation
  local force_index = depot.entity.force.index
  local capacity_bonus = transport_technologies.get_transport_capacity_bonus(force_index)
  local stack_size = depot.get_stack_size and depot:get_stack_size() or 0
  local request_size = stack_size * (1 + capacity_bonus)
  if depot.ignore_capacity_bonus then
    request_size = stack_size
  end
  local storage_size = depot.circuit_limit or depot.storage_limit or (depot.get_storage_size and depot:get_storage_size() or (drone_count * request_size))
  local current = depot.get_current_amount and depot:get_current_amount() or 0
  local missing = storage_size - current

  result.stack_size = stack_size
  result.capacity_bonus = capacity_bonus
  result.request_size = request_size
  result.storage_size = storage_size
  result.current_amount = current
  result.missing = missing

  local should_send = math.ceil(missing / request_size)
  result.should_send_drones = should_send
  result.should_order = active_count < should_send
  if not result.should_order then
    result.failure_reason = "enough drones active (" .. active_count .. " >= " .. should_send .. ")"
    return result
  end

  -- Supply check
  local supply_depots = road_network.get_supply_depots(depot.network_id, item)
  result.has_supply = supply_depots ~= nil and next(supply_depots) ~= nil
  if not result.has_supply then
    result.failure_reason = "no supply of '" .. item .. "' on network " .. tostring(depot.network_id)
    return result
  end

  -- Channel matching
  local match_count = 0
  local my_channel = depot.channel
  local min_size = depot.get_minimum_request_size and depot:get_minimum_request_size() or 1
  result.minimum_request_size = min_size

  for depot_index, count in pairs(supply_depots) do
    local supplier = depot_common.get_depot_by_index(depot_index)
    if supplier and channels_match(my_channel, supplier.channel) and count >= min_size then
      match_count = match_count + 1
    end
  end
  result.channel_match_count = match_count
  if match_count == 0 then
    result.failure_reason = "no supply depots match channel or meet minimum (" .. min_size .. ")"
    return result
  end

  result.failure_reason = "all checks passed - should be dispatching"
  return result
end

local get_update_stats = function()
  local sd = depot_common.get_script_data()

  local total_depots = 0
  for _ in pairs(sd.depots) do
    total_depots = total_depots + 1
  end

  local bucket_count = 0
  local bucket_sizes = {}
  for idx, bucket in pairs(sd.update_buckets) do
    local size = #bucket
    if size > 0 then
      bucket_count = bucket_count + 1
    end
    bucket_sizes[idx] = size
  end

  local dirty = {}
  if sd.bucket_dirty then
    for idx in pairs(sd.bucket_dirty) do
      dirty[#dirty + 1] = idx
    end
  end

  return {
    update_rate = sd.update_rate,
    total_depots = total_depots,
    bucket_count = bucket_count,
    bucket_sizes = bucket_sizes,
    dirty_buckets = dirty,
  }
end

-- Tier 6: Force actions

local force_depot_update = function(index)
  local depot = depot_common.get_depot_by_index(tostring(index))
  if not depot then return false end
  if not depot.entity.valid then return false end
  if not depot.update then return false end
  depot:update()
  return true
end

local force_refresh_buckets = function()
  depot_common.refresh_update_buckets()
  return true
end

local debug_dispatch = function(dispatcher_index)
  local depot = depot_common.get_depot_by_index(tostring(dispatcher_index))
  if not depot then return "ERR: no depot" end
  if not depot.entity.valid then return "ERR: invalid entity" end
  if not depot.distribute_drones then return "ERR: not a dispatcher (no distribute_drones)" end
  if not depot.collect_excess_drone then return "ERR: no collect_excess_drone method" end

  local results = {}
  results[#results+1] = "dispatcher=" .. depot.index .. " network=" .. tostring(depot.network_id)
    .. " channel=" .. tostring(depot.channel)

  if not depot.network_id then return table.concat(results, " | ") .. " | ERR: no network_id" end
  local network = road_network.get_network_by_id(depot.network_id)
  if not network then return table.concat(results, " | ") .. " | ERR: no network obj" end

  local inv = depot.entity.get_inventory(defines.inventory.chest)
  if inv then
    results[#results+1] = "inv_size=" .. #inv .. " empty=" .. inv.count_empty_stacks(true, true)
      .. " bar=" .. tostring(inv.get_bar())
  end

  local drone_categories = {"request", "buffer", "fuel", "active"}
  for _, category in ipairs(drone_categories) do
    local depots_in_cat = network.depots[category]
    if depots_in_cat then
      for _, d in pairs(depots_in_cat) do
        if d.entity.valid and d.get_drone_item_count then
          d._drone_count_cache = nil
          local req = d.requested_drones
          local item_count = d:get_drone_item_count()
          local active_count = d:get_active_drone_count()
          local otw = d.drones_on_the_way or 0
          local ret = d.drones_returning or 0
          local projected = item_count + active_count + otw
          local ch = d.channel or shared.default_channel
          local ch_match = channels_match(depot.channel, ch)
          results[#results+1] = category .. ":" .. d.index
            .. " req=" .. tostring(req) .. " inv=" .. item_count
            .. " active=" .. active_count .. " otw=" .. otw .. " ret=" .. ret
            .. " projected=" .. projected .. " ch=" .. ch
            .. " ch_match=" .. tostring(ch_match)
        end
      end
    end
  end

  return table.concat(results, " | ")
end

-- Tier 7: Bulk dump

local dump_diagnostics = function()
  local sd = depot_common.get_script_data()

  local networks = {}
  for id, network in pairs(road_network.get_networks()) do
    local depot_count = 0
    for _, depots in pairs(network.depots) do
      for _ in pairs(depots) do depot_count = depot_count + 1 end
    end
    local items = 0
    for _, supply in pairs(network.item_supply) do
      for _, count in pairs(supply) do
        if count > 0 then items = items + 1; break end
      end
    end
    networks[id] = { depots = depot_count, items = items }
  end

  local depots = {}
  for index, depot in pairs(sd.depots) do
    if depot.entity.valid then
      local entry = {
        type = depot.entity.name,
        network_id = depot.network_id,
        bucket_index = depot.bucket_index,
        item = depot.item or nil,
      }
      if depot.drones then
        entry.active = depot.get_active_drone_count and depot:get_active_drone_count() or 0
        entry.drones = depot.get_drone_item_count and depot:get_drone_item_count() or 0
        entry.fuel = depot.get_fuel_amount and depot:get_fuel_amount() or 0
      end
      depots[index] = entry
    end
  end

  -- Bucket distribution
  local in_buckets = 0
  for _, bucket in pairs(sd.update_buckets) do
    in_buckets = in_buckets + #bucket
  end

  return {
    version = script.active_mods["Transport_Drones_Continued"] or "unknown",
    tick = game.tick,
    update_rate = sd.update_rate,
    total_depots = table_size(sd.depots),
    depots_in_buckets = in_buckets,
    total_drones = transport_drone.get_drone_count(),
    networks = networks,
    depots = depots,
  }
end

local interface =
{
  -- Tier 1: Network
  get_network_ids = get_network_ids,
  get_network_item_supply = get_network_item_supply,
  get_network_items = get_network_items,
  get_node_network_id = get_node_network_id,
  get_network_details = get_network_details,
  get_supply_breakdown = get_supply_breakdown,

  -- Tier 2: Depots
  get_all_depots = get_all_depots,
  get_depots_by_type = get_depots_by_type,
  get_depot_info = get_depot_info,
  get_depot_by_index = get_depot_by_index,
  get_depot_internal = get_depot_internal,

  -- Tier 3: Drones
  get_drone_count = function() return transport_drone.get_drone_count() end,
  get_all_drones = get_all_drones,
  get_drone_info = get_drone_info,

  -- Tier 4: Write
  set_allow_bots = set_allow_bots,
  set_depot_priority = set_depot_priority,
  set_storage_limit = set_storage_limit,
  set_ignore_capacity_bonus = set_ignore_capacity_bonus,
  set_full_stack_only = set_full_stack_only,
  set_depot_channel = set_depot_channel,

  -- Tier 5: Diagnostics
  diagnose_depot = diagnose_depot,
  get_update_stats = get_update_stats,
  dump_diagnostics = dump_diagnostics,

  -- Tier 6: Force actions
  force_depot_update = force_depot_update,
  force_refresh_buckets = force_refresh_buckets,
  debug_dispatch = debug_dispatch,
  rebuild_reservations = function()
    local sd = depot_common.get_script_data()
    for _, depot in pairs(sd.depots) do
      if depot.entity.valid and depot.to_be_taken then
        depot.to_be_taken = {}
      end
    end
    local drones = transport_drone.get_all_drones()
    if drones then
      for _, drone in pairs(drones) do
        if drone.entity and drone.entity.valid
           and drone.supply_depot and drone.supply_depot.entity and drone.supply_depot.entity.valid
           and drone.requested_item and drone.requested_count then
          local supply = drone.supply_depot
          if supply.to_be_taken then
            supply.to_be_taken[drone.requested_item] = (supply.to_be_taken[drone.requested_item] or 0) + drone.requested_count
          end
        end
      end
    end
    return "done"
  end,

  -- Tier 7: Technology
  get_tech_bonuses = function(force_index)
    return {
      speed = transport_technologies.get_transport_speed_bonus(force_index or 1),
      capacity = transport_technologies.get_transport_capacity_bonus(force_index or 1),
    }
  end,
}

if not remote.interfaces["transport_drones"] then
  remote.add_interface("transport_drones", interface)
end
