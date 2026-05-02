local shared = require("shared")
local transport_technologies = require("script/transport_technologies")
local factorissimo = require("script/factorissimo")

local fuel_amount_per_drone = shared.fuel_amount_per_drone
local fuel_consumption_per_meter = shared.fuel_consumption_per_meter
local drone_pollution_per_second = shared.drone_pollution_per_second

-- Quality bonuses: indexed by quality level (0=normal, 1=uncommon, 2=rare, 3=epic, 5=legendary)
local quality_speed_bonus = {[0] = 0, [1] = 0.15, [2] = 0.3, [3] = 0.5, [5] = 0.8}
local quality_fuel_multiplier = {[0] = 1, [1] = 0.90, [2] = 0.80, [3] = 0.70, [5] = 0.55}

local script_data =
{
  drones = {},
  riding_players = {},
  reset_to_be_taken_again = true,
  reset_fuel_on_the_way = true
}

local depot_base = require("script/depot_base")
local get_fuel_fluid = depot_base.get_fuel_fluid
local insert_fuel = depot_base.insert_fuel

local transport_drone = {}

transport_drone.metatable = {__index = transport_drone}

local add_drone = function(drone)
  script_data.drones[drone.index] = drone
end

local remove_drone = function(drone)
  script_data.drones[drone.index] = nil
end

local get_drone = function(index)

  local drone = script_data.drones[index]

  if not drone then
    return
  end

  if not drone.entity.valid then
    drone:clear_drone_data()
    return
  end

  return drone

end


local states =
{
  going_to_supply = 1,
  return_to_requester = 2,
  delivering_fuel = 4,
  delivering_item = 5,
  delivering_drones = 6,
  returning_drones = 7
}

-- State dispatch table: target depot field, fallback on failure, and update handler
local state_info = {
  [states.going_to_supply]     = {target = "supply_depot", fallback = "return", handler = "process_pickup"},
  [states.delivering_fuel]     = {target = "target_depot", fallback = "return", handler = "process_deliver_fuel"},
  [states.delivering_item]     = {target = "target_depot", fallback = "return", handler = "process_deliver_item"},
  [states.delivering_drones]   = {target = "target_depot", fallback = "suicide", handler = "process_deliver_drones"},
  [states.returning_drones]    = {target = "request_depot", fallback = "suicide", handler = "process_return_drones"},
  [states.return_to_requester] = {target = "request_depot", fallback = "suicide", handler = "process_return_to_requester"},
}

local get_drone_speed = function(force_index)
  return (0.066 * (1 + transport_technologies.get_transport_speed_bonus(force_index)))
end

local variation_count = shared.variation_count
local special_variation_count = shared.special_variation_count
local random = math.random

local is_drone_cache = {}
local is_special_drone = function(name)
  local bool = is_drone_cache[name]
  if bool ~= nil then
    return bool
  end
  bool = prototypes.entity["transport-drone-"..name.."-1"] ~= nil
  is_drone_cache[name] = bool
  return bool
end

local get_drone_name = function(item_name)
  if item_name then
    if is_special_drone(item_name) then
      return "transport-drone-"..item_name.."-"..random(special_variation_count)
    end
  end
  return "transport-drone-"..random(variation_count)
end


local player_leave_drone = function(player)

  local drone = script_data.riding_players[player.index]
  if not drone then return end

  script_data.riding_players[player.index] = nil
  drone.riding_player = nil
  drone:update_speed()

end

local player_enter_drone = function(player, drone)

  script_data.riding_players[player.index] = drone
  drone.riding_player = player.index
  drone:update_speed()

end


transport_drone.new = function(request_depot, drone_name, drone_quality, spawn_at)

  local spawn_depot = spawn_at or request_depot
  local corpse = spawn_depot.corpse
  if not (corpse and corpse.valid) then
    if spawn_depot.get_corpse then
      corpse = spawn_depot:get_corpse()
    end
  end
  if not (corpse and corpse.valid) then
    error("No corpse found")
  end

  local entity = spawn_depot.entity.surface.create_entity{name = get_drone_name(drone_name), position = corpse.position, force = request_depot.entity.force, quality = drone_quality or "normal"}
  if not (entity and entity.valid) then return end

  local drone =
  {
    entity = entity,
    request_depot = request_depot,
    index = tostring(entity.unit_number),
    state = 0,
    requested_count = 0,
    tick_created = game.tick,
    quality = drone_quality or "normal"
  }
  setmetatable(drone, transport_drone.metatable)
  add_drone(drone)

  return drone
