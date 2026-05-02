local base = require("script/depot_base")

local fuel_amount_per_drone = shared.fuel_amount_per_drone
local channels_match = base.channels_match
local request_mode = base.request_mode

local active_depot = {}
active_depot.metatable = {__index = active_depot}

active_depot.corpse_offsets =
{
  [defines.direction.north] = {0, -2},
  [defines.direction.east] = {2, 0},
  [defines.direction.south] = {0, 2},
  [defines.direction.west] = {-2, 0},
}

base.mixin(active_depot, "drone", "supplier")

function active_depot.new(entity, tags)

  local force = entity.force
  local surface = entity.surface

  entity.active = false
  entity.rotatable = false

  -- Create hidden item chest (quality-scaled)
  local quality_level = entity.quality and entity.quality.level or 0
  local chest_name = shared.active_chest_name[quality_level] or "active-depot-chest"
  local item_chest = surface.create_entity{
    name = chest_name,
    position = entity.position,
    force = force
  }
  item_chest.destructible = false

  local drone_chest = base.create_drone_chest(entity)

  local depot =
  {
    entity = entity,
    item_chest = item_chest,
    drone_chest = drone_chest,
    index = tostring(entity.unit_number),
    item = false,
    drones = {},
    to_be_taken = {},
    old_contents = {},
    fuel_on_the_way = 0,
    priority = shared.default_priority,
    base_priority = shared.default_priority,
    channel = shared.default_channel,
    base_channel = shared.default_channel,
    fluid_mode = (entity.name == shared.active_depot_fluid_name or entity.name == shared.active_depot_fluid_name .. "-multi")
  }
  setmetatable(depot, active_depot.metatable)

  depot:get_corpse()

  -- Lock item chest if starting in fluid mode
  if depot.fluid_mode then
    depot:get_item_inventory().set_bar(1)
  end

  depot:read_tags(tags)

  return depot

end

function active_depot:get_fuel_amount()
  if self.fluid_mode then
    return self.fuel_amount_stored or 0
  end
  return self.entity.get_fluid_count(base.get_fuel_fluid())
end

function active_depot:remove_fuel(amount)
  if self.fluid_mode then
    self.fuel_amount_stored = math.max(0, (self.fuel_amount_stored or 0) - amount)
  else
    self.entity.remove_fluid({name = base.get_fuel_fluid(), amount = amount})
  end
end

function active_depot:receive_fuel(amount)
  if self.fluid_mode then
    self.fuel_amount_stored = math.max(0, (self.fuel_amount_stored or 0) + amount)
  else
    if amount > 0 then
      base.insert_fuel(self.entity, amount)
    elseif amount < 0 then
      self.entity.remove_fluid({name = base.get_fuel_fluid(), amount = -amount})
    end
  end
end

function active_depot:check_fuel_amount()
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

function active_depot:check_drone_amount()
  if self:get_drone_item_count() == 0 then
    self:show_drone_alert({"no-drone-in-depot"})
  end
end

function active_depot:get_item_inventory()
  if not (self.item_chest and self.item_chest.valid) then return nil end
  return self.item_chest.get_inventory(defines.inventory.chest)
end

