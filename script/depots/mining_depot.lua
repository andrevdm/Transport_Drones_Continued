local base = require("script/depot_base")
local convert_contents_to_dict = base.convert_contents_to_dict

local mining_depot = {}
mining_depot.metatable = {__index = mining_depot}

mining_depot.corpse_offsets =
{
  [defines.direction.north] = {0, 4.5},
  [defines.direction.east] = {-4.5, 0},
  [defines.direction.south] = {0, -4.5},
  [defines.direction.west] = {4.5, 0},
}

mining_depot.optional_road_connection = true

base.mixin(mining_depot, "supplier")

function mining_depot.new(entity, tags)

  local force = entity.force
  local surface = entity.surface

  entity.active = false
  entity.rotatable = false

  local depot =
  {
    entity = entity,
    index = tostring(entity.unit_number),
    to_be_taken = {},
    old_contents = {},
    priority = shared.default_priority,
    base_priority = shared.default_priority,
    channel = shared.default_channel,
    base_channel = shared.default_channel
  }
  setmetatable(depot, mining_depot.metatable)
  depot:get_corpse()
  depot:read_tags(tags)

  return depot

end

function mining_depot:update_contents()

  local supply = self.road_network.get_network_item_supply(self.network_id)

  -- Reuse buffer table to avoid allocation each cycle
  local buf = self._contents_buf or {}
  local real_contents = convert_contents_to_dict(self.entity.get_output_inventory().get_contents(), buf)

  local new_contents
  local disabled = base.is_writer_disabled(self)
  if disabled then
    new_contents = {}
  end
  if not new_contents then
    new_contents = real_contents
  end

  for name, count in pairs (self.old_contents) do
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

  -- Swap buffers only in normal path (real_contents == buf)
  if not disabled then
    self._contents_buf = self.old_contents
  end
  self.old_contents = new_contents

  local first_name = next(real_contents)
  if self.circuit_reader and self.circuit_reader.valid then
    local behavior = self.circuit_reader.get_or_create_control_behavior()
    local section = behavior.get_section(1)
    if not section then section = behavior.add_section() end

    if not self:update_circuit_reader_network(first_name, "item", first_name and real_contents[first_name] or 0) then
      local name, count = first_name, first_name and real_contents[first_name]
      if name and count and count > 0 then
        local signal_value = {type = "item", name = name, quality = "normal"}
        section.set_slot(1, {value = signal_value, min = count})
      else
        section.clear_slot(1)
      end
    end

    local slot = self:write_reader_extra_signals(section, 2)
    for i = slot, section.filters_count do section.clear_slot(i) end
  end

end

function mining_depot:update()
  self:update_priority_from_circuit()
  self:update_channel_from_circuit()
  self:update_threshold_from_circuit()
  self:update_contents()
  self:update_disabled_visual()
end

function mining_depot:give_item(requested_name, requested_count, requested_quality)
  local inventory = self.entity.get_output_inventory()
  local stack = inventory.find_item_stack(requested_name)
  local spoil_percent = stack and stack.spoil_percent or 0
  local remove_filter = {name = requested_name, count = requested_count}
  if requested_quality and requested_quality ~= "normal" then remove_filter.quality = requested_quality end
  local removed_count = inventory.remove(remove_filter)
  return removed_count, spoil_percent > 0 and spoil_percent or nil
end

function mining_depot:get_available_item_count(name, quality)
  local key = shared.supply_key(name, quality)
  local filter = (quality and quality ~= "normal") and {name = name, quality = quality} or name
  return self.entity.get_output_inventory().get_item_count(filter) - self:get_to_be_taken(key)
end

function mining_depot:add_to_network()
  self.network_id = self.road_network.add_depot(self, "mining")
  self:update_contents()
end

function mining_depot:remove_from_network()
  self.road_network.remove_depot(self, "mining")
  self.network_id = nil
end

function mining_depot:on_removed()
  if self.corpse and self.corpse.valid then
    self.corpse.destroy()
  end
end

mining_depot.read_tags = base.read_base_tags
mining_depot.save_to_blueprint_tags = base.save_base_tags

return mining_depot