end

function transport_drone:update_speed()
  local speed = get_drone_speed(self.entity.force.index)
  local quality_level = self.entity.quality and self.entity.quality.level or 0
  if quality_level > 0 then
    speed = speed * (1 + (quality_speed_bonus[quality_level] or 0))
  end
  if self.riding_player then
    speed = speed * 1.5
  elseif self.fuel_amount then
    speed = speed * 0.6
  elseif self.held_item then
    speed = speed * 0.75
  elseif self.drone_delivery_quality then
    speed = speed * 0.75
  elseif self.drone_return_quality then
    speed = speed * 0.75
  end
  self.entity.speed = speed
end

function transport_drone:add_slow_sticker()
  self.entity.surface.create_entity{name = "drone-slowdown-sticker", position = self.entity.position, target = self.entity, force = "neutral"}
end

function transport_drone:pickup_from_supply(supply, item, count, quality)

  if not supply.entity.valid then
    self:return_to_requester()
    return
  end

  self.supply_depot = supply
  self.requested_count = count
  self.requested_item = item
  self.requested_quality = quality or "normal"
  local key = shared.supply_key(item, quality)
  self.supply_depot:add_to_be_taken(key, count)

  self:add_slow_sticker()
  self:update_speed()
  self.state = states.going_to_supply

  self:go_to_depot(self.supply_depot)

end

function transport_drone:deliver_fuel(depot, amount)

  if not depot.entity.valid then
    self:return_to_requester()
    return
  end

  self.target_depot = depot
  self.fuel_amount = amount
  self.state = states.delivering_fuel
  self.target_depot.fuel_on_the_way = (self.target_depot.fuel_on_the_way or 0) + amount

  self:add_slow_sticker()
  self:update_speed()
  self:update_sticker()

  self:go_to_depot(self.target_depot)

end

function transport_drone:deliver_item(depot, item, count, spoil_percent, quality)

  if not depot.entity.valid then
    self:return_to_requester()
    return
  end

  self.target_depot = depot
  self.held_item = item
  self.held_count = count
  self.held_quality = quality
  self.held_spoil_percent = spoil_percent
  self.state = states.delivering_item

  self:add_slow_sticker()
  self:update_speed()
  self:update_sticker()

  self:go_to_depot(self.target_depot)

end

function transport_drone:process_deliver_item()

  if self.target_depot.entity.valid then
    self.target_depot:take_item(self.held_item, self.held_count, self.held_temperature, self.held_spoil_percent, self.held_quality)
    self:clear_reservations()
  end

  self.held_item = nil
  self.held_count = nil
  self.held_quality = nil
  self.held_spoil_percent = nil

  self:add_slow_sticker()
  self:update_speed()
  self:return_to_requester()

end

function transport_drone:deliver_drone_to(target_depot, drone_quality)

  if not target_depot.entity.valid then
    self:suicide()
    return
  end

  self.target_depot = target_depot
  self.drone_delivery_quality = drone_quality
  self.state = states.delivering_drones

  self:add_slow_sticker()
  self:update_speed()
  self:update_sticker()

  self:go_to_depot(self.target_depot)

end

function transport_drone:process_deliver_drones()

  if self.target_depot and self.target_depot.entity.valid and self.drone_delivery_quality then
    local drone_inv = self.target_depot:get_drone_inventory()
    drone_inv.insert{name = "transport-drone", count = 1, quality = self.drone_delivery_quality}
    self.target_depot._drone_count_cache = nil
  end

  self.drone_delivery_quality = nil

  self.request_depot:remove_drone(self)
  self:clear_drone_data()
  self.entity.destroy()

end

function transport_drone:return_drone_to(dispatcher, source_depot, drone_quality)

  if not dispatcher.entity.valid then
    self:suicide()
    return
  end

  self.return_source = source_depot
  self.drone_return_quality = drone_quality
  self.state = states.returning_drones

  self:add_slow_sticker()
  self:update_speed()
  self:update_sticker()

  self:go_to_depot(self.request_depot)

