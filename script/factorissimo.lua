-- Factorissimo 3 integration: cross-surface road network portals
-- Bridges road networks inside factory buildings with the outside road network.
-- Drones teleport at factory entrances to traverse between surfaces.

local road_network = require("script/road_network")

local floor = math.floor
local abs = math.abs
local sqrt = math.sqrt

local script_data = {
  portals = {},             -- portal_id -> portal data
  building_to_portal = {},  -- building unit_number -> portal_id
  next_portal_id = 1,
}

local factorissimo_active = false

local factorissimo = {}

-- Factory building entity names
local factory_names_set = {}
local factory_names_list = {}

local function init_factory_names()
  factory_names_set = {}
  factory_names_list = {}
  for _, n in pairs({"factory-1", "factory-2", "factory-3",
                      "space-factory-1", "space-factory-2", "space-factory-3"}) do
    if prototypes.entity[n] then
      factory_names_set[n] = true
      table.insert(factory_names_list, n)
    end
  end
end

-- Search offsets for finding road nodes near factory doors
-- Outside door: tiles at door position and just south (away from building)
local outside_search = {
  {0, 0}, {-1, 0}, {1, 0},
  {0, 1}, {-1, 1}, {1, 1},
}
-- Inside door: tiles just north of entrance (into the factory interior)
local inside_search = {
  {0, -1}, {-1, -1}, {1, -1},
  {0, -2}, {-1, -2}, {1, -2},
  {0, 0}, {-1, 0}, {1, 0},
}

-- Find nearest road node to a door position
local function find_road_near_door(surface_index, door_x, door_y, offsets)
  local bx = floor(door_x)
  local by = floor(door_y)
  for _, off in pairs(offsets) do
    local nx, ny = bx + off[1], by + off[2]
    local node = road_network.get_node(surface_index, nx, ny)
    if node then
      return nx, ny, node
    end
  end
  return nil
end

-- Show a status message at a portal endpoint
local function portal_message(surface_index, x, y, text, color)
  local surface = game.surfaces[surface_index]
  if not surface then return end
  rendering.draw_text{
    text = text,
    surface = surface,
    target = {x + 0.5, y + 0.5},
    color = color,
    time_to_live = 180,
    scale = 1.5
  }
end

local color_connected = {r = 0.3, g = 1, b = 0.3}
local color_disconnected = {r = 1, g = 0.3, b = 0.3}

-- Create a navigation corpse at a portal endpoint
local function create_portal_corpse(surface_index, x, y)
  local surface = game.surfaces[surface_index]
  if not surface then return nil end
  local corpse = surface.create_entity{
    name = "transport-caution-corpse",
    position = {x + 0.5, y + 0.5}
  }
  if corpse then
    corpse.corpse_expires = false
  end
  return corpse
end

-- Destroy a portal's corpses
local function destroy_portal_corpses(portal)
  if portal.corpse_outside and portal.corpse_outside.valid then
    portal.corpse_outside.destroy()
  end
  portal.corpse_outside = nil
  if portal.corpse_inside and portal.corpse_inside.valid then
    portal.corpse_inside.destroy()
  end
  portal.corpse_inside = nil
end

-- Get factory data from a building entity via Factorissimo remote API
local function get_factory(entity)
  local ok, factory = pcall(remote.call, "factorissimo", "get_factory_by_building", entity)
  if ok and factory then return factory end
  return nil
end

-- Scan a factory building and detect portal connection
local function scan_factory_portal(entity)
  local factory = get_factory(entity)
  if not factory then return nil end

  local outside_surface = factory.outside_surface
  local inside_surface = factory.inside_surface
  if not (outside_surface and outside_surface.valid and inside_surface and inside_surface.valid) then
    return nil
  end

  local outside_si = outside_surface.index
  local inside_si = inside_surface.index

  -- Find road nodes near outside and inside doors
  local ox, oy, outside_node = find_road_near_door(
    outside_si, factory.outside_door_x, factory.outside_door_y, outside_search)
  local ix, iy, inside_node = find_road_near_door(
    inside_si, factory.inside_door_x, factory.inside_door_y, inside_search)

  return {
    outside_surface = outside_si,
    outside_door_x = factory.outside_door_x,
    outside_door_y = factory.outside_door_y,
    outside_x = ox,
    outside_y = oy,
    inside_surface = inside_si,
    inside_door_x = factory.inside_door_x,
    inside_door_y = factory.inside_door_y,
    inside_x = ix,
    inside_y = iy,
    has_outside = outside_node ~= nil,
    has_inside = inside_node ~= nil,
    factory_id = factory.id,
  }
