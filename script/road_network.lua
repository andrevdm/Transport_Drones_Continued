local shared = require("shared")

local script_data =
{
  networks = {},
  id_number = 0,
  node_map = {}
}


local new_id = function()
  script_data.id_number = script_data.id_number + 1
  local id = script_data.id_number
  script_data.networks[id] =
  {
    item_supply = {},
    depots = {}
  }
  --print("New network "..id)
  return id
end

local get_network_by_id = function(id)
  return script_data.networks[id]
end

local neighbor_offsets =
{
  {-1, 0},
  {1, 0},
  {0, -1},
  {0, 1},

  {-1, -1},
  {1, -1},
  {1, 1},
  {-1, 1},

}

local get_node = function(surface, x, y)
  local surface_map = script_data.node_map[surface]
  if not surface_map then return end

  local x_map = surface_map[x]
  if not x_map then return end

  return x_map[y]

end

-- Diagonal validity: at least one adjacent cardinal tile must be road (prevent corner-cutting)
local check_diagonals = settings.startup["transport-drones-diagonal-check"].value
local diagonal_ok = function(surface, x, y, dx, dy)
  if not check_diagonals then return true end
  if dx == 0 or dy == 0 then return true end
  return get_node(surface, x + dx, y) ~= nil or get_node(surface, x, y + dy) ~= nil
end

local get_neighbors = function(surface, x, y)
  local neighbors = {}

  for k, offset in pairs (neighbor_offsets) do
    local node = get_node(surface, x + offset[1], y + offset[2])
    if node and diagonal_ok(surface, x, y, offset[1], offset[2]) then
      neighbors[k] = node
    end
  end

  return neighbors

end

local get_neighbor_count = function(surface, x, y)
  local count = 0
  for k, offset in pairs (neighbor_offsets) do
    if get_node(surface, x + offset[1], y + offset[2])
       and diagonal_ok(surface, x, y, offset[1], offset[2]) then
      count = count + 1
    end
  end
  return count
end


local accumulate_nodes = function(surface, x, y)

  local nodes = {}
  local new_nodes = {}

  local root_node = get_node(surface, x, y)
  nodes[root_node] = true
  new_nodes[root_node] = {x, y}

  local neighbor_offsets = neighbor_offsets
  local get_node = get_node
  local next = next
  local pairs = pairs

  while true do
    local node, node_position = next(new_nodes)
    if not node then break end
    new_nodes[node] = nil
    local px, py = node_position[1], node_position[2]
    for k, offset in pairs (neighbor_offsets) do
      local dx, dy = offset[1], offset[2]
      local nx, ny = px + dx, py + dy
      local neighbor = get_node(surface, nx, ny)
      if neighbor and (dx == 0 or dy == 0 or get_node(surface, px + dx, py) or get_node(surface, px, py + dy)) then
        if not nodes[neighbor] then
          nodes[neighbor] = true
          new_nodes[neighbor] = {nx, ny}
        end
      end
    end
  end

  return nodes

end

local symmetric_connection_check = function(surface, x1, y1, x2, y2)
  --Because most often, 1 road network is significantly smaller, so this will reduce search time.

  local nodes_1 = {}
  local new_nodes_1 = {}

  local root_node_1 = get_node(surface, x1, y1)
  nodes_1[root_node_1] = true
  new_nodes_1[root_node_1] = {x1, y1}

  local nodes_2 = {}
  local new_nodes_2 = {}

  local root_node_2 = get_node(surface, x2, y2)
  nodes_2[root_node_2] = true
  new_nodes_2[root_node_2] = {x2, y2}


  local neighbor_offsets = neighbor_offsets
  local get_node = get_node
  local diagonal_ok = diagonal_ok
  local next = next
  local pairs = pairs

  while true do

    local node, node_position = next(new_nodes_1)
    if not node then break end

    new_nodes_1[node] = nil
    local px, py = node_position[1], node_position[2]
    for k, offset in pairs (neighbor_offsets) do
      local nx, ny = px + offset[1], py + offset[2]
      local neighbor = get_node(surface, nx, ny)
      if neighbor and diagonal_ok(surface, px, py, offset[1], offset[2]) then

        if nodes_2[neighbor] then return true end

        if not nodes_1[neighbor] then
          nodes_1[neighbor] = true
          new_nodes_1[neighbor] = {nx, ny}
        end
      end
    end

    local node, node_position = next(new_nodes_2)
    if not node then break end

    new_nodes_2[node] = nil
    local px, py = node_position[1], node_position[2]
    for k, offset in pairs (neighbor_offsets) do
      local nx, ny = px + offset[1], py + offset[2]
      local neighbor = get_node(surface, nx, ny)
      if neighbor and diagonal_ok(surface, px, py, offset[1], offset[2]) then

        if nodes_1[neighbor] then return true end

        if not nodes_2[neighbor] then
          nodes_2[neighbor] = true
          new_nodes_2[neighbor] = {nx, ny}
        end
      end
    end

  end

  return false

