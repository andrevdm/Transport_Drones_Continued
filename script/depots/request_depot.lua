local base = require("script/depot_base")

local request_depot = {}
request_depot.metatable = {__index = request_depot}

request_depot.corpse_offsets =
{
  [defines.direction.north] = {0, -2},
  [defines.direction.east] = {2, 0},
  [defines.direction.south] = {0, 2},
  [defines.direction.west] = {-2, 0},
}

base.mixin(request_depot, "drone", "requester")

local request_mode = base.request_mode
local is_valid_item = base.is_valid_item
local is_valid_fluid = base.is_valid_fluid

function request_depot.new(entity, tags)

  local force = entity.force
  local surface = entity.surface

  entity.active = false
  entity.rotatable = false

  local drone_chest = base.create_drone_chest(entity)

  local depot =
  {
    entity = entity,
    drone_chest = drone_chest,
    index = tostring(entity.unit_number),
    item = false,
    item_quality = "normal",
    drones = {},
    mode = request_mode.item,
    fuel_on_the_way = 0,
    items_on_the_way = 0,
    priority = shared.default_priority,
    base_priority = shared.default_priority,
    channel = shared.default_channel,
    base_channel = shared.default_channel
  }
  setmetatable(depot, request_depot.metatable)

  depot:get_corpse()
  depot:read_tags(tags)

  return depot

end

function request_depot:get_output_inventory()
  if not self.output_inventory then
    self.output_inventory = self.entity.get_output_inventory()
  end
  return self.output_inventory
end

function request_depot:get_fuel_amount()
  return self.entity.get_fluid_count(base.get_fuel_fluid())
end

function request_depot:get_output_fluidbox()
  return self.entity.fluidbox[2]
end

function request_depot:set_output_fluidbox(box)
  self.entity.fluidbox[2] = box
end

function request_depot:get_current_amount()
  if self.mode == request_mode.item then
    if not self.item then return 0 end
    if self.item_quality and self.item_quality ~= "normal" then
      return self:get_output_inventory().get_item_count({name = self.item, quality = self.item_quality})
    end
    return self:get_output_inventory().get_item_count(self.item)
  end

  if self.mode == request_mode.fluid then
    local box = self:get_output_fluidbox()
    return box and box.amount or 0
  end
end

function request_depot:update_circuit_reader()
  if not (self.circuit_reader and self.circuit_reader.valid) then return end
  local behavior = self.circuit_reader.get_or_create_control_behavior()
  local section = behavior.get_section(1)
  if not section then section = behavior.add_section() end

  local sig_type = self.mode == request_mode.item and "item" or "fluid"
  local network_handled = self:update_circuit_reader_network(self.item, sig_type, self.item and self:get_current_amount() or 0)

  if not network_handled then
    if self.item then
      local signal_value = {type = sig_type, name = self.item, quality = self.item_quality or "normal"}
      section.set_slot(1, {value = signal_value, min = self:get_current_amount()})
    else
      for i = 1, section.filters_count do section.clear_slot(i) end
      return
    end
  end

  local slot = self:write_reader_extra_signals(section, 2)
  for i = slot, section.filters_count do section.clear_slot(i) end
end

function request_depot:update()
  self._drone_count_cache = nil
  self:check_request_change()
  self:check_fuel_amount()
  self:check_drone_validity()
  self:check_drone_amount()
  self:update_circuit_writer()
  self:update_priority_from_circuit()
  self:update_channel_from_circuit()
  self:make_request()
  self:update_sticker()
  self:update_circuit_reader()
  self:update_disabled_visual()
end

function request_depot:check_request_change()
  local requested_item = self:get_requested_item()
  if self.item == requested_item then return end

  self:set_request_mode()

  if self.item then
    self:remove_from_network()
    self:suicide_all_drones()
  end

  self.item = requested_item
  if not self._pending_quality then
    self.item_quality = "normal"
  else
    self.item_quality = self._pending_quality
    self._pending_quality = nil
  end

  if not self.item then return end

  self:add_to_network()

end

function request_depot:set_item_quality(quality)
  if self.item_quality == quality then return end
  if self.item then
    self:remove_from_network()
    self:suicide_all_drones()
  end
  self.item_quality = quality
  if self.item then
    self:add_to_network()
  end
end

local min = math.min
local item_heuristic_bonus = 50

local request_heuristic = function(depot, count, request_size, minimum_size, priority_weight, node_pos, surface_idx, portal_dist)
  local amount = min(count, request_size)
  local priority = depot.priority or shared.default_priority
  local bonus = depot.score_bonus or 0
  local dist = base.effective_distance(depot, node_pos, surface_idx, portal_dist)
  if priority_weight == 0 then
    return -priority * 1000000 + dist - ((amount / request_size) * item_heuristic_bonus) - bonus
  else
    return -priority * priority_weight + dist - ((amount / request_size) * item_heuristic_bonus) - bonus
  end
end

function request_depot:make_request()
  base.make_request_from_supply(self, request_heuristic)
end

function request_depot:take_item(name, count, temperature, spoil_percent, quality)
  if not count then error("take_item called without count") end

  if self.mode == request_mode.item and is_valid_item(name) then
    local stack = {name = name, count = count}
    if quality and quality ~= "normal" then stack.quality = quality end
    if spoil_percent then stack.spoil_percent = spoil_percent end
    self.entity.get_output_inventory().insert(stack)
    return
  end

  if self.mode == request_mode.fluid and is_valid_fluid(name) then
    -- Push directly into connected pipe/tank for fast output throughput
    local remaining = count
    local connections = self.entity.fluidbox.get_connections(2)
    if connections then
      for _, connected_fb in pairs(connections) do
        if connected_fb.owner and connected_fb.owner.valid then
          local inserted = connected_fb.owner.insert_fluid({name = name, amount = remaining, temperature = temperature})
          remaining = remaining - inserted
          if remaining <= 0 then return end
        end
      end
    end
    -- Buffer remainder in depot's output fluidbox
    local box = self:get_output_fluidbox()
    if not box then
      box = {name = name, amount = 0}
    end
    box.amount = box.amount + remaining
    if temperature then
      box.temperature = temperature
    end
    self:set_output_fluidbox(box)
    return
  end

end

function request_depot:add_to_network()
  self.network_id = self.road_network.add_depot(self, "request")
end

function request_depot:remove_from_network()
  self.road_network.remove_depot(self, "request")
  self.network_id = nil
end

return request_depot
