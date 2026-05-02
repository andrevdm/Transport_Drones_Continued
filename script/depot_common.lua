local transport_drone = require("script/transport_drone")
local road_network = require("script/road_network")
local transport_technologies = require("script/transport_technologies")
local depot_base = require("script/depot_base")

local depot_libs = {}

local required_interfaces =
{
  corpse_offsets = "table",
  metatable = "table",
  new = "function",
  on_removed = "function",
  update = "function"
}

local add_depot_lib = function(entity_name, lib)
  for name, value_type in pairs (required_interfaces) do
    if not lib[name] or type(lib[name]) ~= value_type then
      error("Trying to add lib without all required interfaces: "..serpent.block(
        {
          entity_name = entity_name,
          missing_value_key = name,
          value_type = type(lib[name]),
          expected_type = value_type
        }))
    end
  end
  depot_libs[entity_name] = lib
end

add_depot_lib("request-depot", require("script/depots/request_depot"))
add_depot_lib("request-depot-multi", require("script/depots/request_depot"))
add_depot_lib("supply-depot", require("script/depots/supply_depot"))
for _, name in pairs(shared.supply_chest_name) do
  add_depot_lib(name, require("script/depots/supply_depot"))
end
for _, name in pairs(shared.supply_chest_name_logistic) do
  add_depot_lib(name, require("script/depots/supply_depot"))
end
add_depot_lib("fuel-depot", require("script/depots/fuel_depot"))
add_depot_lib("fuel-depot-multi", require("script/depots/fuel_depot"))
add_depot_lib("mining-depot", require("script/depots/mining_depot"))
add_depot_lib("fluid-depot", require("script/depots/fluid_depot"))
add_depot_lib("fluid-depot-multi", require("script/depots/fluid_depot"))
add_depot_lib("buffer-depot", require("script/depots/buffer_depot"))
add_depot_lib("buffer-depot-multi", require("script/depots/buffer_depot"))
add_depot_lib("active-depot", require("script/depots/active_depot"))
add_depot_lib(shared.active_depot_fluid_name, require("script/depots/active_depot"))
add_depot_lib(shared.active_depot_fluid_name .. "-multi", require("script/depots/active_depot"))
add_depot_lib("storage-depot", require("script/depots/storage_depot"))
add_depot_lib(shared.storage_depot_fluid_name, require("script/depots/storage_depot"))
add_depot_lib(shared.storage_depot_fluid_name .. "-multi", require("script/depots/storage_depot"))
for _, name in pairs(shared.storage_chest_name) do
  add_depot_lib(name, require("script/depots/storage_depot"))
end
for _, name in pairs(shared.storage_chest_name_logistic) do
  add_depot_lib(name, require("script/depots/storage_depot"))
end
add_depot_lib("drone-dispatcher", require("script/depots/dispatcher_depot"))
for _, name in pairs(shared.dispatcher_chest_name) do
  add_depot_lib(name, require("script/depots/dispatcher_depot"))
end
add_depot_lib("road-network-reader", require("script/depots/network_reader"))

local match = "transport_drones_add_"
for name, setting in pairs (settings.startup) do
  if name:find(match) then
    local lib_name = name:sub(match:len() + 1)
    local path = setting.value
    add_depot_lib(lib_name, require(path))
  end
end

local script_data =
{
  depots = {},
  update_buckets = {},
  bucket_dirty = {},
  redispatch_set = {},
  dispatch_set = {},
  reset_to_be_taken_again = true,
  refresh_techs = true,
  update_rate = 60,
  reset_fuel_on_the_way = true
}

local mark_bucket_dirty = function(depot)
  if depot.bucket_index then
    script_data.bucket_dirty[depot.bucket_index] = true
  end
end

local _sort_depots
local priority_comparator = function(a, b)
  local da = _sort_depots[a]
  local db = _sort_depots[b]
  local pa = da and da.priority or shared.default_priority
  local pb = db and db.priority or shared.default_priority
  if pa ~= pb then return pa > pb end
  return a < b
end

local get_depot_by_index = function(index)
  return script_data.depots[index]
end

local get_depot = function(entity)
  return get_depot_by_index(tostring(entity.unit_number))
end