end

local accumulate_smaller_node = function(surface, x1, y1, x2, y2)

  --returns the smaller of the 2 node groups.

  -- Portal-linked networks span multiple surfaces; surface-local BFS undercounts them.
  -- Always treat a portal-linked network as the larger one to prevent clearing it.
  local root_node_1 = get_node(surface, x1, y1)
  local root_node_2 = get_node(surface, x2, y2)
  local net_1 = script_data.networks[root_node_1.id]
  local net_2 = script_data.networks[root_node_2.id]
  if net_1 and net_1.portal_linked and not (net_2 and net_2.portal_linked) then
    return accumulate_nodes(surface, x2, y2) -- return group 2 as "smaller"
  end
  if net_2 and net_2.portal_linked and not (net_1 and net_1.portal_linked) then
    return accumulate_nodes(surface, x1, y1) -- return group 1 as "smaller"
  end

  local nodes_1 = {}
  local new_nodes_1 = {}

  nodes_1[root_node_1] = true
  new_nodes_1[root_node_1] = {x1, y1}

  local nodes_2 = {}
  local new_nodes_2 = {}

  nodes_2[root_node_2] = true
  new_nodes_2[root_node_2] = {x2, y2}


  local neighbor_offsets = neighbor_offsets
  local get_node = get_node
  local diagonal_ok = diagonal_ok
  local next = next
  local pairs = pairs

  while true do

    local node, node_position = next(new_nodes_1)
    if not node then return nodes_1 end

    new_nodes_1[node] = nil
    local px, py = node_position[1], node_position[2]
    for k, offset in pairs (neighbor_offsets) do
      local nx, ny = px + offset[1], py + offset[2]
      local neighbor = get_node(surface, nx, ny)
      if neighbor and diagonal_ok(surface, px, py, offset[1], offset[2]) then
        if not nodes_1[neighbor] then
          nodes_1[neighbor] = true
          new_nodes_1[neighbor] = {nx, ny}
        end
      end
    end

    local node, node_position = next(new_nodes_2)
    if not node then return nodes_2 end

    new_nodes_2[node] = nil
    local px, py = node_position[1], node_position[2]
    for k, offset in pairs (neighbor_offsets) do
      local nx, ny = px + offset[1], py + offset[2]
      local neighbor = get_node(surface, nx, ny)
      if neighbor and diagonal_ok(surface, px, py, offset[1], offset[2]) then
        if not nodes_2[neighbor] then
          nodes_2[neighbor] = true
          new_nodes_2[neighbor] = {nx, ny}
        end
      end
    end

  end

end


local set_node_ids = function(nodes, id)

  --print("Setting nodes "..id)

  for node, bool in pairs (nodes) do
    node.id = id

    if node.depots then
      for k, depot in pairs (node.depots) do
        depot:remove_from_network()
        if depot.entity.valid then
          depot:add_to_network()
        end
      end
    end
  end

end



local clear_network = function(id)
  --print("Clearing "..id)
  local network = script_data.networks[id]

  if not network then return end

  -- Portal-linked networks span multiple surfaces; removing a tile on one
  -- surface doesn't mean the whole network is empty. Let reset() handle it.
  if network.portal_linked then return end

  for category, depots in pairs (network.depots) do
    for id, depot in pairs (depots) do
      depot:remove_from_network()
      depot:add_to_network()
    end
  end

  script_data.networks[id] = nil