end

-- Register a factory building: create portal entry, activate if both sides have roads
local function register_factory(entity)
  local unit_number = entity.unit_number
  if not unit_number then return end
  if script_data.building_to_portal[unit_number] then return end -- already registered

  local scan = scan_factory_portal(entity)
  if not scan then return end

  local portal_id = script_data.next_portal_id
  script_data.next_portal_id = portal_id + 1

  local portal = {
    id = portal_id,
    building = entity,
    factory_id = scan.factory_id,
    outside_surface = scan.outside_surface,
    outside_door_x = scan.outside_door_x,
    outside_door_y = scan.outside_door_y,
    outside_x = scan.outside_x,
    outside_y = scan.outside_y,
    inside_surface = scan.inside_surface,
    inside_door_x = scan.inside_door_x,
    inside_door_y = scan.inside_door_y,
    inside_x = scan.inside_x,
    inside_y = scan.inside_y,
    active = false,
  }

  script_data.portals[portal_id] = portal
  script_data.building_to_portal[unit_number] = portal_id

  -- Activate if both sides have road nodes
  if scan.has_outside and scan.has_inside then
    portal.active = true
    portal.corpse_outside = create_portal_corpse(portal.outside_surface, portal.outside_x, portal.outside_y)
    portal.corpse_inside = create_portal_corpse(portal.inside_surface, portal.inside_x, portal.inside_y)
    road_network.merge_portal_link(
      portal.outside_surface, portal.outside_x, portal.outside_y,
      portal.inside_surface, portal.inside_x, portal.inside_y)
    portal_message(portal.outside_surface, portal.outside_x, portal.outside_y, {"factory-portal-connected"}, color_connected)
    portal_message(portal.inside_surface, portal.inside_x, portal.inside_y, {"factory-portal-connected"}, color_connected)
  end

  return portal_id
end

-- Unregister a factory building: deactivate portal, clean up
local function unregister_factory(entity)
  local unit_number = entity.unit_number
  if not unit_number then return end

  local portal_id = script_data.building_to_portal[unit_number]
  if not portal_id then return end

  local portal = script_data.portals[portal_id]
  if portal then
    if portal.active and portal.outside_x then
      portal_message(portal.outside_surface, portal.outside_x, portal.outside_y, {"factory-portal-disconnected"}, color_disconnected)
    end
    if portal.active and portal.inside_x then
      portal_message(portal.inside_surface, portal.inside_x, portal.inside_y, {"factory-portal-disconnected"}, color_disconnected)
    end
    destroy_portal_corpses(portal)
    script_data.portals[portal_id] = nil
  end

  script_data.building_to_portal[unit_number] = nil
end

-- Re-check a portal after tile changes near its doors
local function recheck_portal(portal)
  if not (portal.building and portal.building.valid) then return end

  local ox, oy = find_road_near_door(
    portal.outside_surface, portal.outside_door_x, portal.outside_door_y, outside_search)
  local ix, iy = find_road_near_door(
    portal.inside_surface, portal.inside_door_x, portal.inside_door_y, inside_search)

  local should_be_active = (ox ~= nil and ix ~= nil)

  if should_be_active and not portal.active then
    -- Activate
    portal.outside_x = ox
    portal.outside_y = oy
    portal.inside_x = ix
    portal.inside_y = iy
    portal.active = true
    portal.corpse_outside = create_portal_corpse(portal.outside_surface, ox, oy)
    portal.corpse_inside = create_portal_corpse(portal.inside_surface, ix, iy)
    road_network.merge_portal_link(
      portal.outside_surface, ox, oy,
      portal.inside_surface, ix, iy)
    portal_message(portal.outside_surface, ox, oy, {"factory-portal-connected"}, color_connected)
    portal_message(portal.inside_surface, ix, iy, {"factory-portal-connected"}, color_connected)

  elseif should_be_active and portal.active then
    -- Already active - re-merge in case tile changes caused a network split
    portal.outside_x = ox
    portal.outside_y = oy
    portal.inside_x = ix
    portal.inside_y = iy
    road_network.merge_portal_link(
      portal.outside_surface, ox, oy,
      portal.inside_surface, ix, iy)

  elseif not should_be_active and portal.active then
    -- Deactivate - need full network reset to split
    local old_ox, old_oy = portal.outside_x, portal.outside_y
    local old_ix, old_iy = portal.inside_x, portal.inside_y
    destroy_portal_corpses(portal)
    portal.active = false
    portal.outside_x = nil
    portal.outside_y = nil
    portal.inside_x = nil
    portal.inside_y = nil
    if old_ox then
      portal_message(portal.outside_surface, old_ox, old_oy, {"factory-portal-disconnected"}, color_disconnected)
    end
    if old_ix then
      portal_message(portal.inside_surface, old_ix, old_iy, {"factory-portal-disconnected"}, color_disconnected)
    end
  end
