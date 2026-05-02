local base = require("script/depot_base")

local fuel_amount_per_drone = shared.fuel_amount_per_drone
local channels_match = base.channels_match

local dispatcher_depot = {}
dispatcher_depot.metatable = {__index = dispatcher_depot}

-- Quality order: highest first for distribution, lowest first for returns
local quality_order_desc = {"legendary", "epic", "rare", "uncommon", "normal"}
local quality_order_asc = {"normal", "uncommon", "rare", "epic", "legendary"}

-- Depot categories that have drone inventories
local drone_categories = {"request", "buffer", "fuel", "active"}

dispatcher_depot.corpse_offsets =
{
  [defines.direction.north] = {0, -2},
  [defines.direction.east] = {2, 0},
  [defines.direction.south] = {0, 2},
  [defines.direction.west] = {-2, 0},
}

base.mixin(dispatcher_depot)

function dispatcher_depot.new(entity, tags)
  local position = entity.position
  local force = entity.force
  local surface = entity.surface
  entity.destructible = false
  entity.rotatable = false
  entity.active = false

  local quality_level = entity.quality and entity.quality.level or 0
  local chest_name = shared.dispatcher_chest_name[quality_level] or "drone-dispatcher-chest"
  local chest = surface.create_entity{name = chest_name, position = position, force = force, player = entity.last_user}

  -- Set all inventory slots to only accept transport-drone
  local inv = chest.get_inventory(defines.inventory.chest)
  for i = 1, #inv do
    inv.set_filter(i, {name = "transport-drone", quality = "normal", comparator = ">="})
  end

  -- Lock second half of inventory for drone returns
  local player_slots = shared.quality_dispatcher_player_slots[quality_level] or 10
  inv.set_bar(player_slots + 1)

  local depot =
  {
    entity = chest,
    assembler = entity,
    index = tostring(chest.unit_number),
    player_slots = player_slots,
    priority = shared.default_priority,
    base_priority = shared.default_priority,
    channel = shared.default_channel,
    base_channel = shared.default_channel,
    fuel_on_the_way = 0,
    drones = {}
  }
  setmetatable(depot, dispatcher_depot.metatable)

  depot:get_corpse()
  depot:read_tags(tags)

  return depot
end

-- Override get_corpse_position to use assembler instead of entity
function dispatcher_depot:get_corpse_position()
  local position = self.assembler.position
  local offset = self.corpse_offsets[self.assembler.direction]
  return {position.x + offset[1], position.y + offset[2]}
end

function dispatcher_depot:read_tags(tags)
  local ttags = base.read_base_tags(self, tags)
  if not ttags then return end
  if ttags.central_dispatch_enabled ~= nil then
    self.central_dispatch_enabled = ttags.central_dispatch_enabled
  end
  if ttags.central_dispatch_percent then
    self.central_dispatch_percent = ttags.central_dispatch_percent
  end
end

function dispatcher_depot:save_to_blueprint_tags()
  local tags = base.save_base_tags(self) or {}
  if self.central_dispatch_enabled then
    tags.central_dispatch_enabled = true
  end
  if self.central_dispatch_percent and self.central_dispatch_percent ~= 50 then
    tags.central_dispatch_percent = self.central_dispatch_percent
  end
  if not next(tags) then return end
  return tags
end

function dispatcher_depot:register_active_drone(d)
  self.drones[d.index] = d
  self._active_count = (self._active_count or 0) + 1
end

function dispatcher_depot:unregister_active_drone(key)
  if self.drones[key] then
    self.drones[key] = nil
    self._active_count = math.max((self._active_count or 1) - 1, 0)
  end
end

