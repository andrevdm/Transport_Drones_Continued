local base = require("script/depot_base")

local buffer_depot = {}
buffer_depot.metatable = {__index = buffer_depot}

buffer_depot.corpse_offsets =
{
  [defines.direction.north] = {0, -2},
  [defines.direction.east] = {2, 0},
  [defines.direction.south] = {0, 2},
  [defines.direction.west] = {-2, 0},
}

buffer_depot.is_buffer_depot = true

base.mixin(buffer_depot, "drone", "requester", "supplier")

local request_mode = base.request_mode
local is_valid_item = base.is_valid_item
local is_valid_fluid = base.is_valid_fluid

function buffer_depot.new(entity, tags)

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
    to_be_taken = {},
    old_contents = {},
    priority = shared.default_priority,
    base_priority = shared.default_priority,
    channel = shared.default_channel,
    base_channel = shared.default_channel,
    allow_bots = false
  }
  setmetatable(depot, buffer_depot.metatable)
  depot:get_corpse()
  depot:read_tags(tags)

  return depot

end

function buffer_depot:update_contents()

  if not self.network_id then return end

  local supply = self.road_network.get_network_item_supply(self.network_id)

  local buf = self._contents_buf or {}
  for k in pairs(buf) do buf[k] = nil end
  local new_contents = buf

  local enabled = (self.circuit_limit ~= 0)

  if enabled and self.item then
    local key = shared.supply_key(self.item, self.item_quality)
    new_contents[key] = self:get_current_amount()
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

  if self.circuit_reader and self.circuit_reader.valid then
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
        section.clear_slot(1)
        section.clear_slot(2)
      end
    end

    local slot = self:write_reader_extra_signals(section, 2)
    for i = slot, section.filters_count do section.clear_slot(i) end
  end

end

function buffer_depot:update()
  self._drone_count_cache = nil
  self:check_request_change()
  self:sync_bot_chest()
  self:update_contents()
  self:check_fuel_amount()
  self:check_drone_validity()
  self:check_drone_amount()
  self:update_circuit_writer()
  self:update_priority_from_circuit()
  self:update_channel_from_circuit()
  self:update_threshold_from_circuit()
  self:make_request()
  self:update_sticker()
  self:update_disabled_visual()
end

function buffer_depot:check_request_change()
  local requested_item = self:get_requested_item()
  if self.item == requested_item then return end

  self:set_request_mode()

  if self.item then
    self:remove_from_network()
    self:suicide_all_drones()
  end

  self:destroy_bot_chest()

  self.item = requested_item
  if not self._pending_quality then
    self.item_quality = "normal"
  else
    self.item_quality = self._pending_quality
    self._pending_quality = nil
  end

  self:add_to_network()

  if self.item and self.allow_bots and self.mode == request_mode.item then
    self:create_bot_chest()
  end
end

function buffer_depot:set_item_quality(quality)
  if self.item_quality == quality then return end
  if self.item then
    self:remove_from_network()
    self:suicide_all_drones()
  end
  self:destroy_bot_chest()
  self.item_quality = quality
  self:add_to_network()
  if self.item and self.allow_bots and self.mode == request_mode.item then
    self:create_bot_chest()
  end
end

function buffer_depot:get_output_inventory()
  if not self.output_inventory then
    self.output_inventory = self.entity.get_output_inventory()
  end
  return self.output_inventory
end

function buffer_depot:get_fuel_amount()
  return self.entity.get_fluid_count(base.get_fuel_fluid())
end

function buffer_depot:get_output_fluidbox()
  return self.entity.fluidbox[2]
end

function buffer_depot:set_output_fluidbox(box)
  self.entity.fluidbox[2] = box
end

function buffer_depot:get_temperature()
  if #self.entity.fluidbox == 2 then
    local box = self:get_output_fluidbox()
    return box and box.temperature
  end
end

function buffer_depot:get_current_amount()
  if not self.item then return 0 end

  if self.mode == request_mode.item then
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

function buffer_depot:get_available_stack_amount()
  if not self.item then return 0 end
  return self:get_available_item_count(self.item, self.item_quality) / self:get_stack_size()
end

function buffer_depot:get_available_item_count(name, quality)
  local key = shared.supply_key(name, quality)
  return self:get_current_amount() - self:get_to_be_taken(key)
end

local big = math.huge
local min = math.min
local item_heuristic_bonus = 50

local buffer_heuristic = function(depot, count, request_size, minimum_size, priority_weight, node_pos, surface_idx, portal_dist)
  if depot.is_buffer_depot then return big end
  local amount = min(count, request_size)
  if amount < minimum_size then return big end
  local priority = depot.priority or shared.default_priority
  local dist = base.effective_distance(depot, node_pos, surface_idx, portal_dist)
  if priority_weight == 0 then
    return -priority * 1000000 + dist - ((amount / request_size) * item_heuristic_bonus)
  else
    return -priority * priority_weight + dist - ((amount / request_size) * item_heuristic_bonus)
  end