end


local road_network = {}

road_network.get_network_item_supply = function(id)
  local network = get_network_by_id(id)
  if not network then return {} end
  return network.item_supply
end

road_network.get_supply_depots = function(id, name)
  local network = get_network_by_id(id)
  if not network then return nil end
  return network.item_supply[name]
end

road_network.add_node = function(surface, x, y)

  local node = get_node(surface, x, y)
  if node then
    --Eh... maybe I should error?
    return
  end

  local new_node_id
  local rx, ry
  local checked = {}

  for k, offset in pairs (neighbor_offsets) do
    local fx, fy = x + offset[1], y + offset[2]
    local neighbor = get_node(surface, fx, fy)
    if neighbor and diagonal_ok(surface, x, y, offset[1], offset[2]) then
      if not new_node_id then
        new_node_id = neighbor.id
        rx, ry = fx, fy
      elseif neighbor.id ~= new_node_id then
        local smaller_node_set = accumulate_smaller_node(surface, rx, ry, fx, fy)
        local smaller_id = next(smaller_node_set).id
        if smaller_id == new_node_id then
          new_node_id = neighbor.id
          rx, ry = fx, fy
        end
      end
    end
  end

  for k, offset in pairs (neighbor_offsets) do
    local fx, fy = x + offset[1], y + offset[2]
    local neighbor = get_node(surface, fx, fy)
    if neighbor and diagonal_ok(surface, x, y, offset[1], offset[2]) then
      local neighbor_id = neighbor.id
      if neighbor_id ~= new_node_id then
        local nodes = accumulate_nodes(surface, fx, fy)
        set_node_ids(nodes, new_node_id)
        clear_network(neighbor_id)
      end
    end
  end

  local surface_map = script_data.node_map[surface]
  if not surface_map then
    surface_map = {}
    script_data.node_map[surface] = surface_map
  end

  local x_map = surface_map[x]
  if not x_map then
    x_map = {}
    surface_map[x] = x_map
  end

  if not new_node_id then
    new_node_id = new_id()
  end

  x_map[y] =
  {
    id = new_node_id
  }

end

road_network.remove_node = function(surface, x, y)


  local node = get_node(surface, x, y)
  if not node then return end

  --print("Removing node "..serpent.line({node.id, x, y}))

  if node.depots and next(node.depots) then
    return true
  end

  script_data.node_map[surface][x][y] = nil

  local count = get_neighbor_count(surface, x, y)

  if count == 0 then
    -- No neighbors, clear the network.
    clear_network(node.id)
    return
  end

  if count == 1 then
    -- only 1 neighbor, no need to worry about anything.
    return
  end

  -- we could be splitting neighbors.
  -- Check every neighbor against every other neighbor

  local node_id = node.id

  local checked = {}
  for k, offset in pairs(neighbor_offsets) do

    checked[k] = true

    local fx, fy = x + offset[1], y + offset[2]
    local neighbor = get_node(surface, fx, fy)

    if neighbor and diagonal_ok(surface, x, y, offset[1], offset[2]) then
      if neighbor.id == node_id then
        for j, offset in pairs(neighbor_offsets) do
          if not checked[j] and diagonal_ok(surface, x, y, offset[1], offset[2]) then
            local nx, ny = x + offset[1], y + offset[2]
            local other_neighbor = get_node(surface, nx, ny)
            if other_neighbor and other_neighbor.id == neighbor.id then
              if not symmetric_connection_check(surface, fx, fy, nx, ny) then
                local smaller_node_set = accumulate_smaller_node(surface, fx, fy, nx, ny)
                set_node_ids(smaller_node_set, new_id())
              end
            end
          end
        end
      end
    end

  end

end

road_network.get_network = function(surface, x, y)
  local node = get_node(surface, x, y)
  if not node then return end

  return get_network_by_id(node.id)
end

