local shared = require("shared")

-- Define custom collision layer prototype for Factorio 2.0
data:extend{{
  type = "collision-layer",
  name = "transport_drone_road"
}}

local road_collision_layer = "transport_drone_road"
local tiles = data.raw.tile

-- Helper functions for Factorio 2.0 collision mask handling
local function get_mask(prototype)
  if not prototype.collision_mask then
    return {layers = {}}
  end
  if type(prototype.collision_mask) == "table" then
    if prototype.collision_mask.layers then
      -- Already in new format
      return prototype.collision_mask
    else
      -- Old array format, convert to new format
      local new_mask = {layers = {}}
      for _, layer in pairs(prototype.collision_mask) do
        if type(layer) == "string" then
          new_mask.layers[layer] = true
        end
      end
      return new_mask
    end
  end
  return {layers = {}}
end

local function add_layer(mask, layer)
  if not mask.layers then
    mask.layers = {}
  end
  mask.layers[layer] = true
end

local function mask_contains_layer(mask, layer)
  return mask.layers and mask.layers[layer] == true
end

local function collect_prototypes_with_layer(layer_name)
  local result = {}
  for prototype_type, prototypes in pairs(data.raw) do
    if type(prototypes) == "table" then
      for name, prototype in pairs(prototypes) do
        if type(prototype) == "table" then
          local mask = get_mask(prototype)
          if mask_contains_layer(mask, layer_name) then
            table.insert(result, prototype)
          end
        end
      end
    end
  end
  return result
end

local road_list = {}
local road_tile_list =
{
  type = "selection-tool",
  name = "road-tile-list",
  hidden = true,
  icon = "__Transport_Drones_Continued__/data/tf_util/empty-sprite.png",
  icon_size = 1,
  tile_filters = road_list,
  stack_size = 1,
  select = {
    border_color = {r = 1, g = 1, b = 1},
    mode = {"any-tile"},
    cursor_box_type = "entity",
  },
  alt_select = {
    border_color = {r = 1, g = 1, b = 1},
    mode = {"any-tile"},
    cursor_box_type = "entity",
  }
}
data:extend{road_tile_list}

local place_as_tile_condition = {layers = {["water_tile"] = true}}

local process_road_item = function(item)

  local tile = tiles[item.place_as_tile.result]
  if not tile then return end
  local seen = {}
  while true do
    tile.collision_mask = {layers = {[road_collision_layer] = true}}
    table.insert(road_list, tile.name)
    seen[tile.name] = true
    tile = tiles[tile.next_direction or ""]
    if not tile then break end
    if seen[tile.name] then break end
  end
  item.place_as_tile.condition = place_as_tile_condition
end


-- Third-party road tile whitelist (user-configurable patterns)
local whitelist_str = settings.startup["transport-drones-road-tile-whitelist"].value or ""
local whitelist = {}
for pattern in whitelist_str:gmatch("[^,]+") do
  local trimmed = pattern:match("^%s*(.-)%s*$")
  if trimmed and #trimmed > 0 then
    table.insert(whitelist, trimmed)
  end
end

if #whitelist > 0 then
  for _, item in pairs(data.raw.item) do
    if item.place_as_tile and not item.is_road_tile then
      for _, pattern in ipairs(whitelist) do
        if pattern:sub(1, 1) == "@" then
          if item.subgroup == pattern:sub(2) then
            item.is_road_tile = true
            break
          end
        else
          if item.name:find(pattern) then
            item.is_road_tile = true
            break
          end
        end
      end
    end
  end
end

for k, item in pairs (data.raw.item) do
  if item.place_as_tile and item.is_road_tile then
    process_road_item(item)
  end
end

-- Collect collision layers from all tiles, distinguishing road vs non-road.
-- Factorio 2.0 may add default layers (planet_tile, static_tile) to all tiles
-- including our road tiles, so we must exclude ALL layers present on road tiles.
local road_tile_set = {}
for _, name in pairs(road_list) do
  road_tile_set[name] = true
end

local road_tile_layers = {}
local non_road_tile_layers = {}
for k, tile in pairs (tiles) do
  tile.check_collision_with_entities = true
  local tile_mask = get_mask(tile)
  if tile_mask.layers then
    for layer, value in pairs(tile_mask.layers) do
      if value then
        if road_tile_set[tile.name] then
          road_tile_layers[layer] = true
        else
          non_road_tile_layers[layer] = true
        end
      end
    end
  end
end

-- Build drone collision mask from layers that exist on non-road tiles
-- but are NOT present on any road tile. This ensures drones can walk on
-- roads regardless of what layers the engine or other mods add to them.
-- Excluded layers:
--   "flying" - mods like Combat Mechanics Overhaul check for this layer
--     and replace the entire collision mask, turning ground drones into
--     flying entities that ignore all terrain.
--   "planet_tile", "static_tile" - Factorio 2.0 injects these default
--     layers onto ALL tiles at runtime (after the data phase), including
--     road tiles. At data time road tiles only have our custom layer, so
--     we can't detect these via road_tile_layers. Excluding them ensures
--     drones don't collide with road tiles at runtime.
local excluded_layers = {
  flying = true,
  planet_tile = true,
  static_tile = true,
}

shared.drone_collision_mask = {
  layers = {},
  colliding_with_tiles_only = true,
  consider_tile_transitions = true
}