end

function transport_drone:process_return_drones()

  -- Insert drone item into dispatcher chest (prefer locked slots past bar, stack properly)
  if self.request_depot and self.request_depot.entity.valid and self.drone_return_quality then
    local inv = self.request_depot.entity.get_inventory(defines.inventory.chest)
    if inv then
      local bar = self.request_depot.player_slots or 10
      local quality = self.drone_return_quality
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
        self.request_depot.entity.surface.spill_item_stack{
          position = self.request_depot.entity.position,
          stack = {name = "transport-drone", count = 1, quality = quality},
          force = self.request_depot.entity.force
        }
      end
    end
  end

  self.drone_return_quality = nil

  self.request_depot:remove_drone(self)
  self:clear_drone_data()
  self.entity.destroy()

end

function transport_drone:retry_command()

  local distance = 1.5

  local surface = self.entity.surface
  if not surface.can_place_entity
  {
    name = self.entity.name,
    position = self.entity.position,
    build_check_type=defines.build_check_type.manual
  } then
    local position = self.entity.surface.find_non_colliding_position(self.entity.name, self.entity.position, 5, 0.25, false)
    if position then
      self.entity.teleport(position)
    end
  end

  local info = state_info[self.state]
  if not info then return end

  local depot = self[info.target]
  if depot and depot.entity.valid then
    self:go_to_depot(depot, distance)
  elseif info.fallback == "return" then
    self:return_to_requester()
  else
    self:suicide()
  end

end

function transport_drone:process_failed_command()

  if (self.failed_command_count or 0) < 2 then
    self.failed_command_count = (self.failed_command_count or 0) + 1
    self:say("R")
    self:retry_command()
    return
  end

  self:say("F")

  local info = state_info[self.state]
  if not info then return end

  if info.fallback == "return" then
    self:return_to_requester()
  else
    self:suicide()
  end

end

local distance = util.distance
function transport_drone:distance(position)
  return distance(self.entity.position, position)
end

local min = math.min
function transport_drone:process_pickup()

  -- For central dispatch drones, the "requester" is the dispatcher (no .item).
  -- Validate against target_depot instead.
  local ref_depot = self.central_dispatch and self.target_depot or self.request_depot

  local ref_item = ref_depot and (ref_depot.item or ref_depot.storage_filter_item)

  if not ref_depot or not ref_depot.entity.valid or not ref_item then
    self:return_to_requester()
    return
  end

  if self.requested_item ~= ref_item then
    self:return_to_requester()
    return
  end

  if not self.supply_depot.entity.valid then
    self:return_to_requester()
    return
  end

  local available_count = self.requested_count + self.supply_depot:get_available_item_count(ref_item, self.requested_quality)

  local to_take
  if not ref_depot.circuit_limit then
    -- No circuit limit, pickup as much as we can
    local request_size
    if ref_depot.get_request_size then
      request_size = ref_depot:get_request_size()
    elseif ref_depot.get_request_size_for_item then
      request_size = ref_depot:get_request_size_for_item(ref_item)
    else
      request_size = available_count
    end
    to_take = min(available_count, request_size)
  else
    -- We want to only take what we requested.
    to_take = self.requested_count
  end

  if to_take > 0 then
    local temperature = self.supply_depot.get_temperature and self.supply_depot:get_temperature()
    local given_count, spoil_percent = self.supply_depot:give_item(self.requested_item, to_take, self.requested_quality)

    if given_count > 0 then
      self.held_item = self.requested_item
      self.held_count = given_count
      self.held_quality = self.requested_quality
      self.held_temperature = temperature
      self.held_spoil_percent = spoil_percent
      self:update_sticker()
    end
  end

  -- Central dispatch: deliver to target depot instead of returning home
  if self.central_dispatch and self.target_depot then
    -- Adjust the reservation made at dispatch time to match actual pickup
    local reserved = self.central_dispatch_reserved or 0
    local actual = self.held_count or 0
    if reserved ~= actual and self.target_depot.entity.valid then
      self.target_depot.items_on_the_way = (self.target_depot.items_on_the_way or 0) + (actual - reserved)
    end
    self.central_dispatch_reserved = nil

    -- Clear supply reservation - items have been picked up.
    -- Must do this now because the state change below skips clear_reservations().
    if self.supply_depot and self.supply_depot.entity.valid and self.requested_item then
      local key = shared.supply_key(self.requested_item, self.requested_quality)
      self.supply_depot:add_to_be_taken(key, -self.requested_count)
      self.requested_item = nil
      self.requested_count = nil
      self.requested_quality = nil
    end

    if self.target_depot.entity.valid and self.held_item then
      self.state = states.delivering_item
      self:add_slow_sticker()
      self:update_speed()
      self:go_to_depot(self.target_depot)
      return
    end
    -- Target gone or nothing picked up - clear reservation, fall through to return home
    if self.target_depot.entity.valid then
      self.target_depot.items_on_the_way = math.max(0, (self.target_depot.items_on_the_way or 0) - actual)
    end
  end

  self:add_slow_sticker()
  self:update_speed()
  self:return_to_requester()

