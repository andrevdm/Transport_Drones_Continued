-- Depot Migration: adopts unregistered depot entities into our storage.
-- Handles saves from other forks that use identical prototype names,
-- or any situation where depot entities exist on the map but aren't tracked.

local shared = require("shared")
local road_network = require("script/road_network")
local depot_common = require("script/depot_common")

local request_depot_lib = require("script/depots/request_depot")
local supply_depot_lib = require("script/depots/supply_depot")
local fuel_depot_lib = require("script/depots/fuel_depot")
local fluid_depot_lib = require("script/depots/fluid_depot")
local buffer_depot_lib = require("script/depots/buffer_depot")
local network_reader_lib = require("script/depots/network_reader")

-- Known forks that use the same prototype names
local KNOWN_FORKS = {
  "Transport_Drones_Meglinge_Fork",
}

-- Map of depot entity names to their library modules
local depot_configs = {
  ["request-depot"]       = {lib = request_depot_lib,  has_drones = true,  stat = "request_depots"},
  ["fuel-depot"]          = {lib = fuel_depot_lib,     has_drones = true,  stat = "fuel_depots"},
  ["buffer-depot"]        = {lib = buffer_depot_lib,   has_drones = true,  stat = "buffer_depots"},
  ["fluid-depot"]         = {lib = fluid_depot_lib,    has_drones = false, stat = "fluid_depots"},
  ["road-network-reader"] = {lib = network_reader_lib, has_drones = false, stat = "network_readers"},
}

local migration_data -- set in on_init/on_load

-- ============================================================
-- Detection
-- ============================================================