for layer, _ in pairs(non_road_tile_layers) do
  if not road_tile_layers[layer] and not excluded_layers[layer] then
    shared.drone_collision_mask.layers[layer] = true
  end
end

-- Add road collision layer to entities with both player-layer and item-layer
for k, prototype in pairs (collect_prototypes_with_layer("player-layer")) do
  if prototype.type ~= "gate" and prototype.type ~= "tile" then
    local mask = get_mask(prototype)
    if mask_contains_layer(mask, "item-layer") then
      add_layer(mask, road_collision_layer)
      prototype.collision_mask = mask
    end
  end
end

if data.raw["assembling-machine"]["mining-depot"] then
  local depot = data.raw["assembling-machine"]["mining-depot"]
  if depot.collision_mask then
    local depot_mask = get_mask(depot)
    add_layer(depot_mask, road_collision_layer)
    depot.collision_mask = depot_mask
  end
end

local util = require "__Transport_Drones_Continued__/data/tf_util/tf_util"
require("data/entities/transport_drone/transport_drone")
require("data/make_request_recipes")

-- Space platform road support
local space_platform_roads_setting = settings.startup["transport-drones-space-platform-roads"]
local space_platform_roads_enabled = space_platform_roads_setting and space_platform_roads_setting.value

if space_platform_roads_enabled then
  local spf = data.raw.tile["space-platform-foundation"]
  if spf then
    spf.allows_being_covered = true
  end
end

-- Mod compatibility
require("data/compat/pyanodon")

-- Space Exploration compatibility: SE's space-collision.lua (which runs
-- before us due to the optional dependency) adds "space_tile" to all
-- assembling-machines and furnaces, preventing placement on SE platforms.
-- SE-postprocess also adds "planet_tile" to all tiles without "space_tile",
-- which causes zone_fix_all_tiles() to strip our roads from space surfaces.
-- Our process_road_item() already strips planet_tile from road tiles (it
-- replaces the entire collision mask). For depots, we remove space_tile here.
-- Must run before multi-pipe deepcopy below so variants inherit the fix.
if mods["space-exploration"] then
  local se_depot_types = {
    ["assembling-machine"] = {
      "request-depot", "supply-depot", "fuel-depot", "buffer-depot",
      "active-depot", "storage-depot", "drone-dispatcher", "mining-depot",
    },
    ["furnace"] = {
      "fluid-depot", shared.active_depot_fluid_name, shared.storage_depot_fluid_name,
    },
  }
  for proto_type, names in pairs(se_depot_types) do
    for _, name in ipairs(names) do
      local proto = data.raw[proto_type][name]
      if proto and proto.collision_mask and proto.collision_mask.layers then
        proto.collision_mask.layers["space_tile"] = nil
      end
    end
  end
end

-- Create multi-pipe variant prototypes with additional E/W pipe connections.
-- Players can toggle multi-pipe mode per-depot via the GUI.
local function create_multi_variant(original_type, original_name, ew_connections, target_box)
  local original = data.raw[original_type][original_name]
  if not original then return end
  -- Set matching fast_replaceable_group so base/multi can fast-replace each other
  -- (preserves pipe connections with neighbors during swap)
  original.fast_replaceable_group = original_name
  local multi = table.deepcopy(original)
  multi.name = original_name .. "-multi"
  multi.localised_name = original.localised_name
  multi.localised_description = original.localised_description
  -- Keep original placeable_by (item name may differ from entity name)
  local box_index = target_box or 2
  for _, conn in ipairs(ew_connections) do
    table.insert(multi.fluid_boxes[box_index].pipe_connections, conn)
  end
  data:extend({multi})
end

-- Fluid depot: box[2] is input - E/W should only accept fluid in
local ew_3x3_input = {
  {flow_direction = "input", position = {1, 0}, direction = defines.direction.east},
  {flow_direction = "input", position = {-1, 0}, direction = defines.direction.west},
}
create_multi_variant("furnace", "fluid-depot", ew_3x3_input)
create_multi_variant("furnace", shared.active_depot_fluid_name, ew_3x3_input)

-- Request depot and buffer depot: box[2] is output - E/W should only send fluid out
local ew_3x3_output = {
  {flow_direction = "output", position = {1, 0}, direction = defines.direction.east},
  {flow_direction = "output", position = {-1, 0}, direction = defines.direction.west},
}
create_multi_variant("assembling-machine", "request-depot", ew_3x3_output)
create_multi_variant("assembling-machine", "buffer-depot", ew_3x3_output)
-- Storage depot: box[1] is storage - E/W should only send fluid out
create_multi_variant("furnace", shared.storage_depot_fluid_name, ew_3x3_output, 1)

-- Fuel depot: box[2] is input - E/W should only accept fluid in
local ew_5x5_input = {
  {flow_direction = "input", position = {2, 0}, direction = defines.direction.east},
  {flow_direction = "input", position = {-2, 0}, direction = defines.direction.west},
}
create_multi_variant("assembling-machine", "fuel-depot", ew_5x5_input)

-- Enforce transport-drone stack size from shared config.
-- Some mods (e.g. Silicon) bulk-override all item stack sizes in data-final-fixes.
-- Our stack_size is intentional and affects drone inventory slot calculations.
if data.raw.item[shared.drone_item_name] then
  data.raw.item[shared.drone_item_name].stack_size = shared.drone_stack_size
end
