local base = require("script/depot_base")

local network_reader = {}
network_reader.metatable = {__index = network_reader}

network_reader.corpse_offsets =
{
  [defines.direction.north] = {0, 1},
  [defines.direction.east] = {-1, 0},
  [defines.direction.south] = {0, -1},
  [defines.direction.west] = {1, 0},
}

base.mixin(network_reader)

function network_reader.new(entity)

  local force = entity.force
  local surface = entity.surface

  entity.rotatable = false

  local depot =
  {
    entity = entity,
    index = tostring(entity.unit_number)
  }
  setmetatable(depot, network_reader.metatable)
  depot:get_corpse()

  local offset = network_reader.corpse_offsets[entity.direction]
  rendering.draw_sprite
  {
    sprite = "utility/fluid_indication_arrow",
    surface = entity.surface,
    only_in_alt_mode = true,
    target = entity,
    target_offset = {offset[1] / 2, offset[2] / 2},
    orientation_target = entity
  }

  return depot

end

function network_reader:update()
  local behavior = self.entity.get_control_behavior()
  if not behavior then return end

  local section = behavior.get_section(1)
  if not section then
    section = behavior.add_section()
  end

  local supply = self.road_network.get_network_item_supply(self.network_id)
  if not supply then return end

  local filters_count = section.filters_count
  for i = 1, filters_count do
    local slot = section.get_slot(i)
    local name = slot and slot.value and slot.value.name
    if name then
      local quality = slot.value.quality
      local key = shared.supply_key(name, quality)
      local sum = 0
      local counts = supply[key]
      if counts then
        for depot, count in pairs (counts) do
          sum = sum + count
        end
      end
      section.set_slot(i, {value = slot.value, min = sum})
    end
  end

end

function network_reader:add_to_network()
  local node = self.road_network.get_node(self.entity.surface.index, self.node_position[1], self.node_position[2])
  self.network_id = node and node.id
end

function network_reader:remove_from_network()
  self.network_id = nil
end

function network_reader:on_removed()
  if self.corpse and self.corpse.valid then
    self.corpse.destroy()
  end
end

return network_reader