local get_active_forks = function()
  local active = {}
  for _, mod_name in pairs(KNOWN_FORKS) do
    if script.active_mods[mod_name] then
      active[#active + 1] = mod_name
    end
  end
  return active
end

local has_unregistered_depots = function()
  local td = depot_common.get_script_data()
  if not td then return false end
  if next(td.depots) then return false end
  for _, surface in pairs(game.surfaces) do
    if surface.count_entities_filtered{name = {"request-depot", "supply-depot", "fuel-depot", "fluid-depot", "buffer-depot"}, limit = 1} > 0 then
      return true
    end
  end
  return false
end

local should_show_button = function()
  if migration_data.complete then return false end
  return #get_active_forks() > 0 or has_unregistered_depots()
end

-- ============================================================
-- GUI
-- ============================================================

local BUTTON_NAME = "depot_migration_button"
local CONFIRM_FRAME = "depot_migration_confirm_frame"
local CONFIRM_YES = "depot_migration_confirm_yes"
local CONFIRM_NO = "depot_migration_confirm_no"

local show_button = function(player)
  if player.gui.top[BUTTON_NAME] then return end
  player.gui.top.add{
    type = "button",
    name = BUTTON_NAME,
    caption = {"", "[img=utility/warning_icon] Recover unregistered depots"},
    tooltip = "Adopt all Transport Drones depot entities that are not tracked by this mod.\n\nFor best results, wait until all active drones have returned to depots before converting.",
    style = "red_confirm_button"
  }
end

local hide_button = function(player)
  local button = player.gui.top[BUTTON_NAME]
  if button then button.destroy() end
end

local show_confirmation = function(player)
  local frame = player.gui.screen[CONFIRM_FRAME]
  if frame then frame.destroy() end

  frame = player.gui.screen.add{
    type = "frame",
    name = CONFIRM_FRAME,
    direction = "vertical",
    caption = "Recover unregistered depots"
  }
  frame.auto_center = true

  local inner = frame.add{type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical"}
  inner.style.width = 480

  inner.add{type = "label", caption = "This will adopt all Transport Drones depot entities that are not tracked by this mod."}
  inner.add{type = "line", direction = "horizontal"}

  local warn = inner.add{type = "flow", direction = "horizontal"}
  local warn_icon = warn.add{type = "sprite", sprite = "utility/warning_icon"}
  warn_icon.style.size = {32, 32}
  warn_icon.style.stretch_image_to_widget_size = true
  local warn_labels = warn.add{type = "flow", direction = "vertical"}
  warn_labels.add{type = "label", caption = "Active drones on the road will be lost."}
  warn_labels.add{type = "label", caption = "Drones stored as recipe ingredients in depots have been lost (recipe change)."}
  warn_labels.add{type = "label", caption = "You will need to re-add drones to your depots after conversion."}

  local active_forks = get_active_forks()
  if #active_forks > 0 then
    inner.add{type = "line", direction = "horizontal"}
    inner.add{type = "label", caption = "After conversion you must:"}
    local steps = inner.add{type = "flow", direction = "vertical"}
    steps.style.left_padding = 16
    steps.add{type = "label", caption = "1. Save the game"}
    steps.add{type = "label", caption = "2. Disable: " .. table.concat(active_forks, ", ")}
    steps.add{type = "label", caption = "3. Restart Factorio"}
  end

  local buttons = frame.add{type = "flow", direction = "horizontal"}
  buttons.style.horizontal_align = "right"
  buttons.style.horizontally_stretchable = true
  local spacer = buttons.add{type = "empty-widget"}
  spacer.style.horizontally_stretchable = true
  buttons.add{type = "button", name = CONFIRM_NO, caption = "Cancel"}
  buttons.add{type = "button", name = CONFIRM_YES, caption = "Convert now", style = "confirm_button"}
end

-- ============================================================
-- Conversion helpers
-- ============================================================

local circuit_offsets = {
  [defines.direction.north] = {0, 1},
  [defines.direction.east]  = {-1, 0},
  [defines.direction.south] = {0, -1},
  [defines.direction.west]  = {1, 0},
}

local destroy_corpses_near = function(surface, position, radius)
  for _, corpse in pairs(surface.find_entities_filtered{
    name = {"transport-caution-corpse", "invisible-transport-caution-corpse"},
    position = position,
    radius = radius or 1.5
  }) do
    corpse.destroy()
  end
end

local ensure_node = function(surface, x, y)
  if road_network.get_node(surface.index, x, y) then return true end

  local tile = surface.get_tile(x, y)
  local tile_proto = prototypes.tile[tile.name]
  if tile_proto and tile_proto.collision_mask and tile_proto.collision_mask.layers
     and tile_proto.collision_mask.layers["transport_drone_road"] then
    road_network.add_node(surface.index, x, y)
    return true
  end

  -- Try placing a road tile
  surface.set_tiles({{name = "transport-drone-road", position = {x, y}}}, false, "abort_on_collision", false, true)
  return road_network.get_node(surface.index, x, y) ~= nil
end

-- Collect all drone chest prototype names for searching
local all_drone_chest_names = {}
for _, name in pairs(shared.drone_chest_name) do
  all_drone_chest_names[#all_drone_chest_names + 1] = name
end

local extract_drones_and_destroy_old_chest = function(entity)
  local total = 0

  -- Find depot-drone-chest entities at the depot position and extract drones.
  -- Destroy old chests since new() will create fresh ones.
  for _, chest in pairs(entity.surface.find_entities_filtered{
    name = all_drone_chest_names,
    position = entity.position,
    radius = 0.5
  }) do
    local inv = chest.get_inventory(defines.inventory.chest)
    if inv then
      total = total + inv.get_item_count("transport-drone")
    end
    chest.destroy()
  end

  -- NOTE: Some forks store drones as recipe ingredients (in assembler input).
  -- Those drones are unrecoverable: when our mod loads, the recipe prototype
  -- changes to fluid-only, Factorio shrinks the input inventory to 0 item
  -- slots, and the drones are silently destroyed before any Lua code runs.

  return total
end

-- Register a depot in our storage and road network
local register_depot = function(depot, td, surface)
  script.register_on_object_destroyed(depot.entity)
  depot.surface_index = surface.index
  td.depots[depot.index] = depot

  local node = road_network.get_node(depot.surface_index, depot.node_position[1], depot.node_position[2])
  if node then
    node.depots = node.depots or {}
    node.depots[depot.index] = depot
    depot:add_to_network()
    return true
  end
  -- No road node - depot can't function, clean up
  td.depots[depot.index] = nil
  return false
end

-- Attach circuit writers/readers to nearby depots
local attach_circuit_writer = function(entity, depots)
  local offset = circuit_offsets[entity.direction]
  if not offset then return false end
  local sx = entity.position.x + offset[1]
  local sy = entity.position.y + offset[2]
  entity.rotatable = false

  for _, found in pairs(entity.surface.find_entities_filtered{position = {sx, sy}}) do
    local depot = depots[tostring(found.unit_number)]
    if depot and not (depot.circuit_writer and depot.circuit_writer.valid) then
      depot.circuit_writer = entity
      return true
    end
  end
  return false
end

local attach_circuit_reader = function(entity, depots)
  local offset = circuit_offsets[entity.direction]
  if not offset then return false end
  local sx = entity.position.x + offset[1]
  local sy = entity.position.y + offset[2]
  entity.rotatable = false

  for _, found in pairs(entity.surface.find_entities_filtered{position = {sx, sy}}) do
    local depot = depots[tostring(found.unit_number)]
    if depot then
      if depot.no_reader then break end
      if not (depot.circuit_reader and depot.circuit_reader.valid) then
        depot.circuit_reader = entity
        rendering.draw_sprite{
          sprite = "utility/fluid_indication_arrow",
          surface = entity.surface,
          only_in_alt_mode = true,
          target = entity,
          target_offset = {offset[1] / 2, offset[2] / 2},
          orientation_target = entity
        }
        return true
      end
    end
  end
  return false
end

-- Convert road-network-reader-filtered → transport-depot-reader with mode=3
local convert_local_reader = function(entity, depots)
  local offset = circuit_offsets[entity.direction]
  if not offset then return false end
  local sx = entity.position.x + offset[1]
  local sy = entity.position.y + offset[2]

  local pos = entity.position
  local dir = entity.direction
  local force = entity.force
  local surface = entity.surface

  -- Save wire connections
  local wire_targets = {}
  for _, wire_id in pairs({defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green}) do
    local connector = entity.get_wire_connector(wire_id)
    if connector then
      for _, connection in pairs(connector.connections) do
        table.insert(wire_targets, {
          wire_id = wire_id,
          target_entity = connection.target.owner,
          target_wire_id = connection.target.wire_connector_id
        })
      end
    end
  end

  -- Find target depot
  local target_depot = nil
  for _, found in pairs(surface.find_entities_filtered{position = {sx, sy}}) do
    local depot = depots[tostring(found.unit_number)]
    if depot and not depot.no_reader and not (depot.circuit_reader and depot.circuit_reader.valid) then
      target_depot = depot
      break
    end
  end

  entity.destroy()

  if target_depot then
    local new_entity = surface.create_entity{
      name = "transport-depot-reader",
      position = pos,
      direction = dir,
      force = force,
      raise_built = true
    }
    if new_entity then
      for _, wt in pairs(wire_targets) do
        if wt.target_entity and wt.target_entity.valid then
          local src = new_entity.get_wire_connector(wt.wire_id)
          local dst = wt.target_entity.get_wire_connector(wt.target_wire_id)
          if src and dst then
            src.connect_to(dst)
          end
        end
      end
      storage.reader_config = storage.reader_config or {}
      storage.reader_config[new_entity.unit_number] = {mode = 3}
      return true
    end
  else
    surface.spill_item_stack{position = pos, stack = {name = "transport-depot-reader", count = 1}, force = force}
  end
  return false
end

-- ============================================================
-- Main conversion
-- ============================================================

local perform_conversion = function(player)
  local say = player and player.print or game.print
  local td = depot_common.get_script_data()
  if not td then
    say("[Transport Drones] Error: depot storage not initialized.")
    return
  end

  local stats = {
    request_depots = 0, supply_depots = 0, fuel_depots = 0,
    fluid_depots = 0, buffer_depots = 0, network_readers = 0,
    circuit_writers = 0, circuit_readers = 0, local_readers = 0,
    drones_killed = 0, drones_recovered = 0, errors = 0,
  }

  for _, surface in pairs(game.surfaces) do

    -- Phase 1: Kill all active transport drone units
    for _, entity in pairs(surface.find_entities_filtered{type = "unit"}) do
      if entity.valid and entity.name:find("^transport%-drone%-") then
        entity.destroy()
        stats.drones_killed = stats.drones_killed + 1
      end
    end

    -- Phase 2: Supply depots (special: need to handle existing supply-depot-chest)
    -- Build lookup of assemblers already tracked by our mod
    local known_assemblers = {}
    for _, depot in pairs(td.depots) do
      if depot.assembler and depot.assembler.valid then
        known_assemblers[depot.assembler.unit_number] = true
      end
    end

    local all_chest_names = {}
    for _, name in pairs(shared.supply_chest_name) do all_chest_names[#all_chest_names + 1] = name end
    for _, name in pairs(shared.supply_chest_name_logistic) do all_chest_names[#all_chest_names + 1] = name end

    for _, assembler in pairs(surface.find_entities_filtered{name = "supply-depot"}) do
      if not known_assemblers[assembler.unit_number] then
        -- Save and destroy the old supply-depot-chest
        local chest_items = {}
        local chest_bar
        for _, old_chest in pairs(surface.find_entities_filtered{name = all_chest_names, position = assembler.position, radius = 0.5}) do
          local inv = old_chest.get_output_inventory()
          if inv then
            for _, item in pairs(inv.get_contents()) do
              chest_items[#chest_items + 1] = {name = item.name, count = item.count, quality = item.quality}
            end
            chest_bar = inv.get_bar()
          end
          old_chest.destroy()
        end

        -- Clean up old corpse
        local offset = supply_depot_lib.corpse_offsets[assembler.direction]
        if offset then
          local cx = assembler.position.x + offset[1]
          local cy = assembler.position.y + offset[2]
          destroy_corpses_near(surface, {cx, cy})
          ensure_node(surface, math.floor(cx), math.floor(cy))
        end

        local ok, depot = pcall(supply_depot_lib.new, assembler)
        if ok and depot then
          if register_depot(depot, td, surface) then
            -- Restore inventory
            local new_inv = depot.entity.get_output_inventory()
            for _, item in pairs(chest_items) do
              local inserted = new_inv.insert(item)
              if inserted < item.count then
                surface.spill_item_stack{
                  position = assembler.position,
                  stack = {name = item.name, count = item.count - inserted, quality = item.quality},
                  force = assembler.force
                }
              end
            end
            if chest_bar then
              local max = #new_inv + 1
              if chest_bar <= max then new_inv.set_bar(chest_bar) end
            end
            stats.supply_depots = stats.supply_depots + 1
          else
            stats.errors = stats.errors + 1
          end
        else
          stats.errors = stats.errors + 1
        end
      end
    end

    -- Phase 3: All other depot types (request, fuel, fluid, buffer, network-reader)
    for entity_name, config in pairs(depot_configs) do
      for _, entity in pairs(surface.find_entities_filtered{name = entity_name}) do
        local index = tostring(entity.unit_number)
        if not td.depots[index] then
          -- Extract drones from old drone chest and destroy it (new() creates a fresh one)
          local drone_count = 0
          if config.has_drones then
            drone_count = extract_drones_and_destroy_old_chest(entity)
          end

          -- Clean up old corpse and ensure node exists
          local offset = config.lib.corpse_offsets[entity.direction]
          if offset then
            local cx = entity.position.x + offset[1]
            local cy = entity.position.y + offset[2]
            destroy_corpses_near(surface, {cx, cy})
            ensure_node(surface, math.floor(cx), math.floor(cy))
          end

          local ok, depot = pcall(config.lib.new, entity)
          if ok and depot then
            if register_depot(depot, td, surface) then
              -- Transfer drones to new drone chest
              if drone_count > 0 and depot.drone_chest and depot.drone_chest.valid then
                depot.drone_chest.get_inventory(defines.inventory.chest).insert(
                  {name = "transport-drone", count = drone_count}
                )
                stats.drones_recovered = stats.drones_recovered + drone_count
              end
              stats[config.stat] = stats[config.stat] + 1
            else
              stats.errors = stats.errors + 1
            end
          else
            stats.errors = stats.errors + 1
          end
        end
      end
    end

    -- Phase 4: Attach circuit entities
    for _, entity in pairs(surface.find_entities_filtered{name = "transport-depot-writer"}) do
      if attach_circuit_writer(entity, td.depots) then
        stats.circuit_writers = stats.circuit_writers + 1
      end
    end

    for _, entity in pairs(surface.find_entities_filtered{name = "transport-depot-reader"}) do
      if attach_circuit_reader(entity, td.depots) then
        stats.circuit_readers = stats.circuit_readers + 1
      end
    end

    for _, entity in pairs(surface.find_entities_filtered{name = "road-network-reader-filtered"}) do
      if convert_local_reader(entity, td.depots) then
        stats.local_readers = stats.local_readers + 1
      end
    end

  end -- surface loop

  -- Rebuild all update buckets
  depot_common.refresh_update_buckets()

  -- Mark complete
  migration_data.complete = true
  migration_data.last_stats = stats

  -- Hide buttons
  for _, p in pairs(game.players) do
    hide_button(p)
  end

  -- Summary
  local total = stats.request_depots + stats.supply_depots + stats.fuel_depots
              + stats.fluid_depots + stats.buffer_depots + stats.network_readers
  say("[Transport Drones] Migration complete!")
  say(string.format(
    "  Depots: %d (request=%d, supply=%d, fuel=%d, fluid=%d, buffer=%d, reader=%d)",
    total, stats.request_depots, stats.supply_depots, stats.fuel_depots,
    stats.fluid_depots, stats.buffer_depots, stats.network_readers))
  say(string.format(
    "  Circuit: writers=%d, readers=%d, filtered=%d",
    stats.circuit_writers, stats.circuit_readers, stats.local_readers))
  say(string.format(
    "  Drones: recovered=%d, lost (active)=%d",
    stats.drones_recovered, stats.drones_killed))
  if stats.errors > 0 then
    say(string.format("  [color=red]Errors: %d (depots without road connection)[/color]", stats.errors))
  end
  local active_forks = get_active_forks()
  if #active_forks > 0 then
    say("[color=yellow]IMPORTANT: Save, disable " .. table.concat(active_forks, ", ") .. ", and restart Factorio.[/color]")
  end

  return stats
end

-- ============================================================
-- Event handlers
-- ============================================================

local on_gui_click = function(event)
  local element = event.element
  if not (element and element.valid) then return end

  local name = element.name
  if name ~= BUTTON_NAME and name ~= CONFIRM_YES and name ~= CONFIRM_NO then return end

  local player = game.get_player(event.player_index)
  if not player then return end

  if name == BUTTON_NAME then
    show_confirmation(player)
  elseif name == CONFIRM_YES then
    local frame = player.gui.screen[CONFIRM_FRAME]
    if frame then frame.destroy() end
    perform_conversion(player)
  elseif name == CONFIRM_NO then
    local frame = player.gui.screen[CONFIRM_FRAME]
    if frame then frame.destroy() end
  end
end

local check_and_show_button = function()
  if should_show_button() then
    for _, player in pairs(game.players) do
      show_button(player)
    end
  end
end

-- ============================================================
-- Module interface
-- ============================================================

local lib = {}

lib.events = {
  [defines.events.on_gui_click] = on_gui_click,
  [defines.events.on_player_created] = function(event)
    if should_show_button() then
      local player = game.get_player(event.player_index)
      if player then show_button(player) end
    end
  end,
  [defines.events.on_player_joined_game] = function(event)
    if should_show_button() then
      local player = game.get_player(event.player_index)
      if player then show_button(player) end
    end
  end,
}

lib.on_init = function()
  storage.depot_migration = storage.depot_migration or storage.fork_migration or {complete = false}
  storage.fork_migration = nil
  migration_data = storage.depot_migration
  check_and_show_button()
end

lib.on_load = function()
  migration_data = storage.depot_migration or storage.fork_migration or {complete = false}
end

lib.on_configuration_changed = function(event)
  storage.depot_migration = storage.depot_migration or storage.fork_migration or {complete = false}
  storage.fork_migration = nil
  migration_data = storage.depot_migration

  -- A known fork was just removed: clean up UI
  if event and event.mod_changes then
    for _, mod_name in pairs(KNOWN_FORKS) do
      local change = event.mod_changes[mod_name]
      if change and change.old_version and not change.new_version then
        for _, player in pairs(game.players) do
          hide_button(player)
        end
        if migration_data.complete then
          game.print("[Transport Drones] Fork mod removed. Migration finalized.")
          return
        end
      end
    end
  end

  check_and_show_button()
end

lib.add_remote_interface = function()
  remote.add_interface("transport_drones_migration", {
    convert = function(player_index)
      local player = player_index and game.get_player(player_index) or nil
      return perform_conversion(player)
    end,
    get_stats = function()
      return migration_data and migration_data.last_stats
    end,
    is_complete = function()
      return migration_data and migration_data.complete or false
    end,
    reset = function()
      if migration_data then
        migration_data.complete = false
        migration_data.last_stats = nil
      end
    end
  })
end

return lib