-- Swap the main entity to a different prototype variant
function active_depot:swap_entity(new_name)
  local old = self.entity
  if old.name == new_name then return end

  -- Save fuel amount: physical (from fluidbox) + virtual (from stored)
  local fuel_fluid = base.get_fuel_fluid()
  local physical_fuel = old.get_fluid_count(fuel_fluid)
  local total_fuel = physical_fuel + (self.fuel_amount_stored or 0)
  local fluid_fb = old.fluidbox[2]
  local saved_fluid = fluid_fb and fluid_fb.amount > 0 and {name = fluid_fb.name, amount = fluid_fb.amount, temperature = fluid_fb.temperature} or nil

  local saved_wires = base.save_wires(old)

  -- Remove from data structures
  local depots = storage.transport_depots.depots
  self:remove_from_network()
  local node = self.road_network.get_node(self.surface_index, self.node_position[1], self.node_position[2])
  if node and node.depots then node.depots[self.index] = nil end
  depots[self.index] = nil

  -- Destroy old, create new
  local pos, dir, force, surface, quality = old.position, old.direction, old.force, old.surface, old.quality
  old.destroy()
  local new_entity = surface.create_entity{
    name = new_name,
    position = pos,
    direction = dir,
    force = force,
    quality = quality.name
  }
  new_entity.active = false
  new_entity.rotatable = false

  -- Restore fuel: virtual in fluid mode, physical in item mode
  if self.fluid_mode then
    self.fuel_amount_stored = total_fuel > 0 and total_fuel or nil
  else
    self.fuel_amount_stored = nil
    if total_fuel > 0 then
      base.insert_fuel(new_entity, total_fuel)
    end
  end

  -- Restore fluid contents (when swapping back from furnace to assembler while draining)
  if saved_fluid then
    new_entity.insert_fluid(saved_fluid)
  end

  base.restore_wires(new_entity, saved_wires)

  -- Update references
  self.entity = new_entity
  self.index = tostring(new_entity.unit_number)

  -- Re-register in data structures
  depots[self.index] = self
  script.register_on_object_destroyed(new_entity)
  if node and node.depots then node.depots[self.index] = self end
  self:add_to_network()
  if self.add_to_update_bucket then
    self.add_to_update_bucket(self.index)
  end

  -- Destroy and recreate corpse at correct position
  if self.corpse and self.corpse.valid then
    self.corpse.destroy()
  end
  self:get_corpse()

  -- Destroy and recreate sticker
  if self.rendering and self.rendering.valid then
    self.rendering:destroy()
    self.rendering = nil
  end
  self:update_sticker()
end

-- Toggle fluid mode: swap to furnace variant with south pipe
function active_depot:set_fluid_mode(value)
  if (self.fluid_mode or false) == value then return end
  self.fluid_mode = value

  -- Lock/unlock item chest
  local item_inv = self:get_item_inventory()
  if item_inv then
    if value then
      item_inv.set_bar(1)
    else
      item_inv.set_bar()
    end
  end

  -- Swap entity immediately
  if value then
    self:swap_entity(shared.active_depot_fluid_name)
  else
    self:swap_entity("active-depot")
  end
end

local convert_contents_to_dict = base.convert_contents_to_dict

function active_depot:update_contents()
  local supply = self.road_network.get_network_item_supply(self.network_id)

  local buf = self._contents_buf or {}
  local new_contents
  if base.is_writer_disabled(self) then
    for k in pairs(buf) do buf[k] = nil end
    new_contents = buf
  end

  if not new_contents then
    if self.fluid_mode then
      for k in pairs(buf) do buf[k] = nil end
      local fluid_name = self:get_fluid_name()
      if fluid_name then
        local count = self.entity.get_fluid_count(fluid_name)
        if count > 0 then
          buf[fluid_name] = count
        end
      end
      new_contents = buf
    else
      local inv = self:get_item_inventory()
      if not inv then for k in pairs(buf) do buf[k] = nil end new_contents = buf
      else new_contents = convert_contents_to_dict(inv.get_contents(), buf) end
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

  for name, count in pairs(new_contents) do
    local item_supply = supply[name]
    if not item_supply then
      item_supply = {}
      supply[name] = item_supply
    end
    local new_count = count - self:get_to_be_taken(name)
    if new_count > 0 then
      item_supply[self.index] = new_count
    else
      item_supply[self.index] = nil
    end
  end

  self._contents_buf = self.old_contents
  self.old_contents = new_contents
end

function active_depot:give_item(requested_name, requested_count, requested_quality)
  if self.fluid_mode then
    return self.entity.remove_fluid{name = requested_name, amount = requested_count}
  end
  local inventory = self:get_item_inventory()
  if not inventory then return 0 end
  local stack = inventory.find_item_stack(requested_name)
  local spoil_percent = stack and stack.spoil_percent or 0
  local remove_filter = {name = requested_name, count = requested_count}
  if requested_quality and requested_quality ~= "normal" then remove_filter.quality = requested_quality end
  local removed_count = inventory.remove(remove_filter)
  return removed_count, spoil_percent > 0 and spoil_percent or nil