road_network.add_depot = function(depot, category)
  local x, y = depot.node_position[1], depot.node_position[2]
  local surface = depot.entity.surface.index
  local node = get_node(surface, x, y)

  local network = get_network_by_id(node.id)
  if not network then
    -- Network entry was removed by portal merge; recreate it
    script_data.networks[node.id] = {item_supply = {}, depots = {}}
    network = script_data.networks[node.id]
  end

  if not network.depots[category] then network.depots[category] = {} end
  network.depots[category][depot.index] = depot

  return node.id
end

road_network.remove_depot = function(depot, category)
  --local x, y = depot.node_position[1], depot.node_position[2]
  --local surface = depot.entity.surface.index
  --local node = get_node(surface, x, y)
  --local network = get_network_by_id(node.id)

  local network_id = depot.network_id
  if not network_id then return end

  local network = get_network_by_id(network_id)
  if not network then return end

  if depot.old_contents then
    local item_supply = network.item_supply
    for name, count in pairs (depot.old_contents) do
      if item_supply[name] then
        item_supply[name][depot.index] = nil
      end
    end
  end

  if network.depots[category] then
    network.depots[category][depot.index] = nil
  end

end

local distance_squared = function(a, b)
  local dx = a[1] - b[1]
  local dy = a[2] - b[2]
  return (dx * dx) + (dy * dy)
end

local sort = table.sort

local floor = math.floor

local get_tiles = function()
  local tiles = {}
  for name, tile in pairs (prototypes.tile) do
    if tile.collision_mask and tile.collision_mask.layers and tile.collision_mask.layers["transport_drone_road"] then
      table.insert(tiles, name)
    end
  end
  return tiles
end