local get_corpse_position = function(entity, corpse_offsets)

  local position = entity.position
  local direction = entity.direction
  local offset = corpse_offsets[direction]
  return {position.x + offset[1], position.y + offset[2]}

end

local mineable_tiles
local is_tile_mineable = function(name)
  if not mineable_tiles then
    mineable_tiles = {}
    for _, tile in pairs (prototypes.tile) do
      if tile.mineable_properties and tile.mineable_properties.minable then
        mineable_tiles[tile.name] = true
      end
    end
  end
  return mineable_tiles[name]
end

local attempt_to_place_node = function(entity, depot_lib)
  local corpse_position = get_corpse_position(entity, depot_lib.corpse_offsets)
  local surface = entity.surface

  local node_position = {math.floor(corpse_position[1]), math.floor(corpse_position[2])}

  if road_network.get_node(surface.index, node_position[1], node_position[2]) then
    --Already a node here, don't worry
    return true
  end

  -- Check if existing tile is already a road tile (supports custom mod tiles)
  local existing_tile = surface.get_tile(node_position).name
  local tile_proto = prototypes.tile[existing_tile]
  if tile_proto and tile_proto.collision_mask and tile_proto.collision_mask.layers
     and tile_proto.collision_mask.layers["transport_drone_road"] then
    road_network.add_node(surface.index, node_position[1], node_position[2])
    return true
  end

  -- Third-party depots: only place connection tile if roads are already nearby
  if depot_lib.optional_road_connection then
    local has_neighbor = false
    for dx = -1, 1 do
      for dy = -1, 1 do
        if not (dx == 0 and dy == 0) then
          if road_network.get_node(surface.index, node_position[1] + dx, node_position[2] + dy) then
            has_neighbor = true
            break
          end
        end
      end
      if has_neighbor then break end
    end
    if not has_neighbor then return false end
  end

  -- Fallback: place transport-drone-road for bare ground
  if not is_tile_mineable(existing_tile) then
    surface.set_hidden_tile(node_position, existing_tile)
  end

  local tiles = { {name = "transport-drone-road", position = node_position} }
  surface.set_tiles(tiles, false, "abort_on_collision", false, true)

  if road_network.get_node(surface.index, node_position[1], node_position[2]) then
    return true
  end

  return false
end

local refund_build = function(event, entity_prototype)

  local item = entity_prototype.items_to_place_this[1]
  if not item then return end

  if event.player_index then
    game.get_player(event.player_index).insert(item)
    return
  end

  if event.robot and event.robot.valid then
    event.robot.get_inventory(defines.inventory.robot_cargo).insert(item)
    return
  end
end

local add_depot_to_node = function(depot)
  local node = road_network.get_node(depot.surface_index, depot.node_position[1], depot.node_position[2])

  if not node then
    depot:on_removed({})
    depot.entity.destroy()
    return true
  end
  node.depots = node.depots or {}
  node.depots[depot.index] = depot
end

local remove_depot_from_node = function(surface, x, y, depot_index)
  local node = road_network.get_node(surface, x, y)
  if not node then return end
  node.depots[depot_index] = nil
  road_network.check_clear_lonely_node(surface, x, y)
end

local big = math.huge
local add_to_update_bucket = function(index)
  local best_bucket
  local best_bucket_index
  local best_count = big
  local buckets = script_data.update_buckets
  for k = 1, script_data.update_rate do
    local bucket_index = k % script_data.update_rate
    local bucket = buckets[bucket_index]
    if not bucket then
      bucket = {}
      buckets[bucket_index] = bucket
      best_bucket = bucket
      best_bucket_index = bucket_index
      best_count = 0
      break
    end
    local size = #bucket
    if size < best_count then
      best_bucket = bucket
      best_bucket_index = bucket_index
      best_count = size
    end
  end
  best_bucket[best_count + 1] = index
  local depot = script_data.depots[index]
  if depot then
    depot.bucket_index = best_bucket_index
  end
  script_data.bucket_dirty[best_bucket_index] = true
end

local circuit_offsets =
{
  [defines.direction.north] = {0, 1},
  [defines.direction.east] = {-1, 0},
  [defines.direction.south] = {0, -1},
  [defines.direction.west] = {1, 0},
}