end

-- Check if a tile event affects any portal
local function on_tile_changed(surface_index, positions)
  if not factorissimo_active then return end

  for _, portal in pairs(script_data.portals) do
    local dominated = false
    for _, pos in pairs(positions) do
      local x, y = pos.x or pos[1], pos.y or pos[2]
      if surface_index == portal.outside_surface then
        if abs(x - floor(portal.outside_door_x)) <= 2 and abs(y - floor(portal.outside_door_y)) <= 2 then
          dominated = true
          break
        end
      end
      if surface_index == portal.inside_surface then
        if abs(x - floor(portal.inside_door_x)) <= 3 and abs(y - floor(portal.inside_door_y)) <= 3 then
          dominated = true
          break
        end
      end
    end
    if dominated then
      recheck_portal(portal)
    end
  end
end

-- Full scan: find all factory buildings and set up portals
local function full_scan()
  -- Clear existing portals
  for _, portal in pairs(script_data.portals) do
    destroy_portal_corpses(portal)
  end
  script_data.portals = {}
  script_data.building_to_portal = {}
  script_data.next_portal_id = 1

  if #factory_names_list == 0 then return end

  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered{name = factory_names_list}
    for _, entity in pairs(entities) do
      register_factory(entity)
    end
  end
end

-- Portal link provider for road_network.reset() Phase 3
local function get_portal_links()
  local links = {}
  for _, portal in pairs(script_data.portals) do
    if portal.active and portal.outside_x and portal.inside_x then
      table.insert(links, {
        portal.outside_surface, portal.outside_x, portal.outside_y,
        portal.inside_surface, portal.inside_x, portal.inside_y
      })
    end
  end
  return links
end

-- ============================================================
-- Public API (used by transport_drone.lua for teleportation)
-- ============================================================

-- Find a portal connecting two surfaces
-- Returns portal or nil
function factorissimo.find_portal(from_surface, to_surface)
  for _, portal in pairs(script_data.portals) do
    if portal.active then
      if portal.outside_surface == from_surface and portal.inside_surface == to_surface then
        return portal, "outside_to_inside"
      end
      if portal.inside_surface == from_surface and portal.outside_surface == to_surface then
        return portal, "inside_to_outside"
      end
    end
  end
  return nil
end

