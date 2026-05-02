local base = require("script/depot_base")
local convert_contents_to_dict = base.convert_contents_to_dict

local supply_depot = {}
supply_depot.metatable = {__index = supply_depot}

supply_depot.corpse_offsets =
{
  [defines.direction.north] = {0, -2},
  [defines.direction.east] = {2, 0},
  [defines.direction.south] = {0, 2},
  [defines.direction.west] = {-2, 0},
}

base.mixin(supply_depot, "supplier")

function supply_depot.new(entity, tags)
  local position = entity.position
  local force = entity.force
  local surface = entity.surface
  entity.destructible = false
  entity.rotatable = false
  entity.active = false

  local quality_level = entity.quality and entity.quality.level or 0
  local chest_name = shared.supply_chest_name[quality_level] or "supply-depot-chest"
  local chest = surface.create_entity{name = chest_name, position = position, force = force, player = entity.last_user}

  local depot =
  {
    entity = chest,
    assembler = entity,
    to_be_taken = {},
    index = tostring(chest.unit_number),
    old_contents = {},
    priority = shared.default_priority,
    base_priority = shared.default_priority,
    channel = shared.default_channel,
    base_channel = shared.default_channel,
    allow_bots = false
  }
  setmetatable(depot, supply_depot.metatable)

  depot:get_corpse()
  depot:read_tags(tags)

  return depot

end

-- Override get_corpse_position to use assembler instead of entity
function supply_depot:get_corpse_position()
  local position = self.assembler.position
  local offset = self.corpse_offsets[self.assembler.direction]
  return {position.x + offset[1], position.y + offset[2]}
end

function supply_depot:read_tags(tags)
  local ttags = base.read_base_tags(self, tags)
  if not ttags then return end
  if ttags.bar then
    local quality_level = self.assembler.quality and self.assembler.quality.level or 0
    local max_slots = shared.quality_supply_inventory[quality_level] or 100
    local bar = ttags.bar
    if bar > max_slots + 1 then bar = max_slots + 1 end
    self.entity.get_output_inventory().set_bar(bar)
  end
  if ttags.allow_bots then
    self:set_allow_bots(true)
  end
end

function supply_depot:save_to_blueprint_tags()
  local tags = base.save_base_tags(self) or {}
  tags.bar = self.entity.get_output_inventory().get_bar()
  if self.allow_bots then tags.allow_bots = true end
  return tags
end


function supply_depot:set_allow_bots(value)
  if (self.allow_bots or false) == value then return end
  self.allow_bots = value
  local ql = self.assembler.quality and self.assembler.quality.level or 0
  local new_name
  if value then
    new_name = shared.supply_chest_name_logistic[ql] or "supply-depot-chest-logistic"
  else
    new_name = shared.supply_chest_name[ql] or "supply-depot-chest"
  end
  self:swap_chest_entity(new_name)
end

function supply_depot:update_contents()
  local supply = self.road_network.get_network_item_supply(self.network_id)

  -- Reuse buffer table to avoid allocation each cycle
  local buf = self._contents_buf or {}
  local new_contents
  if base.is_writer_disabled(self) then
    for k in pairs(buf) do buf[k] = nil end
    new_contents = buf
  end

  if not new_contents then
    new_contents = convert_contents_to_dict(self.entity.get_output_inventory().get_contents(), buf)
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

  self._contents_buf = self.old_contents
  self.old_contents = new_contents

end

function supply_depot:update_circuit_reader()
  if not (self.circuit_reader and self.circuit_reader.valid) then return end

  local behavior = self.circuit_reader.get_or_create_control_behavior()
  local section = behavior.get_section(1)
  if not section then section = behavior.add_section() end

  local rconfig = storage.reader_config and storage.reader_config[self.circuit_reader.unit_number]
  local mode = rconfig and rconfig.mode or 1

  local slot = 1
  if mode == 1 then
    for name, count in pairs(self.old_contents) do
      if count > 0 then
        section.set_slot(slot, {value = {type = "item", name = name, quality = "normal"}, min = count})
        slot = slot + 1
      end
    end
  else
    local supply = self.network_id and self.road_network.get_network_item_supply(self.network_id)
    if supply then
      for name, count in pairs(self.old_contents) do
        local counts = supply[name]
        local sum = 0
        if counts then
          for _, c in pairs(counts) do
            sum = sum + c
          end
        end
        if mode == 3 then
          sum = math.max(0, sum - count)
        end
        if sum > 0 then
          section.set_slot(slot, {value = {type = "item", name = name, quality = "normal"}, min = sum})
          slot = slot + 1
        end
      end
    end
  end

  slot = self:write_reader_extra_signals(section, slot)

  local filters_count = section.filters_count
  for i = slot, filters_count do
    section.clear_slot(i)
  end
end

function supply_depot:update()
  self:update_priority_from_circuit()
  self:update_channel_from_circuit()
  self:update_threshold_from_circuit()
  self:update_contents()
  self:update_circuit_reader()
  self:update_disabled_visual()
end

function supply_depot:give_item(requested_name, requested_count, requested_quality)
  local inventory = self.entity.get_output_inventory()
  local stack = inventory.find_item_stack(requested_name)
  local spoil_percent = stack and stack.spoil_percent or 0
  local remove_filter = {name = requested_name, count = requested_count}
  if requested_quality and requested_quality ~= "normal" then remove_filter.quality = requested_quality end
  local removed_count = inventory.remove(remove_filter)
  return removed_count, spoil_percent > 0 and spoil_percent or nil
end

function supply_depot:get_available_item_count(name, quality)
  local key = shared.supply_key(name, quality)
  local filter = (quality and quality ~= "normal") and {name = name, quality = quality} or name
  return self.entity.get_output_inventory().get_item_count(filter) - self:get_to_be_taken(key)
end

function supply_depot:add_to_network()
  self.network_id = self.road_network.add_depot(self, "supply")
  self:update_contents()
end

function supply_depot:remove_from_network()
  self.road_network.remove_depot(self, "supply")
  self.network_id = nil
end

function supply_depot:on_removed(event)

  if self.corpse and self.corpse.valid then
    self.corpse.destroy()
  end

  if self.assembler.valid then
    self.assembler.destructible = true
    if event.name == defines.events.on_entity_died then
      self.assembler.die()
    else
      self.assembler.destroy()
    end
  end

  if self.entity.valid then
    self.entity.destroy()
  end
end

return supply_depot