end

function transport_drone:process_deliver_fuel()

  if self.target_depot.entity.valid then
    self.target_depot:receive_fuel(self.fuel_amount)
    self:clear_reservations()
    self.fuel_amount = nil
  end

  self:add_slow_sticker()
  self:update_speed()
  self:return_to_requester()

end

function transport_drone:clear_reservations()

  if self.state == states.going_to_supply then
    if self.supply_depot and self.supply_depot.entity.valid and self.requested_item then
      local key = shared.supply_key(self.requested_item, self.requested_quality)
      self.supply_depot:add_to_be_taken(key, -self.requested_count)
      self.requested_item = nil
      self.requested_count = nil
      self.requested_quality = nil
    end
    -- Central dispatch: undo early reservation on target depot
    if self.central_dispatch_reserved and self.target_depot and self.target_depot.entity.valid then
      self.target_depot.items_on_the_way = math.max(0, (self.target_depot.items_on_the_way or 0) - self.central_dispatch_reserved)
      self.central_dispatch_reserved = nil
    end
  end

  if self.state == states.delivering_fuel then
    if self.target_depot and self.target_depot.entity.valid and self.fuel_amount then
      self.target_depot.fuel_on_the_way = self.target_depot.fuel_on_the_way - self.fuel_amount
    end
  end

  if self.state == states.delivering_item then
    if self.target_depot and self.target_depot.entity.valid and self.held_count then
      self.target_depot.items_on_the_way = (self.target_depot.items_on_the_way or 0) - self.held_count
    end
  end

  if self.state == states.delivering_drones then
    -- Return drone item to dispatcher
    if self.request_depot and self.request_depot.entity.valid and self.drone_delivery_quality then
      local inv = self.request_depot.entity.get_inventory(defines.inventory.chest)
      if inv then
        inv.insert{name = "transport-drone", count = 1, quality = self.drone_delivery_quality}
      end
    end
    -- Decrement on_the_way
    if self.target_depot and self.target_depot.entity.valid then
      self.target_depot.drones_on_the_way = math.max(0, (self.target_depot.drones_on_the_way or 0) - 1)
    end
    self.drone_delivery_quality = nil
  end

  if self.state == states.returning_drones then
    -- Return drone item to source depot
    if self.return_source and self.return_source.entity.valid and self.drone_return_quality then
      local drone_inv = self.return_source:get_drone_inventory()
      if drone_inv then
        drone_inv.insert{name = "transport-drone", count = 1, quality = self.drone_return_quality}
        self.return_source._drone_count_cache = nil
      end
    end
    -- Decrement drones_returning
    if self.return_source and self.return_source.entity.valid then
      self.return_source.drones_returning = math.max(0, (self.return_source.drones_returning or 0) - 1)
    end
    self.drone_return_quality = nil
  end

end

function transport_drone:return_to_requester()

  self:clear_reservations()

  if not self.request_depot.entity.valid then
    self:suicide()
    return
  end

  self:update_sticker()

  self.state = states.return_to_requester

  self:go_to_depot(self.request_depot)

end

local is_valid_item = depot_base.is_valid_item
local is_valid_fluid = depot_base.is_valid_fluid