function dispatcher_depot:remove_drone(drone)
  -- Central dispatch drones had their item physically removed at dispatch time.
  -- Re-insert it now that the drone is returning.
  if drone.central_dispatch then
    local inv = self.entity.get_inventory(defines.inventory.chest)
    if inv then
      local bar = self.player_slots or 10
      local quality = drone.quality or "normal"
      local inserted = false
      -- Try stacking onto existing matching stack past bar
      for i = bar + 1, #inv do
        if inv[i].valid_for_read and inv[i].name == "transport-drone"
           and inv[i].quality.name == quality and inv[i].count < inv[i].prototype.stack_size then
          inv[i].count = inv[i].count + 1
          inserted = true
          break
        end
      end
      -- Try empty slot past bar
      if not inserted then
        for i = bar + 1, #inv do
          if not inv[i].valid_for_read then
            inv[i].set_stack{name = "transport-drone", count = 1, quality = quality}
            inserted = true
            break
          end
        end
      end
      -- Fall back to stacking in player slots
      if not inserted then
        for i = 1, bar do
          if inv[i].valid_for_read and inv[i].name == "transport-drone"
             and inv[i].quality.name == quality and inv[i].count < inv[i].prototype.stack_size then
            inv[i].count = inv[i].count + 1
            inserted = true
            break
          end
        end
      end
      -- Fall back to empty player slot
      if not inserted then
        for i = 1, bar do
          if not inv[i].valid_for_read then
            inv[i].set_stack{name = "transport-drone", count = 1, quality = quality}
            inserted = true
            break
          end
        end
      end
      -- Last resort: spill on ground
      if not inserted then
        self.entity.surface.spill_item_stack{
          position = self.entity.position,
          stack = {name = "transport-drone", count = 1, quality = quality},
          force = self.entity.force
        }
      end
    end
  end
  self:unregister_active_drone(drone.index)
end

function dispatcher_depot:get_fuel_amount()
  return self.assembler.get_fluid_count(base.get_fuel_fluid())
end

function dispatcher_depot:remove_fuel(amount)
  self.assembler.remove_fluid({name = base.get_fuel_fluid(), amount = amount})
end

function dispatcher_depot:receive_fuel(amount)
  if amount > 0 then
    base.insert_fuel(self.assembler, amount)
  elseif amount < 0 then
    self.assembler.remove_fluid({name = base.get_fuel_fluid(), amount = -amount})
  end
end

local max = math.max
local min = math.min

function dispatcher_depot:minimum_fuel_amount()
  return max(fuel_amount_per_drone * 2, fuel_amount_per_drone * self:get_drone_item_count() * 0.2)
end

function dispatcher_depot:max_fuel_amount()
  local target = self:get_drone_item_count() * fuel_amount_per_drone
  local capacity = self.assembler.fluidbox.get_capacity(1)
  return min(target, capacity)
end

local fuel_icon_param = {type = "virtual", name = "fuel-signal"}
function dispatcher_depot:show_fuel_alert(message)
  for k, player in pairs(game.connected_players) do
    player.add_custom_alert(self.entity, fuel_icon_param, message, true)
  end
end

function dispatcher_depot:check_fuel_amount()
  if self:get_drone_item_count() == 0 then return end

  local current_amount = self:get_fuel_amount()
  if current_amount >= self:minimum_fuel_amount() then
    return
  end

  local fuel_request_amount = (self:max_fuel_amount() - current_amount)
  if fuel_request_amount <= self.fuel_on_the_way then return end

  local fuel_depots = self.road_network.get_depots_by_distance(self.network_id, "fuel", self.node_position, self.entity.surface_index)
  if not (fuel_depots and fuel_depots[1]) then
    self:show_fuel_alert({"no-fuel-depot-on-network"})
    return
  end

  for k = 1, #fuel_depots do
    local depot = fuel_depots[k]
    if channels_match(self.channel, depot.channel) then
      depot:handle_fuel_request(self)
      if fuel_request_amount <= self.fuel_on_the_way then
        return
      end
    end
  end

  self:show_fuel_alert({"no-fuel-in-network"})
end

-- Remove 1 drone from inventory, preferring return slots (after bar) first.
-- Returns the quality of the removed drone, or nil if none found.
function dispatcher_depot:remove_drone_from_inventory(inv, quality)
  local size = #inv
  local bar = inv.supports_bar() and inv.get_bar() or (size + 1)
  -- Scan return slots first (after bar), then user slots (before bar)
  for i = size, bar, -1 do
    local stack = inv[i]
    if stack.valid_for_read and stack.name == "transport-drone" and stack.quality.name == quality then
      if stack.count > 1 then
        stack.count = stack.count - 1
      else
        stack.clear()
      end
      return quality
    end
  end
  for i = bar - 1, 1, -1 do
    local stack = inv[i]
    if stack.valid_for_read and stack.name == "transport-drone" and stack.quality.name == quality then
      if stack.count > 1 then
        stack.count = stack.count - 1
      else
        stack.clear()
      end
      return quality
    end
  end
  return nil
end