local circuit_writer_built = function(entity, player_index)
  local offset = circuit_offsets[entity.direction]
  if not offset then error("Unknown direction for circuit entity: " .. tostring(entity.direction)) end
  local search_position = entity.position
  search_position.x = search_position.x + offset[1]
  search_position.y = search_position.y + offset[2]

  entity.rotatable = false

  for k, found_entity in pairs (entity.surface.find_entities_filtered{position = search_position}) do
    local this_depot = get_depot(found_entity)
    if this_depot then
      if not (this_depot.circuit_writer and this_depot.circuit_writer.valid) then
        this_depot.circuit_writer = entity
        this_depot:say("Circuit writer attached", player_index)
        return
      end
    end
  end
end

local circuit_reader_built = function(entity, player_index)
  local offset = circuit_offsets[entity.direction]
  if not offset then error("Unknown direction for circuit entity: " .. tostring(entity.direction)) end
  local search_position = entity.position
  search_position.x = search_position.x + offset[1]
  search_position.y = search_position.y + offset[2]

  entity.rotatable = false

  local attached = false

  for k, found_entity in pairs (entity.surface.find_entities_filtered{position = search_position}) do
    local this_depot = get_depot(found_entity)
    if this_depot then
      if not (this_depot.circuit_reader and this_depot.circuit_reader.valid) then
        this_depot.circuit_reader = entity
        this_depot:say("Circuit reader attached", player_index)
        -- Default reader config: show capacity enabled
        storage.reader_config = storage.reader_config or {}
        if not storage.reader_config[entity.unit_number] then
          storage.reader_config[entity.unit_number] = {show_capacity = true}
        end
        attached = true
        break
      end
    end
  end

  if attached then
    rendering.draw_sprite
    {
      sprite = "utility/fluid_indication_arrow",
      surface = entity.surface,
      only_in_alt_mode = true,
      target = entity,
      target_offset = {offset[1] / 2, offset[2] / 2},
      orientation_target = entity
    }
  end

end

local on_created_entity = function(event)
  local entity = event.entity or event.created_entity
  if not (entity and entity.valid) then return end

  local name = entity.name

  if name == "transport-depot-writer" then
    circuit_writer_built(entity, event.player_index)
    -- Restore writer config from blueprint tags
    if event.tags and event.tags.writer_config then
      storage.writer_config = storage.writer_config or {}
      storage.writer_config[entity.unit_number] = event.tags.writer_config
    end
    return
  end

  if name == "transport-depot-reader" then
    circuit_reader_built(entity, event.player_index)
    return
  end

  local depot_lib = depot_libs[name]
  if not depot_lib then
    return
  end

  if not attempt_to_place_node(entity, depot_lib) then
    if depot_lib.optional_road_connection then
      return -- Third-party entity; don't destroy, just skip road registration
    end
    refund_build(event, entity.prototype)
    entity.destroy({raise_destroy = true})
    return
  end

  local depot = depot_lib.new(entity, event.tags)
  -- new() may swap the entity (e.g. fluid mode toggle), so register the final entity
  if entity.valid then
    script.register_on_object_destroyed(entity)
  end
  -- Supply depots: the depot entity (chest) differs from the built entity (assembler).
  -- Register both so on_object_destroyed catches whichever is destroyed first.
  if depot.entity.unit_number ~= (entity.valid and entity.unit_number) then
    script.register_on_object_destroyed(depot.entity)
  end
  depot.surface_index = depot.entity.surface.index
  script_data.depots[depot.index] = depot
  if add_depot_to_node(depot) then
    return
  end
  depot:add_to_network()
  add_to_update_bucket(depot.index)

  local final = depot.entity
  for k, nearby in pairs (final.surface.find_entities_filtered{name = "transport-depot-writer", radius = final.get_radius() + 1, position = final.position}) do
    circuit_writer_built(nearby, event.player_index)
  end

  for k, nearby in pairs (final.surface.find_entities_filtered{name = "transport-depot-reader", radius = final.get_radius() + 1, position = final.position}) do
    circuit_reader_built(nearby, event.player_index)
  end

end