function transport_drone:draw_sticker(sprite)
  local surface = self.entity.surface
  local offset = self.entity.prototype.sticker_box.left_top

  self.background_rendering = rendering.draw_sprite
  {
    sprite = "utility/entity_info_dark_background",
    target = self.entity,
    target_offset = offset,
    surface = surface,
    only_in_alt_mode = true,
    x_scale = 0.6,
    y_scale = 0.6,
  }

  self.item_rendering = rendering.draw_sprite
  {
    sprite = sprite,
    target = self.entity,
    target_offset = offset,
    surface = surface,
    only_in_alt_mode = true,
    x_scale = 0.6,
    y_scale = 0.6,
  }
end

function transport_drone:update_sticker()


  if self.background_rendering then
    self.background_rendering:destroy()
    self.background_rendering = nil
  end

  if self.item_rendering then
    self.item_rendering:destroy()
    self.item_rendering = nil
  end

  if self.held_item then

    local sprite
    if is_valid_fluid(self.held_item) then
      sprite = "fluid/"..self.held_item
    elseif is_valid_item(self.held_item) then
      sprite = "item/"..self.held_item
    end

    self:draw_sticker(sprite)
  end

  if self.fuel_amount then
    self:draw_sticker("fluid/"..get_fuel_fluid())
  end

  if self.drone_delivery_quality or self.drone_return_quality then
    self:draw_sticker("item/transport-drone")
  end

end

function transport_drone:suicide()
  self:say("S")

  self:clear_drone_data()

  if self.request_depot.entity.valid then
    self.request_depot:remove_drone(self)
  end
  self.entity.force = "neutral"
  self.entity.die()
end

function transport_drone:process_return_to_requester()

  if not self.request_depot.entity.valid then
    self:suicide()
    return
  end

  if self.held_item then
    self.request_depot:take_item(self.held_item, self.held_count, self.held_temperature, self.held_spoil_percent, self.held_quality)
    self.held_item = nil
    self.held_quality = nil
    self.held_spoil_percent = nil
  end

  if self.fuel_amount then
    self.request_depot:receive_fuel(self.fuel_amount)
    self.fuel_amount = nil
  end

  self:refund_fuel()
  self:remove_from_depot()

end


function transport_drone:refund_fuel()
  local age = game.tick - (self.tick_created or game.tick - 1)
  local quality_level = self.entity.quality and self.entity.quality.level or 0
  local fuel_mult = quality_fuel_multiplier[quality_level] or 1
  local consumption = age * self.entity.speed * fuel_consumption_per_meter * fuel_mult

  local pollution = (age / 60) * drone_pollution_per_second
  game.get_pollution_statistics(self.entity.surface).on_flow("transport-drone-1", pollution)

  self.entity.force.get_fluid_production_statistics(self.entity.surface_index).on_flow(get_fuel_fluid(), -consumption)
  local fuel_refund = fuel_amount_per_drone - consumption

  if fuel_refund ~= 0 then
    self.request_depot:receive_fuel(fuel_refund)
  end

end

function transport_drone:remove_from_depot()

  self.request_depot:remove_drone(self)
  self:clear_drone_data()
  self.entity.destroy()

end

