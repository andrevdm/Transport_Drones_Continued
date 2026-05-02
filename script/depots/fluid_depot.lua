local base = require("script/depot_base")

local fluid_depot = {}
fluid_depot.metatable = {__index = fluid_depot}

fluid_depot.corpse_offsets =
{
  [defines.direction.north] = {0, -2},
  [defines.direction.east] = {2, 0},
  [defines.direction.south] = {0, 2},
  [defines.direction.west] = {-2, 0},
}

base.mixin(fluid_depot, "supplier")

function fluid_depot.new(entity, tags)

  local force = entity.force
  local surface = entity.surface

  entity.rotatable = false

  local depot =
  {
    entity = entity,
    to_be_taken = {},
    index = tostring(entity.unit_number),
    old_contents = {},
    priority = shared.default_priority,
    base_priority = shared.default_priority,
    channel = shared.default_channel,
    base_channel = shared.default_channel
  }
  setmetatable(depot, fluid_depot.metatable)
  depot:get_corpse()
  depot:read_tags(tags)

  return depot

end

function fluid_depot:get_output_fluidbox()
  return self.entity.fluidbox[1]
end

function fluid_depot:get_temperature()
  local box = self:get_output_fluidbox()
  return box and box.temperature
end

function fluid_depot:set_output_fluidbox(box)
  self.entity.fluidbox[1] = box
end

function fluid_depot:update_contents()

  local supply = self.road_network.get_network_item_supply(self.network_id)

  local buf = self._contents_buf or {}
  for k in pairs(buf) do buf[k] = nil end
  local new_contents = buf

  local enabled = not base.is_writer_disabled(self)

  if enabled then
    local box = self:get_output_fluidbox()
    if box then
      new_contents[box.name] = box.amount
    end
  end

  for name, count in pairs(self.old_contents) do
    if not new_contents[name] then
      local item_supply = supply[name]
      if item_supply then
        item_supply[self.index] = nil
      end
    end
  end

  local threshold = self:get_supply_threshold()
  for name, count in pairs (new_contents) do
    local item_supply = supply[name]
    if not item_supply then
      item_supply = {}
      supply[name] = item_supply
    end
    local new_count = count - self:get_to_be_taken(name) - threshold
    if new_count > 0 then
      item_supply[self.index] = new_count
    else
      item_supply[self.index] = nil
    end
  end

  self._contents_buf = self.old_contents
  self.old_contents = new_contents

  local first_fluid = next(new_contents)
  if not first_fluid then
    local box = self:get_output_fluidbox()
    if box then first_fluid = box.name end
  end
  local local_fluid_count = 0
  if first_fluid then
    local_fluid_count = new_contents[first_fluid] or 0
    if local_fluid_count <= 0 then
      local box = self:get_output_fluidbox()
      if box and box.name == first_fluid then local_fluid_count = box.amount end
    end
  end
  if not self:update_circuit_reader_network(first_fluid, "fluid", local_fluid_count) then
    if self.circuit_reader and self.circuit_reader.valid then
      local behavior = self.circuit_reader.get_or_create_control_behavior()
      local section = behavior.get_section(1)
      if not section then section = behavior.add_section() end
      local name = first_fluid
      local count = name and (new_contents[name] or 0)
      if not count or count <= 0 then
        local box = self:get_output_fluidbox()
        if box and box.name == name then count = box.amount end
      end
      if name and count and count > 0 then
        local signal_value = {type = "fluid", name = name, quality = "normal"}
        section.set_slot(1, {value = signal_value, min = count})
      else
        section.clear_slot(1)
      end
    end
  end

end

function fluid_depot:update()
  if not self.network_id then return end
  self:update_priority_from_circuit()
  self:update_channel_from_circuit()
  self:update_threshold_from_circuit()
  self:update_disabled_visual()

  local box = self:get_output_fluidbox()
  if not box then
    if not self.entity.active then
      self.entity.active = true
      self.entity.crafting_progress = 0
    end
    return
  end

  if self.entity.active then
    self.entity.active = false
  end

  self:update_contents()

end

function fluid_depot:give_item(requested_name, requested_count)
  return self.entity.remove_fluid{name = requested_name, amount = requested_count}
end

function fluid_depot:get_available_item_count(name)
  return self.entity.get_fluid_count(name) - self:get_to_be_taken(name)
end

function fluid_depot:add_to_network()
  self.network_id = self.road_network.add_depot(self, "fluid")
  self:update_contents()
end

function fluid_depot:remove_from_network()
  self.road_network.remove_depot(self, "fluid")
  self.network_id = nil
end

function fluid_depot:on_removed()
  if self.corpse and self.corpse.valid then
    self.corpse.destroy()
  end
end

fluid_depot.read_tags = base.read_base_tags
fluid_depot.save_to_blueprint_tags = base.save_base_tags

return fluid_depot