-- Find a portal path between two surfaces (may require multiple hops for nested factories)
-- from_pos: optional {x, y} position of the drone on from_surface (used for entry distance)
-- target_pos: optional {x, y} position of the target on to_surface (used for exit distance)
-- When both are given, picks the path with the lowest total cost (entry_dist + exit_dist).
-- Returns ordered list of {portal, direction} or nil
function factorissimo.find_portal_path(from_surface, to_surface, target_pos, from_pos)
  if from_surface == to_surface then return nil end

  -- BFS over portal graph
  local visited = {[from_surface] = true}
  local queue = {{surface = from_surface, path = {}}}
  local head = 1
  local found = {}
  local found_depth

  while head <= #queue do
    local current = queue[head]
    head = head + 1

    -- Stop BFS once we've passed the depth where solutions were found
    if found_depth and #current.path >= found_depth then
      break
    end

    for _, portal in pairs(script_data.portals) do
      if portal.active then
        local next_surface, direction
        if portal.outside_surface == current.surface and not visited[portal.inside_surface] then
          next_surface = portal.inside_surface
          direction = "outside_to_inside"
        elseif portal.inside_surface == current.surface and not visited[portal.outside_surface] then
          next_surface = portal.outside_surface
          direction = "inside_to_outside"
        end

        if next_surface then
          local new_path = {}
          for _, step in pairs(current.path) do
            table.insert(new_path, step)
          end
          table.insert(new_path, {portal = portal, direction = direction})

          if next_surface == to_surface then
            if not target_pos and not from_pos then
              return new_path  -- no preference, return first
            end
            table.insert(found, new_path)
            found_depth = #new_path
          else
            -- Only expand if we haven't found solutions yet at a shallower depth
            if not found_depth then
              visited[next_surface] = true
              table.insert(queue, {surface = next_surface, path = new_path})
            end
          end
        end
      end
    end
  end

  if #found == 0 then return nil end
  if #found == 1 then return found[1] end

  -- Score each candidate path by total distance (entry + exit)
  local best_path, best_cost
  local tx, ty
  if target_pos then
    tx, ty = target_pos[1] or target_pos.x, target_pos[2] or target_pos.y
  end
  local fx, fy
  if from_pos then
    fx, fy = from_pos[1] or from_pos.x, from_pos[2] or from_pos.y
  end
  for _, path in pairs(found) do
    local cost = 0

    -- Entry distance: drone position → first portal's entry point
    if fx then
      local first_step = path[1]
      local entry_x, entry_y
      if first_step.direction == "outside_to_inside" then
        entry_x, entry_y = first_step.portal.outside_x, first_step.portal.outside_y
      else
        entry_x, entry_y = first_step.portal.inside_x, first_step.portal.inside_y
      end
      local dx, dy = (entry_x or 0) - fx, (entry_y or 0) - fy
      cost = cost + sqrt(dx * dx + dy * dy)
    end

    -- Exit distance: last portal's exit point → target position
    if tx then
      local last_step = path[#path]
      local ex, ey
      if last_step.direction == "outside_to_inside" then
        ex, ey = last_step.portal.inside_x, last_step.portal.inside_y
      else
        ex, ey = last_step.portal.outside_x, last_step.portal.outside_y
      end
      local dx, dy = (ex or 0) - tx, (ey or 0) - ty
      cost = cost + sqrt(dx * dx + dy * dy)
    end

    if not best_cost or cost < best_cost then
      best_cost = cost
      best_path = path
    end
  end
  return best_path
end

-- Get the entry corpse for a portal from a given surface
function factorissimo.get_entry_corpse(portal, from_surface)
  if from_surface == portal.outside_surface then
    return portal.corpse_outside
  elseif from_surface == portal.inside_surface then
    return portal.corpse_inside
  end
  return nil
end

-- Get the exit position and surface after traversing a portal
function factorissimo.get_exit(portal, direction)
  if direction == "outside_to_inside" then
    return portal.inside_surface, portal.inside_x + 0.5, portal.inside_y + 0.5
  else
    return portal.outside_surface, portal.outside_x + 0.5, portal.outside_y + 0.5
  end
end

-- Check if factorissimo integration is active
function factorissimo.is_active()
  return factorissimo_active
end

-- Resolve a surface to its parent planet surface by traversing portals upward.
-- If the surface IS a planet, returns its index unchanged.
-- For factory interiors, follows outside_surface links until reaching a planet.
-- Uses our portal data first, falls back to Factorissimo remote API.
function factorissimo.resolve_planet_surface(surface_index)
  if not factorissimo_active then return surface_index end
  local visited = {}
  local si = surface_index
  for _ = 1, 10 do -- safety limit for nested factories
    local surface = game.surfaces[si]
    if not surface then return surface_index end
    -- Check if this is a real planet (not a factorissimo interior that also has .planet)
    if surface.planet then
      local ok, is_facto = pcall(remote.call, "factorissimo", "is_factorissimo_surface", si)
      if not (ok and is_facto) then return si end
    end
    if visited[si] then return si end
    visited[si] = true
    -- Try our portal data first
    local next_si = nil
    for _, portal in pairs(script_data.portals) do
      if portal.inside_surface == si then
        next_si = portal.outside_surface
        break
      end
    end
    -- Fallback: use Factorissimo remote API
    if not next_si then
      local ok, factory = pcall(remote.call, "factorissimo", "find_surrounding_factory", surface, {x = 0, y = 0})
      if ok and factory and factory.outside_surface and factory.outside_surface.valid then
        next_si = factory.outside_surface.index
      end
    end
    if not next_si then return si end
    si = next_si
  end
  return si
end

-- ============================================================
-- Event handlers
-- ============================================================

local function on_built_entity(event)
  if not factorissimo_active then return end
  local entity = event.entity or event.created_entity
  if not (entity and entity.valid) then return end
  if not factory_names_set[entity.name] then return end
  register_factory(entity)
end

local function on_entity_removed(event)
  if not factorissimo_active then return end
  local entity = event.entity
  if not (entity and entity.valid) then return end
  if not factory_names_set[entity.name] then return end
  unregister_factory(entity)
end

local function on_tile_event(event)
  if not factorissimo_active then return end
  if not event.tiles then return end

  local positions = {}
  for _, tile in pairs(event.tiles) do
    table.insert(positions, tile.position)
  end
  if #positions > 0 then
    on_tile_changed(event.surface_index, positions)
  end
end

-- ============================================================
-- Lifecycle
-- ============================================================

factorissimo.on_init = function()
  storage.factorissimo = storage.factorissimo or script_data

  factorissimo_active = remote.interfaces["factorissimo"] ~= nil
  if factorissimo_active then
    init_factory_names()
  end
end

factorissimo.on_load = function()
  script_data = storage.factorissimo or script_data

  factorissimo_active = remote.interfaces["factorissimo"] ~= nil
  if factorissimo_active then
    init_factory_names()
  end
end

factorissimo.on_configuration_changed = function()
  storage.factorissimo = storage.factorissimo or script_data
  script_data = storage.factorissimo

  factorissimo_active = remote.interfaces["factorissimo"] ~= nil
  if not factorissimo_active then return end

  init_factory_names()
  full_scan()
end

factorissimo.events = {
  [defines.events.on_built_entity] = on_built_entity,
  [defines.events.on_robot_built_entity] = on_built_entity,
  [defines.events.script_raised_built] = on_built_entity,

  [defines.events.on_player_mined_entity] = on_entity_removed,
  [defines.events.on_robot_mined_entity] = on_entity_removed,
  [defines.events.on_entity_died] = on_entity_removed,
  [defines.events.script_raised_destroy] = on_entity_removed,

  [defines.events.on_player_built_tile] = on_tile_event,
  [defines.events.on_robot_built_tile] = on_tile_event,
  [defines.events.on_player_mined_tile] = on_tile_event,
  [defines.events.on_robot_mined_tile] = on_tile_event,
  [defines.events.script_raised_set_tiles] = on_tile_event,
}

-- Compute effective distance between two points on different surfaces,
-- travelling through portal doors. Returns Euclidean distance (not squared).
function factorissimo.portal_distance(from_surface, from_pos, to_surface, to_pos)
  local path = factorissimo.find_portal_path(from_surface, to_surface, to_pos, from_pos)
  if not path then return nil end
  local total = 0
  local cx, cy = from_pos[1], from_pos[2]
  for _, step in ipairs(path) do
    local entry_x, entry_y, exit_x, exit_y
    if step.direction == "outside_to_inside" then
      entry_x, entry_y = step.portal.outside_x, step.portal.outside_y
      exit_x, exit_y = step.portal.inside_x, step.portal.inside_y
    else
      entry_x, entry_y = step.portal.inside_x, step.portal.inside_y
      exit_x, exit_y = step.portal.outside_x, step.portal.outside_y
    end
    local dx, dy = cx - entry_x, cy - entry_y
    total = total + sqrt(dx * dx + dy * dy)
    cx, cy = exit_x, exit_y
  end
  local dx, dy = cx - to_pos[1], cy - to_pos[2]
  total = total + sqrt(dx * dx + dy * dy)
  return total
end

-- Register portal link provider for road_network.reset()
road_network.portal_link_provider = function()
  if not factorissimo_active then return nil end
  -- During reset, portals may have stale node references - re-scan
  init_factory_names()
  full_scan()
  return get_portal_links()
end

-- Register portal distance estimator for cross-surface depot scoring
road_network.portal_distance = function(fs, fp, ts, tp)
  if not factorissimo_active then return nil end
  return factorissimo.portal_distance(fs, fp, ts, tp)
end

return factorissimo