function transport_drone:process_portal_transit()
  local target_depot = self.portal_target_depot
  if not (target_depot and target_depot.entity and target_depot.entity.valid) then
    self.portal_in_transit = nil
    self.portal_target_depot = nil
    self.portal_target_radius = nil
    self:return_to_requester()
    return
  end

  local path = factorissimo.find_portal_path(self.entity.surface_index, target_depot.entity.surface_index, {target_depot.entity.position.x, target_depot.entity.position.y}, {self.entity.position.x, self.entity.position.y})
  if not path or #path == 0 then
    self.portal_in_transit = nil
    self.portal_target_depot = nil
    self.portal_target_radius = nil
    self:return_to_requester()
    return
  end

  local step = path[1]
  local exit_surface_idx, exit_x, exit_y = factorissimo.get_exit(step.portal, step.direction)
  local exit_surface = game.surfaces[exit_surface_idx]
  if not exit_surface then
    self.portal_in_transit = nil
    self.portal_target_depot = nil
    self.portal_target_radius = nil
    self:return_to_requester()
    return
  end

  -- Unit entities can't cross-surface teleport; destroy and recreate on exit surface
  local old_entity = self.entity
  local drone_name = old_entity.name
  local force = old_entity.force
  local quality = old_entity.quality and old_entity.quality.name or "normal"

  -- Find valid position on exit surface
  local pos = {exit_x, exit_y}
  local alt_pos = exit_surface.find_non_colliding_position(drone_name, pos, 3, 0.25)
  if alt_pos then pos = alt_pos end

  -- Create new entity on exit surface
  local new_entity = exit_surface.create_entity{
    name = drone_name,
    position = pos,
    force = force,
    quality = quality
  }
  if not new_entity then
    self.portal_in_transit = nil
    self.portal_target_depot = nil
    self.portal_target_radius = nil
    self:suicide()
    return
  end

  -- Swap entity reference: unregister old, destroy old, register new
  local old_index = self.index
  remove_drone(self)
  old_entity.destroy()
  self.entity = new_entity
  self.index = tostring(new_entity.unit_number)
  add_drone(self)

  -- Update depot's drone table (keyed by index)
  if self.request_depot and self.request_depot.drones then
    self.request_depot.drones[old_index] = nil
    self.request_depot.drones[self.index] = self
  end

  -- Teleport riding player if present
  if self.riding_player then
    local player = game.get_player(self.riding_player)
    if player then
      player.teleport(pos, exit_surface)
    end
  end

  -- Re-apply speed and sticker on new entity
  self:update_speed()
  self:add_slow_sticker()
  self:update_sticker()

  -- Continue to target depot or next portal
  if self.entity.surface_index == target_depot.entity.surface_index then
    local radius = self.portal_target_radius
    self.portal_in_transit = nil
    self.portal_target_depot = nil
    self.portal_target_radius = nil
    self:go_to_depot(target_depot, radius)
  else
    self:navigate_to_next_portal()
  end
end

function transport_drone:update(event)
  if not self.entity.valid then return end

  if event.result ~= defines.behavior_result.success then
    self:process_failed_command()
    return
  end

  if self.failed_command_count then
    self.failed_command_count = nil
  end

  -- Handle portal traversal (Factorissimo cross-surface)
  if self.portal_in_transit then
    self:process_portal_transit()
    return
  end

  local info = state_info[self.state]
  if info then
    self[info.handler](self)
  end

end

function transport_drone:say(text)
  rendering.draw_text{text = text, surface = self.entity.surface, target = self.entity.position, color = {1, 1, 1}, time_to_live = 120, scale = 1.5}
end


local drone_path_flags = {prefer_straight_paths = true, cache = true, low_priority = true}
local insert = table.insert

function transport_drone:navigate_to_next_portal()
  local target_depot = self.portal_target_depot
  if not (target_depot and target_depot.entity.valid) then
    self.portal_in_transit = nil
    self.portal_target_depot = nil
    self.portal_target_radius = nil
    self:return_to_requester()
    return
  end

  local path = factorissimo.find_portal_path(self.entity.surface_index, target_depot.entity.surface_index, {target_depot.entity.position.x, target_depot.entity.position.y}, {self.entity.position.x, self.entity.position.y})
  if not path or #path == 0 then
    self.portal_in_transit = nil
    self.portal_target_depot = nil
    self.portal_target_radius = nil
    self:return_to_requester()
    return
  end

  local step = path[1]
  local entry_corpse = factorissimo.get_entry_corpse(step.portal, self.entity.surface_index)
  if not (entry_corpse and entry_corpse.valid) then
    self.portal_in_transit = nil
    self.portal_target_depot = nil
    self.portal_target_radius = nil
    self:return_to_requester()
    return
  end

  local commands = {}
  insert(commands, {
    type = defines.command.go_to_location,
    destination_entity = entry_corpse,
    distraction = defines.distraction.none,
    radius = 0.5,
    pathfind_flags = drone_path_flags
  })
  insert(commands, {
    type = defines.command.stop,
    distraction = defines.distraction.none,
    ticks_to_wait = 15
  })
  self.entity.commandable.set_command{
    type = defines.command.compound,
    distraction = defines.distraction.none,
    structure_type = defines.compound_command.return_last,
    commands = commands
  }
end