end

function active_depot:get_available_item_count(name, quality)
  if self.fluid_mode then
    return self.entity.get_fluid_count(name) - self:get_to_be_taken(name)
  end
  local inv = self:get_item_inventory()
  if not inv then return 0 end
  local key = shared.supply_key(name, quality)
  local filter = (quality and quality ~= "normal") and {name = name, quality = quality} or name
  return inv.get_item_count(filter) - self:get_to_be_taken(key)
end

function active_depot:dispatch_push_drone(target_depot, item_name, count)
  local drone_quality = self:get_next_drone_quality()
  if not drone_quality then return false end

  local drone = self.transport_drone.new(self, item_name, drone_quality)
  if not drone then return false end
  self._drone_count_cache = nil

  -- Capture spoil percent from first matching stack before removal
  local inventory = self:get_item_inventory()
  if not inventory then return false end
  local spoil_percent
  local stack = inventory.find_item_stack(item_name)
  if stack then
    spoil_percent = stack.spoil_percent > 0 and stack.spoil_percent or nil
  end
  inventory.remove({name = item_name, count = count})

  -- Track items on the way at the target
  target_depot.items_on_the_way = (target_depot.items_on_the_way or 0) + count

  -- Dispatch drone to deliver
  drone:deliver_item(target_depot, item_name, count, spoil_percent)

  self:remove_fuel(fuel_amount_per_drone)
  self:register_active_drone(drone)
  self:update_sticker()

  return true
end

function active_depot:dispatch_push_drone_fluid(target_depot, fluid_name, count)
  local drone_quality = self:get_next_drone_quality()
  if not drone_quality then return false end

  local drone = self.transport_drone.new(self, fluid_name, drone_quality)
  if not drone then return false end
  self._drone_count_cache = nil

  -- Capture temperature from fluid storage
  local fb = self:get_fluid_storage()
  local temperature = fb and fb.temperature

  -- Remove fluid from storage fluidbox
  self.entity.remove_fluid({name = fluid_name, amount = count})

  -- Track on the way at the target
  target_depot.items_on_the_way = (target_depot.items_on_the_way or 0) + count

  -- Dispatch drone to deliver
  drone:deliver_item(target_depot, fluid_name, count, nil)
  drone.held_temperature = temperature

  self:remove_fuel(fuel_amount_per_drone)
  self:register_active_drone(drone)
  self:update_sticker()

  return true
end

function active_depot:scan_and_push()
  if not self:can_spawn_drone() then return end
  if self:get_fuel_amount() < fuel_amount_per_drone then return end
  if not self.network_id then return end

  -- Scan hidden chest contents, subtract items reserved for central dispatch pickup
  local inv = self:get_item_inventory()
  if not inv then return end
  local contents = {}
  for _, item in pairs(inv.get_contents()) do
    contents[item.name] = (contents[item.name] or 0) + item.count
  end
  if not next(contents) then return end
  for name, count in pairs(contents) do
    local reserved = self:get_to_be_taken(name)
    if reserved > 0 then
      contents[name] = count - reserved
    end
  end

  local _, _, max_dispatches = base.get_dispatch_settings()
  local dispatched = 0
  local my_channel = self.channel

  for item_name, available in pairs(contents) do
    if available > 0 then
      -- Search request depots first, then buffer depots
      for _, category in pairs({"request", "buffer"}) do
        local depots = self.road_network.get_depots_by_distance(self.network_id, category, self.node_position, self.entity.surface_index)
        if depots then
          for _, depot in pairs(depots) do
            if depot.item == item_name and channels_match(my_channel, depot.channel) then
              local capacity = depot:get_push_capacity()
              if capacity > 0 then
                if not self:can_spawn_drone() then return end
                if self:get_fuel_amount() < fuel_amount_per_drone then return end

                local request_size = depot:get_request_size()
                local send = math.min(available, capacity, request_size)

                if send > 0 then
                  if self:dispatch_push_drone(depot, item_name, send) then
                    dispatched = dispatched + 1
                    available = available - send
                    if dispatched >= max_dispatches then return end
                    if available <= 0 then break end
                  else
                    return
                  end
                end
              end
            end
          end
        end
        if available <= 0 then break end
      end

      -- Push remaining overflow to storage depots
      if available > 0 then
        local storage_depots = self.road_network.get_depots_by_distance(self.network_id, "storage", self.node_position, self.entity.surface_index)
        if storage_depots then
          for _, depot in pairs(storage_depots) do
            if channels_match(my_channel, depot.channel) then
              local capacity = depot:get_push_capacity_for_item(item_name)
              if capacity > 0 then
                if not self:can_spawn_drone() then return end
                if self:get_fuel_amount() < fuel_amount_per_drone then return end

                local request_size = depot:get_request_size_for_item(item_name)
                local send = math.min(available, capacity, request_size)

                if send > 0 then
                  if self:dispatch_push_drone(depot, item_name, send) then
                    dispatched = dispatched + 1
                    available = available - send
                    if dispatched >= max_dispatches then return end
                    if available <= 0 then break end
                  else
                    return
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