local remove_depot = function(depot, event)
  depot:remove_from_network()
  local surface = depot.surface_index
  local index = depot.index
  local x, y = depot.node_position[1], depot.node_position[2]
  remove_depot_from_node(surface, x, y, index)
  script_data.depots[index] = nil
  depot:on_removed(event)
end

-- For supply depots, the depot is indexed by the chest's unit_number,
-- but the entity being removed may be the assembler. Fall back to a
-- scan of depots when the direct lookup fails for a known depot entity.
local find_depot_by_assembler = function(entity)
  if not depot_libs[entity.name] then return end
  local unit_number = entity.unit_number
  for _, depot in pairs(script_data.depots) do
    if depot.assembler and depot.assembler.valid and depot.assembler.unit_number == unit_number then
      return depot
    end
  end
end

local on_entity_removed = function(event)
  local entity = event.entity

  if not (entity and entity.valid) then return end

  -- Clean up writer config when a writer is destroyed
  if entity.name == "transport-depot-writer" and storage.writer_config then
    storage.writer_config[entity.unit_number] = nil
  end

  -- Clean up reader config when a reader is destroyed
  if entity.name == "transport-depot-reader" and storage.reader_config then
    storage.reader_config[entity.unit_number] = nil
  end

  local depot = get_depot(entity) or find_depot_by_assembler(entity)
  if depot then
    remove_depot(depot, event)
  end

end

local on_entity_destroyed = function(event)
  local useful_id = event.useful_id
  if not useful_id then return end

  local depot = get_depot_by_index(tostring(useful_id))
  if depot then
    remove_depot(depot, event)
  end
end

local get_lib = function(depot)
  if not depot.entity.valid then
    return {}
  end
  local name = depot.entity.name
  return depot_libs[name]
end

local load_depot = function(depot)
  local lib = get_lib(depot)
  if lib.metatable then
    setmetatable(depot, lib.metatable)
  end
end

local update_depots = function(tick)
  local bucket_index = tick % script_data.update_rate
  local update_list = script_data.update_buckets[bucket_index]
  if not update_list then return end

  local depots = script_data.depots

  -- Only re-sort when a depot in this bucket had its priority changed
  if script_data.bucket_dirty[bucket_index] then
    _sort_depots = depots
    table.sort(update_list, priority_comparator)
    script_data.bucket_dirty[bucket_index] = nil
  end

  local k = 1
  while true do
    local depot_index = update_list[k]
    if not depot_index then return end
    local depot = depots[depot_index]
    if not (depot and depot.entity.valid) then
      depots[depot_index] = nil
      local last = #update_list
      if k == last then
        update_list[k] = nil
      else
        update_list[k], update_list[last] = update_list[last], nil
      end
    else
      depot:update()
      local redispatch_set = script_data.redispatch_set
      if depot._redispatch then
        redispatch_set[depot_index] = true
      else
        redispatch_set[depot_index] = nil
      end
      if depot._needs_dispatch then
        script_data.dispatch_set[depot_index] = true
      else
        script_data.dispatch_set[depot_index] = nil
      end
      k = k + 1
    end
  end

end

local scan_optional_depots = function()
  for name, depot_lib in pairs(depot_libs) do
    if depot_lib.optional_road_connection and prototypes.entity[name] then
      for _, surface in pairs(game.surfaces) do
        for _, entity in pairs(surface.find_entities_filtered{name = name}) do
          local index = tostring(entity.unit_number)
          if not script_data.depots[index] then
            if attempt_to_place_node(entity, depot_lib) then
              local depot = depot_lib.new(entity)
              script.register_on_object_destroyed(entity)
              depot.surface_index = entity.surface.index
              script_data.depots[index] = depot
              if not add_depot_to_node(depot) then
                depot:add_to_network()
                add_to_update_bucket(index)
              end
            end
          end
        end
      end
    end
  end
end

local process_redispatch = function()
  local set = script_data.redispatch_set
  if not next(set) then return end
  local depots = script_data.depots
  for depot_index, _ in pairs(set) do
    local depot = depots[depot_index]
    if not depot or not depot.entity.valid or not depot.make_request then
      set[depot_index] = nil
    else
      depot._drone_count_cache = nil
      depot:make_request()
      if not depot._redispatch then
        set[depot_index] = nil
      end
    end
  end