end

function buffer_depot:make_request()
  base.make_request_from_supply(self, buffer_heuristic)
end

function buffer_depot:give_item(requested_name, requested_count, requested_quality)

  if prototypes.item[requested_name] then
    local inventory = self.entity.get_output_inventory()
    local stack = inventory.find_item_stack(requested_name)
    local spoil_percent = stack and stack.spoil_percent or 0
    local remove_filter = {name = requested_name, count = requested_count}
    if requested_quality and requested_quality ~= "normal" then remove_filter.quality = requested_quality end
    local removed_count = inventory.remove(remove_filter)
    return removed_count, spoil_percent > 0 and spoil_percent or nil
  end

  if prototypes.fluid[requested_name] then
    local box = self:get_output_fluidbox()
    if not box then
      return 0
    end

    if box.name ~= requested_name then
      return 0
    end

    if requested_count >= box.amount then
      self:set_output_fluidbox(nil)
      return box.amount
    end

    box.amount = box.amount - requested_count
    self:set_output_fluidbox(box)
    return requested_count
  end
end

function buffer_depot:take_item(name, count, temperature, spoil_percent, quality)
  if not count then error("take_item called without count") end

  if self.mode == request_mode.item and is_valid_item(name) then
    local stack = {name = name, count = count}
    if quality and quality ~= "normal" then stack.quality = quality end
    if spoil_percent then stack.spoil_percent = spoil_percent end
    self.entity.get_output_inventory().insert(stack)
    return
  end

  if self.mode == request_mode.fluid and is_valid_fluid(name) then
    local box = self:get_output_fluidbox()
    if not box then
      box = {name = name, amount = 0}
    end
    box.amount = box.amount + count
    if temperature then
      box.temperature = temperature
    end
    self:set_output_fluidbox(box)
    return
  end

end

function buffer_depot:set_allow_bots(value)
  if (self.allow_bots or false) == value then return end
  self.allow_bots = value
  if value and self.mode == request_mode.item and self.item then
    self:create_bot_chest()
  else
    self:destroy_bot_chest()
  end
end

function buffer_depot:create_bot_chest()
  if self.bot_chest and self.bot_chest.valid then return end
  local quality_level = self.entity.quality and self.entity.quality.level or 0
  local chest_name = shared.buffer_chest_name_logistic[quality_level] or "buffer-depot-chest-logistic"
  local chest = self.entity.surface.create_entity{
    name = chest_name,
    position = self.entity.position,
    force = self.entity.force
  }
  chest.destructible = false
  self.bot_chest = chest

  local count = self:get_current_amount()
  if count > 0 and self.item then
    chest.get_output_inventory().insert({name = self.item, count = count})
  end
  self.last_bot_count = count
end

function buffer_depot:destroy_bot_chest()
  if self.bot_chest and self.bot_chest.valid then
    self.bot_chest.destroy()
  end
  self.bot_chest = nil
  self.last_bot_count = nil
end

function buffer_depot:sync_bot_chest()
  if not self.bot_chest or not self.bot_chest.valid then return end
  if not self.item or self.mode ~= request_mode.item then
    self:destroy_bot_chest()
    return
  end

  local bot_inv = self.bot_chest.get_output_inventory()
  local bot_count = bot_inv.get_item_count(self.item)
  local bots_took = (self.last_bot_count or 0) - bot_count
  if bots_took > 0 then
    self:get_output_inventory().remove({name = self.item, count = bots_took})
  end

  local current = self:get_output_inventory().get_item_count(self.item)
  bot_inv.clear()
  if current > 0 then
    bot_inv.insert({name = self.item, count = current})
  end
  self.last_bot_count = current
end

local drone_save_tags = buffer_depot.save_to_blueprint_tags
function buffer_depot:save_to_blueprint_tags()
  local tags = drone_save_tags(self)
  if self.allow_bots then
    tags = tags or {}
    tags.allow_bots = true
  end
  return tags
end

local drone_read_tags = buffer_depot.read_tags
function buffer_depot:read_tags(tags)
  drone_read_tags(self, tags)
  if tags and tags.transport_depot_tags and tags.transport_depot_tags.allow_bots then
    self:set_allow_bots(true)
  end
end

local drone_on_removed = buffer_depot.on_removed
function buffer_depot:on_removed(event)
  self:destroy_bot_chest()
  drone_on_removed(self, event)
end

function buffer_depot:add_to_network()
  self.network_id = self.road_network.add_depot(self, "buffer")
  self:update_contents()
end

function buffer_depot:remove_from_network()
  self.road_network.remove_depot(self, "buffer")
  self.network_id = nil
end

return buffer_depot