function active_depot:get_fluid_name()
  local recipe = self.entity.get_recipe()
  if not recipe then return nil end
  local ingredients = recipe.ingredients
  if ingredients and ingredients[1] then
    return ingredients[1].name
  end
end

-- Find the fluidbox containing the handled fluid (not fuel)
-- Returns the fluidbox table or nil
function active_depot:get_fluid_storage()
  local fluid_name = self:get_fluid_name()
  if not fluid_name then return nil end
  for i = 1, #self.entity.fluidbox do
    local fb = self.entity.fluidbox[i]
    if fb and fb.name == fluid_name then
      return fb
    end
  end
end

function active_depot:scan_and_push_fluid()
  if not self:can_spawn_drone() then return end
  if self:get_fuel_amount() < fuel_amount_per_drone then return end
  if not self.network_id then return end

  local fluid_name = self:get_fluid_name()
  if not fluid_name then return end

  -- Read fluid storage
  local available = self.entity.get_fluid_count(fluid_name)
  if available <= 0 then return end

  local _, _, max_dispatches = base.get_dispatch_settings()
  local dispatched = 0
  local my_channel = self.channel

  -- Search request depots and buffer depots in fluid mode
  for _, category in pairs({"request", "buffer"}) do
    local depots = self.road_network.get_depots_by_distance(self.network_id, category, self.node_position, self.entity.surface_index)
    if depots then
      for _, depot in pairs(depots) do
        if depot.item == fluid_name and depot.mode == request_mode.fluid and channels_match(my_channel, depot.channel) then
          local capacity = depot:get_push_capacity()
          if capacity > 0 then
            if not self:can_spawn_drone() then return end
            if self:get_fuel_amount() < fuel_amount_per_drone then return end

            local request_size = depot:get_request_size()
            local send = math.min(available, capacity, request_size)

            if send > 0 then
              if self:dispatch_push_drone_fluid(depot, fluid_name, send) then
                dispatched = dispatched + 1
                available = available - send
                if dispatched >= max_dispatches then return end
                if available <= 0 then return end
              else
                return
              end
            end
          end
        end
      end
    end
    if available <= 0 then return end
  end

  -- Push remaining overflow to storage depots in fluid mode
  if available > 0 then
    local storage_depots = self.road_network.get_depots_by_distance(self.network_id, "storage", self.node_position, self.entity.surface_index)
    if storage_depots then
      for _, depot in pairs(storage_depots) do
        if channels_match(my_channel, depot.channel) then
          local capacity = depot:get_push_capacity_for_item(fluid_name)
          if capacity > 0 then
            if not self:can_spawn_drone() then return end
            if self:get_fuel_amount() < fuel_amount_per_drone then return end

            local request_size = depot:get_request_size_for_item(fluid_name)
            local send = math.min(available, capacity, request_size)

            if send > 0 then
              if self:dispatch_push_drone_fluid(depot, fluid_name, send) then
                dispatched = dispatched + 1
                available = available - send
                if dispatched >= max_dispatches then return end
                if available <= 0 then return end
              else
                return
              end
            end
          end
        end
      end
    end
  end