function transport_drone:go_to_depot(depot, radius)
  -- Cross-surface navigation via Factorissimo portals
  if factorissimo.is_active() and self.entity.surface_index ~= depot.entity.surface_index then
    local path = factorissimo.find_portal_path(self.entity.surface_index, depot.entity.surface_index, {depot.entity.position.x, depot.entity.position.y}, {self.entity.position.x, self.entity.position.y})
    if path and #path > 0 then
      self.portal_target_depot = depot
      self.portal_target_radius = radius
      self.portal_in_transit = true
      self:navigate_to_next_portal()
      return
    end
  end
  self.portal_in_transit = nil
  self.portal_target_depot = nil
  self.portal_target_radius = nil

  local commands = {}
  local corpse = depot.corpse

  if not (corpse and corpse.valid) then
    if depot.get_corpse then
      corpse = depot:get_corpse()
    end
  end

  if not (corpse and corpse.valid) then
    self:suicide()
    return
  end

  insert(commands,
  {
    type = defines.command.go_to_location,
    destination_entity = corpse,
    distraction = defines.distraction.none,
    radius = radius or 0.5,
    pathfind_flags = drone_path_flags
  })

  insert(commands,
  {
    type = defines.command.stop,
    distraction = defines.distraction.none,
    ticks_to_wait = 15
  })

  self.entity.commandable.set_command
  {
    type = defines.command.compound,
    distraction = defines.distraction.none,
    structure_type = defines.compound_command.return_last,
    commands = commands
  }

end

function transport_drone:clear_drone_data()

  self:clear_reservations()

  self.portal_in_transit = nil
  self.portal_target_depot = nil
  self.portal_target_radius = nil

  if self.riding_player then
    local player = game.get_player(self.riding_player)
    if player then player_leave_drone(player) end
  end

  remove_drone(self)
end

function transport_drone:handle_drone_deletion()
  if self.entity.valid then
    self:say("D")
  end

  self:clear_drone_data()

  if self.request_depot.entity.valid then
    self.request_depot:remove_drone(self, true)
  end

end

local on_ai_command_completed = function(event)
  local drone = get_drone(tostring(event.unit_number))
  if not drone then return end
  drone:update(event)
end