end

local process_dispatcher_dispatch = function()
  local set = script_data.dispatch_set
  if not set or not next(set) then return end
  local depots = script_data.depots
  for depot_index, _ in pairs(set) do
    local depot = depots[depot_index]
    if not depot or not depot.entity.valid or not depot.distribute_drones then
      set[depot_index] = nil
    else
      depot:distribute_drones()
      if not depot._needs_dispatch then
        set[depot_index] = nil
      end
    end
  end
end

local scan_pending = false

local on_tick = function(event)
  if scan_pending then
    scan_pending = false
    scan_optional_depots()
  end
  local tick = event.tick
  update_depots(tick)
  if tick % settings.global["transport-drone-redispatch-interval"].value == 0 then
    process_redispatch()
  end
  if tick % 30 == 0 then
    process_dispatcher_dispatch()
  end
end

local setup_lib_values = function()

  for k, lib in pairs (depot_libs) do
    lib.road_network = road_network
    lib.transport_drone = transport_drone
    lib.transport_technologies = transport_technologies
    lib.get_depot = get_depot_by_index
    lib.add_to_update_bucket = add_to_update_bucket
    lib.mark_bucket_dirty = mark_bucket_dirty
  end

end

local insert = table.insert
local refresh_update_buckets = function()
  local count = 1
  local interval = script_data.update_rate
  local buckets = {}
  local dirty = {}
  for index, depot in pairs (script_data.depots) do
    local bucket_index = count % interval
    buckets[bucket_index] = buckets[bucket_index] or {}
    insert(buckets[bucket_index], index)
    depot.bucket_index = bucket_index
    dirty[bucket_index] = true
    count = count + 1
  end
  script_data.update_buckets = buckets
  script_data.bucket_dirty = dirty
end

local refresh_update_rate = function()
  local update_rate = settings.global["transport-depot-update-interval"].value
  if script_data.update_rate == update_rate then return end
  script_data.update_rate = update_rate
  refresh_update_buckets()
end

local on_runtime_mod_setting_changed = function(event)
  refresh_update_rate()
  depot_base.refresh_settings_cache()
end

local picker_dolly_blacklist = function()

  if remote.interfaces["PickerDollies"] then
    for name, depot_lib in pairs (depot_libs) do
      remote.call("PickerDollies", "add_blacklist_name", name, true)
    end
  end

end

local get_tags = function(blueprint_entity, surface)
  local name = blueprint_entity.name
  local lib = depot_libs[name]
  if not lib then return end

  if name == "supply-depot" then
    local entity
    for _, chest_name in pairs(shared.supply_chest_name) do
      entity = surface.find_entity(chest_name, blueprint_entity.position)
      if entity then break end
    end
    if not entity then
      for _, chest_name in pairs(shared.supply_chest_name_logistic) do
        entity = surface.find_entity(chest_name, blueprint_entity.position)
        if entity then break end
      end
    end
    if not entity then return end
    local depot = get_depot(entity)
    if not depot then return end
    local saver = depot.save_to_blueprint_tags
    if not saver then return end
    return saver(depot)
  end

  if name == "storage-depot" then
    local entity
    for _, chest_name in pairs(shared.storage_chest_name) do
      entity = surface.find_entity(chest_name, blueprint_entity.position)
      if entity then break end
    end
    if not entity then
      for _, chest_name in pairs(shared.storage_chest_name_logistic) do
        entity = surface.find_entity(chest_name, blueprint_entity.position)
        if entity then break end
      end
    end
    if not entity then
      -- Fluid mode: depot entity is the furnace, indexed directly
      entity = surface.find_entity(shared.storage_depot_fluid_name, blueprint_entity.position)
        or surface.find_entity(shared.storage_depot_fluid_name .. "-multi", blueprint_entity.position)
    end
    if not entity then return end
    local depot = get_depot(entity)
    if not depot then return end
    local saver = depot.save_to_blueprint_tags
    if not saver then return end
    return saver(depot)
  end

  if name == "drone-dispatcher" then
    local entity
    for _, chest_name in pairs(shared.dispatcher_chest_name) do
      entity = surface.find_entity(chest_name, blueprint_entity.position)
      if entity then break end
    end
    if not entity then return end
    local depot = get_depot(entity)
    if not depot then return end
    local saver = depot.save_to_blueprint_tags
    if not saver then return end
    return saver(depot)
  end

  local entity = surface.find_entity(name, blueprint_entity.position)
  if not entity then return end

  local depot = get_depot(entity)
  if not depot then return end

  local saver = depot.save_to_blueprint_tags
  if not saver then return end

  return saver(depot)