function dispatcher_depot:distribute_drones()
  -- Cooldown: at most 1 dispatch per 30 ticks (0.5 seconds)
  local tick = game.tick
  if self.last_dispatch_tick and tick - self.last_dispatch_tick < 30 then
    return -- _needs_dispatch unchanged
  end

  if not self.network_id then self._needs_dispatch = false return end

  local network = self.road_network.get_network_by_id(self.network_id)
  if not network then self._needs_dispatch = false return end

  if self:get_fuel_amount() < fuel_amount_per_drone then self._needs_dispatch = false return end

  -- Yield to higher-priority dispatchers on the same network that still have drones
  local dispatchers = network.depots.dispatcher
  if dispatchers then
    for _, other in pairs(dispatchers) do
      if other ~= self and other.entity.valid and (other.priority or shared.default_priority) > (self.priority or shared.default_priority)
         and channels_match(self.channel, other.channel) then
        local other_inv = other.entity.get_inventory(defines.inventory.chest)
        if other_inv then
          for _, item in pairs(other_inv.get_contents()) do
            if item.name == "transport-drone" then
              -- Higher-priority dispatcher has drones, yield
              self._needs_dispatch = true
              return
            end
          end
        end
      end
    end
  end

  -- Phase 1: Try to distribute drones to needy depots
  local inv = self.entity.get_inventory(defines.inventory.chest)
  if inv then
    local available = {}
    local total_available = 0
    for _, item in pairs(inv.get_contents()) do
      if item.name == "transport-drone" then
        available[item.quality] = (available[item.quality] or 0) + item.count
        total_available = total_available + item.count
      end
    end

    if total_available > 0 then
      local needy = {}
      for _, category in ipairs(drone_categories) do
        local depots = network.depots[category]
        if depots then
          for _, depot in pairs(depots) do
            if depot.entity.valid and depot.requested_drones and depot.requested_drones > 0
               and channels_match(self.channel, depot.channel) then
              depot._drone_count_cache = nil
              local current = depot:get_drone_item_count() + (depot.drones_on_the_way or 0)
              local deficit = depot.requested_drones - current
              if deficit > 0 then
                needy[#needy + 1] = {depot = depot, deficit = deficit, priority = depot.priority or shared.default_priority}
              end
            end
          end
        end
      end

      if #needy > 0 then
        table.sort(needy, function(a, b) return a.priority > b.priority end)
        for _, entry in ipairs(needy) do
          local depot = entry.depot
          for _, quality in ipairs(quality_order_desc) do
            local qty = available[quality]
            if qty and qty > 0 then
              if self:remove_drone_from_inventory(inv, quality) then
                depot.drones_on_the_way = (depot.drones_on_the_way or 0) + 1
                local drone = self.transport_drone.new(self, nil, quality)
                if drone then
                  self:register_active_drone(drone)
                  drone:deliver_drone_to(depot, quality)
                  self:remove_fuel(fuel_amount_per_drone)
                else
                  inv.insert{name = "transport-drone", count = 1, quality = quality}
                  depot.drones_on_the_way = math.max(0, (depot.drones_on_the_way or 0) - 1)
                end
                self.last_dispatch_tick = tick
                self._needs_dispatch = true
                return
              end
            end
          end
        end
      end
    end
  end

  -- Phase 2: Try to collect excess drones from depots
  if self:collect_excess_drone(network) then
    self.last_dispatch_tick = tick
    self._needs_dispatch = true
    return
  end

  self._needs_dispatch = false
end

function dispatcher_depot:collect_excess_drone(network)
  -- Check dispatcher chest has room (include filtered slots in count)
  local inv = self.entity.get_inventory(defines.inventory.chest)
  if not inv or inv.count_empty_stacks(true, true) == 0 then return false end
  if self:get_fuel_amount() < fuel_amount_per_drone then return false end

  for _, category in ipairs(drone_categories) do
    local depots = network.depots[category]
    if depots then
      for _, depot in pairs(depots) do
        if depot.entity.valid and depot.requested_drones ~= nil
           and channels_match(self.channel, depot.channel) then
          depot._drone_count_cache = nil
          local projected = depot:get_drone_item_count() + (depot.drones_on_the_way or 0)
          if projected > depot.requested_drones and depot:get_drone_item_count() > 0 then
            -- Find the quality of the drone to return (lowest quality first)
            local drone_inv = depot:get_drone_inventory()
            for _, quality in ipairs(quality_order_asc) do
              local count = drone_inv.get_item_count({name = "transport-drone", quality = quality})
              if count > 0 then
                -- Remove 1 drone from depot inventory
                drone_inv.remove{name = "transport-drone", count = 1, quality = quality}
                depot._drone_count_cache = nil
                depot.drones_returning = (depot.drones_returning or 0) + 1

                -- Create return drone entity at the depot's position
                local drone = self.transport_drone.new(self, nil, quality, depot)
                if drone then
                  self:register_active_drone(drone)
                  drone:return_drone_to(self, depot, quality)
                  self:remove_fuel(fuel_amount_per_drone)
                else
                  -- Failed to create entity, return item to depot
                  drone_inv.insert{name = "transport-drone", count = 1, quality = quality}
                  depot._drone_count_cache = nil
                  depot.drones_returning = math.max(0, (depot.drones_returning or 0) - 1)
                end
                return true
              end
            end
          end
        end
      end
    end
  end
  return false
end

function dispatcher_depot:get_drone_inventory()
  return self.entity.get_inventory(defines.inventory.chest)
end

function dispatcher_depot:get_max_storage_size()
  local proto = prototypes.item["transport-drone"]
  return self.player_slots * (proto and proto.stack_size or 100)
end

function dispatcher_depot:get_drone_item_count()
  local inv = self.entity.get_inventory(defines.inventory.chest)
  if not inv then return 0 end
  local total = 0
  for _, item in pairs(inv.get_contents()) do
    if item.name == "transport-drone" then
      total = total + item.count
    end
  end
  return total
end

function dispatcher_depot:update_sticker()
  if self.rendering and self.rendering.valid then
    self.rendering.text = self:get_active_drone_count().."/"..self:get_drone_item_count()
    return
  end

  self.rendering = rendering.draw_text
  {
    surface = self.assembler.surface.index,
    target = self.assembler,
    text = self:get_active_drone_count().."/"..self:get_drone_item_count(),
    only_in_alt_mode = true,
    forces = {self.assembler.force},
    color = {r = 1, g = 1, b = 1},
    alignment = "center",
    scale = 1.5
  }
end

function dispatcher_depot:get_active_drone_count()
  if not self.drones then return 0 end
  if self._active_count == nil then
    self._active_count = table_size(self.drones)
  end
  return self._active_count
end

function dispatcher_depot:update_circuit_reader()
  if not (self.circuit_reader and self.circuit_reader.valid) then return end

  local behavior = self.circuit_reader.get_or_create_control_behavior()
  local section = behavior.get_section(1)
  if not section then section = behavior.add_section() end

  -- Slot 1: transport-drone item signal (supports depot/network/network-excl modes)
  if not self:update_circuit_reader_network("transport-drone", "item", self:get_drone_item_count()) then
    section.set_slot(1, {value = {type = "item", name = "transport-drone", quality = "normal"}, min = self:get_drone_item_count()})
  end

  -- Slot 2+: extra signals (drones, active, capacity, etc.)
  local slot = self:write_reader_extra_signals(section, 2)
  for i = slot, section.filters_count do section.clear_slot(i) end
end

-- Accept items from a returning central dispatch drone that failed delivery.
-- Spills items on the ground near the dispatcher.
function dispatcher_depot:take_item(name, count, temperature, spoil_percent, quality)
  if not (name and count and count > 0) then return end
  local insert_def = {name = name, count = count}
  if quality and quality ~= "normal" then insert_def.quality = quality end
  if spoil_percent and spoil_percent > 0 then
    insert_def.spoil_percent = spoil_percent
  end
  self.entity.surface.spill_item_stack{
    position = self.entity.position,
    stack = insert_def,
    force = self.entity.force
  }
end

-- Central dispatch categories: depot types that may need item delivery
local central_categories = {"request", "buffer", "storage"}

function dispatcher_depot:get_central_dispatch_active_count()
  if not self.drones then return 0 end
  local count = 0
  for _, drone in pairs(self.drones) do
    if drone.central_dispatch then
      count = count + 1
    end
  end
  return count
end

local floor = math.floor
local min = math.min
local big = math.huge
local random = math.random

local item_heuristic_bonus = 50

local central_heuristic = function(depot, count, request_size, minimum_size, priority_weight, node_pos, surface_idx, portal_dist)
  if depot.is_buffer_depot then return big end
  if depot.set_storage_filter then return big end
  local amount = min(count, request_size)
  if amount < minimum_size then return big end
  local priority = depot.priority or shared.default_priority
  local bonus = depot.score_bonus or 0
  local dist = base.effective_distance(depot, node_pos, surface_idx, portal_dist)
  if priority_weight == 0 then
    return -priority * 1000000 + dist - ((amount / request_size) * item_heuristic_bonus) - bonus
  else
    return -priority * priority_weight + dist - ((amount / request_size) * item_heuristic_bonus) - bonus
  end
end

-- Reusable scratch arrays for candidate sorting (same pattern as depot_base)
local _c_depots = {}
local _c_indices = {}
local _c_scores = {}

function dispatcher_depot:central_dispatch_items()
  if not self.central_dispatch_enabled then return end

  -- Share cooldown with distribute_drones
  local tick = game.tick
  if self.last_dispatch_tick and tick - self.last_dispatch_tick < 30 then
    return
  end

  if not self.network_id then return end

  local network = self.road_network.get_network_by_id(self.network_id)
  if not network then return end

  if self:get_fuel_amount() < fuel_amount_per_drone then return end

  -- Calculate available drones for central dispatch
  local percent = self.central_dispatch_percent or 50
  local total_in_inv = self:get_drone_item_count()
  local max_central = floor(total_in_inv * percent / 100)
  local active_central = self:get_central_dispatch_active_count()
  if active_central >= max_central then return end

  local get_depot = self.get_depot
  local my_channel = self.channel
  local priority_weight, balance_threshold = base.get_dispatch_settings()

  for _, category in ipairs(central_categories) do
    local depots = network.depots[category]
    if depots then
      for _, depot in pairs(depots) do
        local target_item = depot.item or depot.storage_filter_item
        local target_quality = depot.item_quality
        if depot.entity.valid and target_item
           and depot.allow_central_dispatch ~= false
           and channels_match(my_channel, depot.channel) then
          -- Skip depots that can self-serve (have own drones + fuel)
          if depot.get_drone_item_count and depot.get_fuel_amount then
            local own_drones = depot:get_drone_item_count() - depot:get_active_drone_count()
            if own_drones > 0 and depot:get_fuel_amount() >= fuel_amount_per_drone then
              goto next_depot
            end
          end
          local capacity
          if depot.get_push_capacity then
            capacity = depot:get_push_capacity()
          elseif depot.get_push_capacity_for_item then
            capacity = depot:get_push_capacity_for_item(target_item)
          end
          if capacity and capacity > 0 then

          -- Found a depot with push capacity - find best supply using heuristic
          local supply_key = shared.supply_key(target_item, target_quality)
          local supply_depots = self.road_network.get_supply_depots(self.network_id, supply_key)
          if supply_depots then
            local request_size
            if depot.get_request_size then
              request_size = min(depot:get_request_size(), capacity)
            elseif depot.get_request_size_for_item then
              request_size = min(depot:get_request_size_for_item(target_item), capacity)
            else
              request_size = capacity
            end
            local minimum_size = depot.get_minimum_request_size and depot:get_minimum_request_size() or 1
            local node_pos = depot.node_position
            local surface_idx = depot.entity.surface_index
            local portal_dist = self.road_network.portal_distance

            -- Score all supply depots (same pattern as make_request_from_supply)
            local candidate_count = 0
            for depot_index, count in pairs(supply_depots) do
              if count >= minimum_size then
                local supply = get_depot(depot_index)
                if supply and supply.allow_central_dispatch ~= false and channels_match(my_channel, supply.channel) then
                  local score = central_heuristic(supply, count, request_size, minimum_size, priority_weight, node_pos, surface_idx, portal_dist)
                  if score < big then
                    candidate_count = candidate_count + 1
                    _c_depots[candidate_count] = supply
                    _c_indices[candidate_count] = depot_index
                    _c_scores[candidate_count] = score
                  end
                end
              end
            end

            if candidate_count > 0 then
              -- Sort candidates by score (ascending = best first)
              for i = 2, candidate_count do
                local key_d, key_i, key_s = _c_depots[i], _c_indices[i], _c_scores[i]
                local j = i - 1
                while j > 0 and _c_scores[j] > key_s do
                  _c_depots[j+1] = _c_depots[j]
                  _c_indices[j+1] = _c_indices[j]
                  _c_scores[j+1] = _c_scores[j]
                  j = j - 1
                end
                _c_depots[j+1] = key_d
                _c_indices[j+1] = key_i
                _c_scores[j+1] = key_s
              end

              -- Load balancing: pick random start among eligible candidates
              local ci = 1
              if balance_threshold > 0 and candidate_count > 1 then
                local threshold = _c_scores[1] + balance_threshold
                local eligible = 1
                for i = 2, candidate_count do
                  if _c_scores[i] <= threshold then
                    eligible = i
                  else
                    break
                  end
                end
                if eligible > 1 then
                  ci = random(1, eligible)
                end
              end

              local best_supply = _c_depots[ci]
              local best_index = _c_indices[ci]
              local best_count = supply_depots[best_index] or 0

              -- Cleanup candidate arrays
              for i = 1, candidate_count do
                _c_depots[i] = nil
                _c_indices[i] = nil
                _c_scores[i] = nil
              end

              -- Dispatch a drone from the dispatcher's inventory
              local inv = self.entity.get_inventory(defines.inventory.chest)
              if not inv then return end

              local drone_quality = nil
              for _, quality in ipairs(quality_order_desc) do
                if self:remove_drone_from_inventory(inv, quality) then
                  drone_quality = quality
                  break
                end
              end
              if not drone_quality then return end

              local send = min(request_size, best_count, capacity)

              -- Reserve items_on_the_way on target depot NOW so it won't
              -- dispatch its own drones for the same items while we're en route
              depot.items_on_the_way = (depot.items_on_the_way or 0) + send

              local drone = self.transport_drone.new(self, target_item, drone_quality)
              if drone then
                drone.central_dispatch = true
                drone.target_depot = depot
                drone.central_dispatch_reserved = send
                self:register_active_drone(drone)
                drone:pickup_from_supply(best_supply, target_item, send, target_quality)
                self:remove_fuel(fuel_amount_per_drone)
              else
                -- Failed to create entity, undo reservation and return drone item
                depot.items_on_the_way = (depot.items_on_the_way or 0) - send
                inv.insert{name = "transport-drone", count = 1, quality = drone_quality}
              end

              self.last_dispatch_tick = tick
              self._needs_dispatch = true
              return
            end

            -- Cleanup on no candidates
            for i = 1, candidate_count do
              _c_depots[i] = nil
              _c_indices[i] = nil
              _c_scores[i] = nil
            end
          end
          end
        end
        ::next_depot::
      end
    end
  end
end

function dispatcher_depot:update()
  self:update_priority_from_circuit()
  self:update_channel_from_circuit()
  self:update_disabled_visual()
  self:check_fuel_amount()

  -- Enforce inventory bar (player cannot change locked slots)
  local inv = self.entity.get_inventory(defines.inventory.chest)
  local expected_bar = self.player_slots + 1
  if inv and inv.get_bar() ~= expected_bar then
    inv.set_bar(expected_bar)
  end

  -- Clean up invalid delivery drones
  if self.drones then
    for k, drone in pairs(self.drones) do
      if not drone.entity or not drone.entity.valid then
        if drone.clear_drone_data then
          drone:clear_drone_data()
        end
        self:unregister_active_drone(k)
      end
    end
  end

  if not base.is_writer_disabled(self) then
    self:distribute_drones()
    self:central_dispatch_items()
  else
    self._needs_dispatch = false
  end

  self:update_circuit_reader()
  self:update_sticker()
end

function dispatcher_depot:add_to_network()
  self.network_id = self.road_network.add_depot(self, "dispatcher")
end

function dispatcher_depot:remove_from_network()
  self.road_network.remove_depot(self, "dispatcher")
  self.network_id = nil
end

function dispatcher_depot:on_removed(event)
  if self.rendering and self.rendering.valid then
    self.rendering:destroy()
  end

  -- Kill active delivery drones
  if self.drones then
    for _, drone in pairs(self.drones) do
      if drone.entity and drone.entity.valid then
        drone:clear_drone_data()
        drone.entity.destroy()
      end
    end
    self.drones = {}
  end

  if self.circuit_reader and self.circuit_reader.valid then
    if storage.reader_config then storage.reader_config[self.circuit_reader.unit_number] = nil end
    self.circuit_reader.destroy()
  end

  if self.circuit_writer and self.circuit_writer.valid then
    if storage.writer_config then storage.writer_config[self.circuit_writer.unit_number] = nil end
    self.circuit_writer.destroy()
  end

  if self.corpse and self.corpse.valid then
    self.corpse.destroy()
  end

  if self.entity.valid then
    base.return_inventory(self.entity, event)
    self.entity.destroy()
  end

  if self.assembler and self.assembler.valid then
    self.assembler.destructible = true
    if event.name == defines.events.on_entity_died then
      self.assembler.die()
    else
      self.assembler.destroy()
    end
  end
end

return dispatcher_depot