local on_entity_removed = function(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end

  local unit_number = entity.unit_number
  if not unit_number then return end

  local drone = get_drone(tostring(unit_number))
  if not drone then return end

  if event.force then
    entity.force.get_kill_count_statistics(entity.surface_index).on_flow("transport-drone-1", 1)
    event.force.get_kill_count_statistics(entity.surface_index).on_flow("transport-drone-1", -1)
  end

  drone:handle_drone_deletion()


end

local follow_drone_hotkey = function(event)
  local player = game.get_player(event.player_index)

  if script_data.riding_players[player.index] then
    player_leave_drone(player)
    return
  end

  if player.vehicle then
    --He is getting out of a vehicle.
    return
  end

  local radius = player.character and player.character.prototype.enter_vehicle_distance or 5

  if player.surface.count_entities_filtered{type = "car", force = player.force, position = player.position, radius = radius, limit = 1} > 0 then
    --There is a vehicle nearby, let him get into that.
    return
  end

  local units = player.surface.find_entities_filtered{type = "unit", force = player.force, position = player.position, radius = radius}

  for k, unit in pairs (units) do
    local drone = get_drone(tostring(unit.unit_number))
    if not drone then
      units[k] = nil
    elseif drone.riding_player then
      units[k] = nil
    end
  end

  if not next(units) then return end

  local closest = player.surface.get_closest(player.position, units)
  if not closest then return end

  local drone = get_drone(tostring(closest.unit_number))
  player_enter_drone(player, drone)

end

local floor = math.floor
local to_direction = function(orientation)
  local direction = floor(16 * (orientation + (1 / 32)))
  if direction >= 16 then direction = 0 end
  return direction
end


local get_orientation = function(source_position, target_position)

  -- Angle in rads
  local angle = util.angle(target_position, source_position)

  -- Convert to orientation
  local orientation =  (angle / (2 * math.pi)) - 0.25
  if orientation < 0 then orientation = orientation + 1 end

  return orientation

end

local smoothing = 0.20
local sticker_offset_cache = {}

local on_tick = function(event)
  if not next(script_data.riding_players) then return end
  local players = game.players
  for player_index, drone in pairs (script_data.riding_players) do
    local player = players[player_index]
    if player and player.valid then
      if drone.entity and drone.entity.valid then

        local player_position = player.position
        local position = drone.entity.position

        local drone_name = drone.entity.name
        local shift = sticker_offset_cache[drone_name]
        if not shift then
          local box = drone.entity.prototype.sticker_box
          shift = {x = box.left_top.x, y = box.left_top.y}
          sticker_offset_cache[drone_name] = shift
        end

        local target_x = position.x + shift.x
        local target_y = position.y + shift.y
        local dx = (target_x - player_position.x) * smoothing
        local dy = (target_y - player_position.y) * smoothing

        local final_x = player_position.x + dx
        local final_y = player_position.y + dy
        player.teleport({final_x, final_y})
        if player.character then
          player.character.direction = to_direction(get_orientation(player_position, {final_x, final_y}))
        end
      end
    end
  end
end

local set_map_settings = function()
  game.map_settings.path_finder.max_steps_worked_per_tick = settings.global["transport-drone-pathfinder-max-steps"].value
  game.map_settings.path_finder.max_work_done_per_tick = settings.global["transport-drone-pathfinder-max-work"].value
  game.map_settings.path_finder.use_path_cache = settings.global["transport-drone-pathfinder-use-cache"].value
end

transport_drone.events =
{
  --[defines.events.on_built_entity] = on_built_entity,
  --[defines.events.on_robot_built_entity] = on_built_entity,
  --[defines.events.script_raised_revive] = on_built_entity,
  --[defines.events.script_raised_built] = on_built_entity,

  [defines.events.on_player_mined_entity] = on_entity_removed,
  [defines.events.on_robot_mined_entity] = on_entity_removed,

  [defines.events.on_entity_died] = on_entity_removed,
  [defines.events.script_raised_destroy] = on_entity_removed,

  [defines.events.on_ai_command_completed] = on_ai_command_completed,

  ["follow-drone"] = follow_drone_hotkey,
  [defines.events.on_tick] = on_tick,
  [defines.events.on_runtime_mod_setting_changed] = function(event)
    set_map_settings()
  end,
}

transport_drone.on_load = function()
  script_data = storage.transport_drone or script_data
  for unit_number, drone in pairs (script_data.drones) do
    setmetatable(drone, transport_drone.metatable)
  end
end

transport_drone.on_init = function()
  storage.transport_drone = storage.transport_drone or script_data
  set_map_settings()
end

transport_drone.on_configuration_changed = function()
  for k, drone in pairs (script_data.drones) do
    if drone.entity.valid then
      drone.portal_in_transit = nil
      drone.portal_target_depot = nil
      drone.portal_target_radius = nil
      if drone.state == states.going_to_supply then
        local count = drone.requested_count or 0
        local item = drone.requested_item or (drone.target_depot and drone.target_depot.item) or drone.request_depot.item
        drone:pickup_from_supply(drone.supply_depot, item, count)
      end
      if drone.state == states.delivering_fuel then
        drone.target_depot.fuel_on_the_way = drone.target_depot.fuel_on_the_way + (drone.fuel_amount or 0)
      end
      if drone.state == states.delivering_item then
        if drone.target_depot and drone.target_depot.entity.valid then
          drone.target_depot.items_on_the_way = (drone.target_depot.items_on_the_way or 0) + (drone.held_count or 0)
        end
      end
      if drone.state == states.delivering_drones then
        if drone.target_depot and drone.target_depot.entity.valid then
          drone.target_depot.drones_on_the_way = (drone.target_depot.drones_on_the_way or 0) + 1
        end
      end
      if drone.state == states.returning_drones then
        if drone.return_source and drone.return_source.entity.valid then
          drone.return_source.drones_returning = (drone.return_source.drones_returning or 0) + 1
        end
      end
    else
      script_data.drones[k] = nil
    end
  end

  set_map_settings()

end

transport_drone.get_drone = get_drone

transport_drone.get_drone_count = function()
  return table_size(script_data.drones)
end

transport_drone.get_all_drones = function()
  return script_data.drones
end

return transport_drone