end


local on_player_setup_blueprint = function(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  local item = player.cursor_stack
  if not (item and item.valid_for_read) then
    item = player.blueprint_to_setup
    if not (item and item.valid_for_read) then return end
  end

  local entities = item.get_blueprint_entities()
  if not (entities and next(entities)) then return end

  local surface = player.surface

  for index, blueprint_entity in pairs(entities) do
    local tags = get_tags(blueprint_entity, surface)
    if tags then
      item.set_blueprint_entity_tag(index, "transport_depot_tags", tags)
    end
    -- Save writer config to blueprint tags
    if blueprint_entity.name == "transport-depot-writer" and storage.writer_config then
      local writer = surface.find_entity("transport-depot-writer", blueprint_entity.position)
      if writer then
        local config = storage.writer_config[writer.unit_number]
        if config then
          item.set_blueprint_entity_tag(index, "writer_config", config)
        end
      end
    end
  end
end

-- Circuit entity placement highlights
local circuit_highlight_items = {
  ["transport-depot-writer"] = true,
  ["transport-depot-reader"] = true,
}

local depot_highlight_names = {"request-depot", "request-depot-multi", "supply-depot", "fuel-depot", "fuel-depot-multi", "buffer-depot", "buffer-depot-multi", "fluid-depot", "fluid-depot-multi", "active-depot", shared.active_depot_fluid_name, shared.active_depot_fluid_name .. "-multi", "storage-depot", shared.storage_depot_fluid_name, shared.storage_depot_fluid_name .. "-multi", "drone-dispatcher"}

local clear_circuit_highlights = function(player_index)
  local highlights = script_data.circuit_highlights and script_data.circuit_highlights[player_index]
  if highlights then
    for _, entity in pairs(highlights) do
      if entity.valid then entity.destroy() end
    end
    script_data.circuit_highlights[player_index] = nil
  end
end

local update_circuit_highlights = function(event)
  local player = game.get_player(event.player_index)
  if not player then return end

  clear_circuit_highlights(event.player_index)

  -- Check cursor stack or cursor ghost
  local item_name
  local cursor = player.cursor_stack
  if cursor and cursor.valid_for_read then
    item_name = cursor.name
  else
    local ghost = player.cursor_ghost
    if ghost then
      item_name = ghost.name
    end
  end

  if not item_name or not circuit_highlight_items[item_name] then return end

  -- Build target names (exclude supply for reader; include mining-depot if available)
  local base = depot_highlight_names
  local names = base
  if prototypes.entity["mining-depot"] then
    names = {}
    for _, n in pairs(base) do names[#names + 1] = n end
    names[#names + 1] = "mining-depot"
  end

  local surface = player.surface
  local pos = player.position
  local area = {{pos.x - 100, pos.y - 100}, {pos.x + 100, pos.y + 100}}
  local entities = surface.find_entities_filtered{name = names, area = area}

  if not script_data.circuit_highlights then
    script_data.circuit_highlights = {}
  end

  local highlights = {}
  for _, depot_entity in pairs(entities) do
    local h = surface.create_entity{
      name = "highlight-box",
      position = depot_entity.position,
      source = depot_entity,
    }
    if h then
      h.highlight_box_type = "copy"
      h.render_player = player
      h.time_to_live = 60 * 60 * 5
      highlights[#highlights + 1] = h
    end
  end

  script_data.circuit_highlights[event.player_index] = highlights
end

local on_player_left = function(event)
  clear_circuit_highlights(event.player_index)
end

local lib = {}

lib.events =
{
  [defines.events.on_built_entity] = on_created_entity,
  [defines.events.on_robot_built_entity] = on_created_entity,
  [defines.events.script_raised_built] = on_created_entity,
  [defines.events.script_raised_revive] = on_created_entity,

  [defines.events.on_entity_died] = on_entity_removed,
  [defines.events.on_robot_mined_entity] = on_entity_removed,
  [defines.events.script_raised_destroy] = on_entity_removed,
  [defines.events.on_player_mined_entity] = on_entity_removed,
  [defines.events.on_object_destroyed] = on_entity_destroyed,

  [defines.events.on_player_setup_blueprint] = on_player_setup_blueprint,

  [defines.events.on_player_cursor_stack_changed] = update_circuit_highlights,
  [defines.events.on_player_left_game] = on_player_left,
  [defines.events.on_player_removed] = on_player_left,

  [defines.events.on_tick] = on_tick,
  [defines.events.on_runtime_mod_setting_changed] = on_runtime_mod_setting_changed
}

lib.on_init = function()
  storage.transport_depots = storage.transport_depots or script_data
  storage.writer_config = storage.writer_config or {}
  setup_lib_values()
  refresh_update_rate()
  picker_dolly_blacklist()
end

lib.on_load = function()
  script_data = storage.transport_depots or script_data
  setup_lib_values()
  for k, depot in pairs (script_data.depots) do
    load_depot(depot)
  end
  scan_pending = true
end



lib.on_configuration_changed = function()
  scan_pending = false

  storage.transport_depots = storage.transport_depots or script_data

  -- Pre-compute name lookups for migrations
  local dispatcher_names = {}
  for _, name in pairs(shared.dispatcher_chest_name) do
    dispatcher_names[name] = true
  end
  local active_fluid = shared.active_depot_fluid_name
  local active_fluid_multi = active_fluid .. "-multi"
  local fuel_fluid = depot_base.get_fuel_fluid()
  local storage_fluid = shared.storage_depot_fluid_name
  local storage_fluid_multi = storage_fluid .. "-multi"

  for k, depot in pairs (script_data.depots) do
    if not depot.entity.valid then
      -- Clean up orphaned sub-entities before removing the depot
      if depot.rendering and depot.rendering.valid then
        depot.rendering:destroy()
      end
      if depot.corpse and depot.corpse.valid then
        depot.corpse.destroy()
      end
      if depot.assembler and depot.assembler.valid then
        depot.assembler.destroy()
      end
      script_data.depots[k] = nil
    else
      local ename = depot.entity.name

      -- Migrate active depot fluid mode flag
      if not depot.fluid_mode then
        if ename == active_fluid or ename == active_fluid_multi then
          depot.fluid_mode = true
        end
      end

      -- Migrate active depot: recreate entity to fix fluidbox layout
      -- Old layout had volume=5000 output box that trapped fluid; new layout has volume=1
      if depot.fluid_mode and (ename == active_fluid or ename == active_fluid_multi) then
        local fb1 = depot.entity.fluidbox[1]
        if fb1 and fb1.amount > 1 then
          local old = depot.entity
          local saved_fluid = {name = fb1.name, amount = fb1.amount, temperature = fb1.temperature}
          local pos = old.position
          local dir = old.direction
          local surface = old.surface
          local force = old.force
          local quality = old.quality.name
          old.destroy()
          local new_entity = surface.create_entity{
            name = ename, position = pos, direction = dir, force = force, quality = quality
          }
          new_entity.destructible = false
          new_entity.active = false
          new_entity.rotatable = false
          new_entity.fluidbox[2] = saved_fluid
          depot.entity = new_entity
        end
      end

      -- Migrate active depot: move physical fuel to virtual tracking
      if depot.fluid_mode and not depot.fuel_amount_stored then
        local fb_fuel = depot.entity.get_fluid_count(fuel_fluid)
        if fb_fuel > 0 then
          depot.fuel_amount_stored = fb_fuel
          depot.entity.remove_fluid({name = fuel_fluid, amount = fb_fuel})
        end
      end

      -- Migrate storage depot: swap fluid from old fb[2] to new fb[1]
      if depot.fluid_mode and (ename == storage_fluid or ename == storage_fluid_multi) then
        local fb2 = depot.entity.fluidbox[2]
        if fb2 and fb2.amount > 0 then
          depot.entity.clear_fluid_inside()
          depot.entity.fluidbox[1] = {name = fb2.name, amount = fb2.amount, temperature = fb2.temperature}
        end
      end

      -- Migrate active depot: add supplier fields for central dispatch supply
      if depot.item_chest and not depot.to_be_taken then
        depot.to_be_taken = {}
        depot.old_contents = {}
      end

      -- Migrate dispatcher chests: set bar + filters for locked return slots
      if dispatcher_names[ename] then
        local quality_level = depot.assembler and depot.assembler.valid
          and depot.assembler.quality and depot.assembler.quality.level or 0
        local player_slots = shared.quality_dispatcher_player_slots[quality_level] or 10
        depot.player_slots = player_slots
        local inv = depot.entity.get_inventory(defines.inventory.chest)
        if inv then
          inv.set_bar(player_slots + 1)
          for i = 1, #inv do
            inv.set_filter(i, {name = "transport-drone", quality = "normal", comparator = ">="})
          end
        end
        depot.drones = depot.drones or {}
        depot.fuel_on_the_way = depot.fuel_on_the_way or 0
      end

      -- Standard re-registration (after migrations that may recreate entities)
      script.register_on_object_destroyed(depot.entity)
      depot.surface_index = depot.entity.surface.index
      if depot.set_request_mode then
        depot:set_request_mode()
      end
      if depot.get_corpse then
        depot:get_corpse()
      end
      if not add_depot_to_node(depot) then
        depot:remove_from_network()
        depot:add_to_network()
        if depot.to_be_taken then
          depot.to_be_taken = {}
        end
        if depot.fuel_on_the_way then
          depot.fuel_on_the_way = 0
        end
        if depot.items_on_the_way then
          depot.items_on_the_way = 0
        end
        if depot.drones_on_the_way then
          depot.drones_on_the_way = 0
        end
        if depot.drones_returning then
          depot.drones_returning = 0
        end
      end
    end
  end

  refresh_update_rate()

  -- Ensure tables exist (migration from older saves)
  script_data.redispatch_set = script_data.redispatch_set or {}
  script_data.dispatch_set = script_data.dispatch_set or {}
  script_data.bucket_dirty = script_data.bucket_dirty or {}
  for bucket_index in pairs(script_data.update_buckets) do
    script_data.bucket_dirty[bucket_index] = true
  end

  scan_optional_depots()

  picker_dolly_blacklist()
end

lib.get_depot = function(entity)
  return script_data.depots[tostring(entity.unit_number)]
end

lib.get_depot_by_index = get_depot_by_index

lib.get_all_depots = function()
  return script_data.depots
end

lib.get_script_data = function()
  return script_data
end

lib.refresh_update_buckets = refresh_update_buckets

lib.on_road_tile_placed = function(surface_index, positions)
  -- Build bounding box around placed road tiles, expanded by 6
  -- (mining depot corpse offset is 4.5, plus 1 for neighbor check)
  local min_x, min_y = math.huge, math.huge
  local max_x, max_y = -math.huge, -math.huge
  for _, pos in pairs(positions) do
    local x, y = pos.x or pos[1], pos.y or pos[2]
    if x < min_x then min_x = x end
    if x > max_x then max_x = x end
    if y < min_y then min_y = y end
    if y > max_y then max_y = y end
  end

  local surface = game.get_surface(surface_index)
  if not surface then return end

  local area = {{min_x - 6, min_y - 6}, {max_x + 7, max_y + 7}}

  for name, depot_lib in pairs(depot_libs) do
    if depot_lib.optional_road_connection and prototypes.entity[name] then
      for _, entity in pairs(surface.find_entities_filtered{name = name, area = area}) do
        local index = tostring(entity.unit_number)
        if not script_data.depots[index] then
          if attempt_to_place_node(entity, depot_lib) then
            local depot = depot_lib.new(entity)
            script.register_on_object_destroyed(entity)
            depot.surface_index = entity.surface.index
            script_data.depots[index] = depot
            if not add_depot_to_node(depot) then
              depot:add_to_network()
              add_to_update_bucket(index)
            end
          end
        end
      end
    end
  end
end

return lib