end

function active_depot:update_circuit_reader()
  if not (self.circuit_reader and self.circuit_reader.valid) then return end

  local behavior = self.circuit_reader.get_or_create_control_behavior()
  local section = behavior.get_section(1)
  if not section then section = behavior.add_section() end

  local rconfig = storage.reader_config and storage.reader_config[self.circuit_reader.unit_number]
  local mode = rconfig and rconfig.mode or 1

  local slot = 1

  if self.fluid_mode then
    -- Fluid mode: read from recipe + fluid storage
    local fluid_name = self:get_fluid_name()
    local fluid_count = fluid_name and math.floor(self.entity.get_fluid_count(fluid_name)) or 0
    if fluid_count > 0 then
      if mode == 1 then
        if fluid_count > 0 then
          section.set_slot(slot, {value = {type = "fluid", name = fluid_name, quality = "normal"}, min = fluid_count})
          slot = slot + 1
        end
      else
        local supply = self.network_id and self.road_network.get_network_item_supply(self.network_id)
        if supply then
          local counts = supply[fluid_name]
          local sum = 0
          if counts then for _, c in pairs(counts) do sum = sum + c end end
          if mode == 3 then sum = math.max(0, sum - fluid_count) end
          if sum > 0 then
            section.set_slot(slot, {value = {type = "fluid", name = fluid_name, quality = "normal"}, min = sum})
            slot = slot + 1
          end
        end
      end
    end
  else
    -- Item mode: read from hidden chest
    local inv = self:get_item_inventory()
    local contents = {}
    if not inv then return slot end
    for _, item in pairs(inv.get_contents()) do
      contents[item.name] = (contents[item.name] or 0) + item.count
    end
    if mode == 1 then
      for name, count in pairs(contents) do
        if count > 0 then
          section.set_slot(slot, {value = {type = "item", name = name, quality = "normal"}, min = count})
          slot = slot + 1
        end
      end
    else
      local supply = self.network_id and self.road_network.get_network_item_supply(self.network_id)
      if supply then
        for name, count in pairs(contents) do
          local counts = supply[name]
          local sum = 0
          if counts then for _, c in pairs(counts) do sum = sum + c end end
          if mode == 3 then sum = math.max(0, sum - count) end
          if sum > 0 then
            section.set_slot(slot, {value = {type = "item", name = name, quality = "normal"}, min = sum})
            slot = slot + 1
          end
        end
      end
    end
  end

  -- Extra signals (drones, active, fuel)
  slot = self:write_reader_extra_signals(section, slot)

  -- Clear leftover slots
  local filters_count = section.filters_count
  for i = slot, filters_count do section.clear_slot(i) end
end

function active_depot:update_sticker()
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
    scale = 1.5
  }
end

function active_depot:update()
  self._drone_count_cache = nil
  self:check_fuel_amount()
  self:check_drone_amount()
  self:check_drone_validity()
  self:update_priority_from_circuit()
  self:update_channel_from_circuit()
  if self.fluid_mode then
    -- Keep furnace active for recipe auto-detection and icon display
    -- Reset crafting_progress to prevent actual recipe completion
    if not self.entity.active then
      self.entity.active = true
    end
    self.entity.crafting_progress = 0
    self:update_contents()
    self:scan_and_push_fluid()
  else
    self:update_contents()
    self:scan_and_push()
  end
  self:update_circuit_reader()
  self:update_disabled_visual()
  self:update_sticker()
end

function active_depot:add_to_network()
  self.network_id = self.road_network.add_depot(self, "active")
end

function active_depot:remove_from_network()
  self.road_network.remove_depot(self, "active")
  self.network_id = nil
end

function active_depot:on_removed(event)
  self:suicide_all_drones()
  if self.corpse and self.corpse.valid then
    self.corpse.destroy()
  end
  if self.item_chest and self.item_chest.valid then
    base.return_inventory(self.item_chest, event)
    self.item_chest.destroy()
  end
  if self.drone_chest and self.drone_chest.valid then
    base.return_inventory(self.drone_chest, event)
    self.drone_chest.destroy()
  end
end

return active_depot
