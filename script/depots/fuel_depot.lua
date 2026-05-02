local base = require("script/depot_base")

local fuel_amount_per_drone = shared.fuel_amount_per_drone
local drone_fluid_capacity = shared.drone_fluid_capacity

local fuel_depot = {}
fuel_depot.metatable = {__index = fuel_depot}

fuel_depot.corpse_offsets =
{
  [defines.direction.north] = {0, -3},
  [defines.direction.east] = {3, 0},
  [defines.direction.south] = {0, 3},
  [defines.direction.west] = {-3, 0},
}

base.mixin(fuel_depot, "drone")

function fuel_depot.new(entity, tags)

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
    drones = {},
    priority = shared.default_priority,
    base_priority = shared.default_priority,
    channel = shared.default_channel,
    base_channel = shared.default_channel
  }
  setmetatable(depot, fuel_depot.metatable)

  depot:get_corpse()
  depot:read_tags(tags)

  return depot

end

function fuel_depot:update_circuit_reader()
  if not (self.circuit_reader and self.circuit_reader.valid) then return end
  local behavior = self.circuit_reader.get_or_create_control_behavior()
  local section = behavior.get_section(1)
  if not section then section = behavior.add_section() end

  local network_handled = self:update_circuit_reader_network(base.get_fuel_fluid(), "fluid", self:get_fuel_amount())

  if not network_handled then
    local signal_value = {type = "fluid", name = base.get_fuel_fluid(), quality = "normal"}
    section.set_slot(1, {value = signal_value, min = self:get_fuel_amount()})
  end

  local slot = self:write_reader_extra_signals(section, 2)
  for i = slot, section.filters_count do section.clear_slot(i) end
end

function fuel_depot:update()
  self._drone_count_cache = nil
  self:update_priority_from_circuit()
  self:update_channel_from_circuit()
  self:check_drone_validity()
  self:update_circuit_reader()
  self:update_sticker()
  self:update_disabled_visual()
end

function fuel_depot:add_to_network()
  self.network_id = self.road_network.add_depot(self, "fuel")
end

function fuel_depot:remove_from_network()
  self.road_network.remove_depot(self, "fuel")
  self.network_id = nil
end

function fuel_depot:get_fuel_amount()
  return self.entity.get_fluid_count(base.get_fuel_fluid())
end

function fuel_depot:minimum_request_size()
  return (fuel_amount_per_drone * 2)
end

function fuel_depot:get_drone_fluid_capacity()
  return drone_fluid_capacity * (1 + fuel_depot.transport_technologies.get_transport_capacity_bonus(self.entity.force.index))
end

function fuel_depot:handle_fuel_request(depot)
  if not self:can_spawn_drone() then return end

  if base.is_writer_disabled(self) then
    return
  end

  local amount = self:get_fuel_amount()
  if amount < self:minimum_request_size() then return end

  amount = math.min((amount - fuel_amount_per_drone), self:get_drone_fluid_capacity())

  local drone_quality = self:get_next_drone_quality()
  if not drone_quality then return end
  local drone = fuel_depot.transport_drone.new(self, "fuel-truck", drone_quality)
  if not drone then return end
  self._drone_count_cache = nil

  self:remove_fuel(amount)
  self:remove_fuel(fuel_amount_per_drone)

  drone:deliver_fuel(depot, amount)
  self:register_active_drone(drone)
  self:update_sticker()

end

-- Override update_sticker for fuel depot (different scale/offset)
function fuel_depot:update_sticker()

  if self.rendering and self.rendering.valid then
    self.rendering.text = self:get_active_drone_count().."/"..self:get_drone_item_count()
    return
  end

  self.rendering = rendering.draw_text
  {
    surface = self.entity.surface.index,
    target = self.entity,
    text = self:get_active_drone_count().."/"..self:get_drone_item_count(),
    only_in_alt_mode = true,
    forces = {self.entity.force},
    color = {r = 1, g = 1, b = 1},
    alignment = "center",
    scale = 2,
    target_offset = {0, 0.5}
  }

end

return fuel_depot