local reset = function()

  local profiler = game.create_profiler()

  script_data.node_map = {}
  script_data.networks = {}
  script_data.id_number = 0

  local tile_names = get_tiles()
  if not next(tile_names) then
    error("NO ROAD TILES? Something if fishy! Aborting loading to prevent save corruption.")
  end

  -- Phase 1: Build node_map without network assignment
  local node_map = script_data.node_map
  for surface_index, surface in pairs (game.surfaces) do
    local index = surface.index
    local tiles = surface.find_tiles_filtered{name = tile_names}
    local surface_map = node_map[index]
    if not surface_map then
      surface_map = {}
      node_map[index] = surface_map
    end
    for k, tile in pairs (tiles) do
      local pos = tile.position
      local x, y = pos.x, pos.y
      local x_map = surface_map[x]
      if not x_map then
        x_map = {}
        surface_map[x] = x_map
      end
      x_map[y] = {id = 0}
    end
  end

  -- Phase 2: BFS to assign network IDs to connected components
  local neighbor_offsets = neighbor_offsets
  for surface, surface_map in pairs (node_map) do
    for x, x_map in pairs (surface_map) do
      for y, node in pairs (x_map) do
        if node.id == 0 then
          local network_id = new_id()
          node.id = network_id
          local queue = {{x, y}}
          local head = 1
          while head <= #queue do
            local pos = queue[head]
            head = head + 1
            local px, py = pos[1], pos[2]
            for k = 1, 8 do
              local offset = neighbor_offsets[k]
              local dx, dy = offset[1], offset[2]
              local nx, ny = px + dx, py + dy
              local neighbor = get_node(surface, nx, ny)
              if neighbor and neighbor.id == 0
                 and (dx == 0 or dy == 0 or get_node(surface, px + dx, py) or get_node(surface, px, py + dy)) then
                neighbor.id = network_id
                queue[#queue + 1] = {nx, ny}
              end
            end
          end
        end
      end
    end
  end

  -- Phase 3: Merge portal-connected networks (Factorissimo cross-surface links)
  if road_network.portal_link_provider then
    local links = road_network.portal_link_provider()
    if links then
      for _, link in pairs(links) do
        local n1 = get_node(link[1], link[2], link[3])
        local n2 = get_node(link[4], link[5], link[6])
        if n1 and n2 and n1.id ~= 0 and n2.id ~= 0 and n1.id ~= n2.id then
          local old_id = n2.id
          local target_id = n1.id
          for s, sm in pairs(node_map) do
            for x, xm in pairs(sm) do
              for y, node in pairs(xm) do
                if node.id == old_id then
                  node.id = target_id
                end
              end
            end
          end
          script_data.networks[old_id] = nil
          local target_net = script_data.networks[target_id]
          if target_net then target_net.portal_linked = true end
        end
      end
    end
  end

  log({"", "Reset road network - ", profiler})

end


local _dist_sort_position
local _dist_sort_surface
local get_effective_distance = function(depot)
  if _dist_sort_surface and road_network.portal_distance
     and depot.entity.valid and depot.entity.surface_index ~= _dist_sort_surface then
    return road_network.portal_distance(
      _dist_sort_surface, _dist_sort_position,
      depot.entity.surface_index, depot.node_position)
      or distance_squared(depot.node_position, _dist_sort_position) ^ 0.5
  end
  return distance_squared(depot.node_position, _dist_sort_position) ^ 0.5
end

local distance_sort_function = function(depot_a, depot_b)
  local pa = depot_a.priority or shared.default_priority
  local pb = depot_b.priority or shared.default_priority
  if pa ~= pb then return pa > pb end
  return get_effective_distance(depot_a) < get_effective_distance(depot_b)
end

road_network.get_depots_by_distance = function(id, category, node_position, surface_index)
  local network = get_network_by_id(id)
  if not network then return end
  local depots = network.depots[category]
  if not depots then return end

  local to_sort = {}
  local i = 1
  for k, v in pairs (depots) do
    to_sort[i] = v
    i = i + 1
  end

  _dist_sort_position = node_position
  _dist_sort_surface = surface_index
  sort(to_sort, distance_sort_function)
  return to_sort
end

road_network.check_clear_lonely_node = function(surface, x, y)
  if next(get_neighbors(surface, x, y)) then
    -- We have a neighbor, do nothing.
    return
  end

  if road_network.remove_node(surface, x, y) then
    --depot on it or something
    return
  end

  local surface = game.surfaces[surface]
  local position = {x, y}

  local hidden = surface.get_hidden_tile(position)
  if hidden then
    surface.set_tiles
    {
      {
        name = hidden,
        position = position
      }
    }
  end

end

road_network.on_init = function()
  storage.road_network = storage.road_network or script_data
end

road_network.on_load = function()
  script_data = storage.road_network or script_data
end

road_network.on_configuration_changed = function()

  reset()

end

road_network.get_network_by_id = get_network_by_id
road_network.get_node = get_node
road_network.get_networks = function()
  return script_data.networks
end

-- Merge two network components across surfaces (for Factorissimo portals)
road_network.merge_portal_link = function(s1, x1, y1, s2, x2, y2)
  local n1 = get_node(s1, x1, y1)
  local n2 = get_node(s2, x2, y2)
  if not n1 or not n2 then return false end
  if n1.id == n2.id then return true end -- already same network

  local old_id = n2.id
  local target_id = n1.id

  -- Remap all nodes with old_id to target_id
  local node_map = script_data.node_map
  for s, sm in pairs(node_map) do
    for x, xm in pairs(sm) do
      for y, node in pairs(xm) do
        if node.id == old_id then
          node.id = target_id
        end
      end
    end
  end

  -- Merge network depot/supply data
  local old_net = script_data.networks[old_id]
  local new_net = script_data.networks[target_id]
  if old_net and new_net then
    for cat, depots in pairs(old_net.depots) do
      if not new_net.depots[cat] then new_net.depots[cat] = {} end
      for id, depot in pairs(depots) do
        new_net.depots[cat][id] = depot
        depot.network_id = target_id
      end
    end
    for name, supplies in pairs(old_net.item_supply) do
      if not new_net.item_supply[name] then new_net.item_supply[name] = {} end
      for id, depot in pairs(supplies) do
        new_net.item_supply[name][id] = depot
      end
    end
  end
  script_data.networks[old_id] = nil
  if new_net then new_net.portal_linked = true end

  return true
end

-- Callback for Factorissimo portal links (set by factorissimo.lua)
road_network.portal_link_provider = nil

return road_network