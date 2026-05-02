local base = require("script/depot_base")
local transport_technologies = require("script/transport_technologies")
local convert_contents_to_dict = base.convert_contents_to_dict

local max = math.max

local storage_depot = {}
storage_depot.metatable = {__index = storage_depot}

storage_depot.corpse_offsets =
{
  [defines.direction.north] = {0, -2},
  [defines.direction.east] = {2, 0},
  [defines.direction.south] = {0, 2},
  [defines.direction.west] = {-2, 0},
}

base.mixin(storage_depot, "supplier")

-- Save mixin version of swap_fluid_entity for use in our override
local base_swap_fluid_entity = storage_depot.swap_fluid_entity

function storage_depot.new(entity, tags)
  local position = entity.position
  local force = entity.force
  local surface = entity.surface
  entity.destructible = false
  entity.rotatable = false
  entity.active = false

  local quality_level = entity.quality and entity.quality.level or 0
  local chest_name = shared.storage_chest_name[quality_level] or "storage-depot-chest"
  local chest = surface.create_entity{name = chest_name, position = position, force = force, player = entity.last_user}
  chest.get_output_inventory().set_bar(1)

  local depot =
  {
    entity = chest,
    assembler = entity,
    to_be_taken = {},
    index = tostring(chest.unit_number),
    old_contents = {},
    items_on_the_way = 0,
    score_bonus = 0.001,
    priority = shared.default_priority,
    base_priority = shared.default_priority,
    channel = shared.default_channel,
    base_channel = shared.default_channel,
    fluid_mode = false,
    allow_bots = false,
    storage_filter_item = nil,
    saved_bar = nil,
  }
  setmetatable(depot, storage_depot.metatable)

  depot:get_corpse()
  depot:read_tags(tags)

  return depot

end

-- Override get_corpse_position to use assembler instead of entity
function storage_depot:get_corpse_position()
  local position = self.assembler.position
  local offset = self.corpse_offsets[self.assembler.direction]
  return {position.x + offset[1], position.y + offset[2]}
end

-- Override swap_fluid_entity to keep assembler in sync during fluid mode
function storage_depot:swap_fluid_entity(new_name)
  base_swap_fluid_entity(self, new_name)
  if self.fluid_mode then
    self.assembler = self.entity
    -- Recreate corpse since assembler reference changed
    if self.corpse and self.corpse.valid then
      self.corpse.destroy()
    end
    self:get_corpse()
  end
end

local BLINK_COUNT = 6

local function sync_logistic_filter(entity, item_name)
  if item_name then
    entity.storage_filter = {name = item_name, quality = "normal"}
  else
    entity.storage_filter = nil
  end
end

function storage_depot:set_storage_filter(item_name)
  local old_filter = self.storage_filter_item
  self.storage_filter_item = item_name
  if self.fluid_mode then
    -- Clear old fluid when filter changes
    if old_filter and old_filter ~= item_name then
      self.entity.clear_fluid_inside()
    end
    self.old_contents = {}
    return
  end

  local inv = self.entity.get_output_inventory()
  local has_bar = inv.supports_bar()
  if item_name then
    if inv.supports_filters() then
      for i = 1, #inv do
        inv.set_filter(i, {name = item_name, quality = "normal", comparator = ">="})
      end
    end
    -- Restore saved bar, or fully open if none saved (or if saved was fully locked)
    if has_bar then
      local bar = self.saved_bar
      if bar and bar > 1 then
        inv.set_bar(bar)
      else
        inv.set_bar()
      end
    end
  else
    if has_bar then
      -- Save current bar before locking (so we can restore on next filter set)
      local current_bar = inv.get_bar()
      if current_bar and current_bar > 1 then
        self.saved_bar = current_bar
      end
      inv.set_bar(1)
    end
    if inv.supports_filters() then
      for i = 1, #inv do
        inv.set_filter(i, nil)
      end
    end
  end

  if self.allow_bots and self.entity.type == "logistic-container" then
    sync_logistic_filter(self.entity, item_name)
  end
end

function storage_depot:enforce_container_state()
  local inv = self.entity.get_output_inventory()
  if inv.supports_bar() then
    if not self.storage_filter_item then
      -- Lock bar when no filter
      if inv.get_bar() ~= 1 then
        inv.set_bar(1)
        self._filter_blink = BLINK_COUNT
      end
    else
      -- Track player bar changes (including reset via X button)
      local bar = inv.get_bar()
      if bar > #inv then
        self.saved_bar = nil
      elseif bar > 1 then
        self.saved_bar = bar
      end
    end
  end
  -- Sync native storage filter on logistic containers (adopt player changes)
  if self.allow_bots and self.entity.type == "logistic-container" then
    local current = self.entity.storage_filter
    local current_name = current and (type(current.name) == "string" and current.name or current.name.name)
    if self.storage_filter_item ~= current_name then
      self:set_storage_filter(current_name)
      -- Update the chooser in the panel if the player has it open
      for _, player in pairs(game.connected_players) do
        if player.opened == self.entity then
          local panel = player.gui.relative["depot-panel-container"]
          local inner = panel and panel["panel-inner"]
          local sf_flow = inner and inner["storage-filter-flow"]
          local chooser = sf_flow and sf_flow["storage-filter-chooser"]
          if chooser then chooser.elem_value = current_name end
        end
      end
    end
  end
  -- Blink the "Storage filter:" label when player tampers with bar or logistic filter
  if self._filter_blink and self._filter_blink > 0 then
    self._filter_blink = self._filter_blink - 1
    local on = (self._filter_blink % 2 == 1)
    for _, player in pairs(game.connected_players) do
      if player.opened == self.entity then
        local panel = player.gui.relative["depot-panel-container"]
        local inner = panel and panel["panel-inner"]
        local sf_flow = inner and inner["storage-filter-flow"]
        if sf_flow then
          local label = sf_flow["storage-filter-label"]
          if label then label.style.font_color = on and {1, 0.5, 0} or {1, 1, 1} end
        end
      end
    end
  end
end

function storage_depot:set_allow_bots(value)
  if (self.allow_bots or false) == value then return end
  if self.fluid_mode then return end
  self.allow_bots = value

  local ql = self.assembler.quality and self.assembler.quality.level or 0
  local new_name
  if value then
    new_name = shared.storage_chest_name_logistic[ql] or "storage-depot-chest-logistic"
  else
    new_name = shared.storage_chest_name[ql] or "storage-depot-chest"
  end
  self:swap_chest_entity(new_name)
  self._filter_blink = nil

  -- Reapply storage filter after swap (also sets native storage_filter on logistic containers)
  self:set_storage_filter(self.storage_filter_item)
end

function storage_depot:set_fluid_mode(value)
  if (self.fluid_mode or false) == value then return end
  self.fluid_mode = value

  if value then
    -- Item mode -> fluid mode: destroy chest + assembler, create furnace
    local pos = self.assembler.position
    local dir = self.assembler.direction
    local force = self.assembler.force
    local surface = self.assembler.surface
    local quality = self.assembler.quality

    -- Spill inventory contents
    local inv = self.entity.get_output_inventory()
    for _, item in pairs(inv.get_contents()) do
      surface.spill_item_stack{position = pos, stack = {name = item.name, count = item.count, quality = item.quality}, force = force}
    end

    local saved_wires = base.save_wires(self.entity)

    -- Remove from data structures
    local depots = storage.transport_depots.depots
    self:remove_from_network()
    local node = self.road_network.get_node(self.surface_index, self.node_position[1], self.node_position[2])
    if node and node.depots then node.depots[self.index] = nil end
    depots[self.index] = nil

    -- Destroy old entities
    self.entity.destroy()
    self.assembler.destructible = true
    self.assembler.destroy()

    -- Create furnace
    local furnace = surface.create_entity{
      name = shared.storage_depot_fluid_name,
      position = pos,
      direction = dir,
      force = force,
      quality = quality.name,
    }
    furnace.rotatable = false

    -- Update references
    self.entity = furnace
    self.assembler = furnace
    self.index = tostring(furnace.unit_number)
    self.allow_bots = false

    base.restore_wires(furnace, saved_wires)

    -- Re-register
    depots[self.index] = self
    script.register_on_object_destroyed(furnace)
    if node and node.depots then node.depots[self.index] = self end
    self:add_to_network()
    if self.add_to_update_bucket then
      self.add_to_update_bucket(self.index)
    end

    -- Clear filter from item mode (item names are not valid fluid filters)
    self.storage_filter_item = nil
  else
    -- Fluid mode -> item mode: destroy furnace, create assembler + chest
    local pos = self.entity.position
    local dir = self.entity.direction
    local force = self.entity.force
    local surface = self.entity.surface
    local quality = self.entity.quality

    local saved_wires = base.save_wires(self.entity)

    -- Remove from data structures
    local depots = storage.transport_depots.depots
    self:remove_from_network()
    local node = self.road_network.get_node(self.surface_index, self.node_position[1], self.node_position[2])
    if node and node.depots then node.depots[self.index] = nil end
    depots[self.index] = nil

    -- Destroy furnace
    self.entity.destroy()

    -- Create assembler
    local ql = quality and quality.level or 0
    local assembler = surface.create_entity{
      name = "storage-depot",
      position = pos,
      direction = dir,
      force = force,
      quality = quality.name,
    }
    assembler.destructible = false
    assembler.rotatable = false
    assembler.active = false

    -- Create chest (locked until a filter is selected)
    local chest_name = shared.storage_chest_name[ql] or "storage-depot-chest"
    local chest = surface.create_entity{name = chest_name, position = pos, force = force}
    chest.get_output_inventory().set_bar(1)

    -- Update references
    self.entity = chest
    self.assembler = assembler
    self.index = tostring(chest.unit_number)

    base.restore_wires(chest, saved_wires)

    -- Re-register
    depots[self.index] = self
    script.register_on_object_destroyed(chest)
    script.register_on_object_destroyed(assembler)
    if node and node.depots then node.depots[self.index] = self end
    self:add_to_network()
    if self.add_to_update_bucket then
      self.add_to_update_bucket(self.index)
    end

    -- Clear filter from fluid mode (fluid names are not valid item filters)
    self.storage_filter_item = nil
  end

  -- Cleanup visuals
  self.old_contents = {}
  self._contents_buf = nil
  if self.corpse and self.corpse.valid then
    self.corpse.destroy()
  end
  self:get_corpse()
  if self.rendering and self.rendering.valid then
    self.rendering:destroy()
    self.rendering = nil
  end
end

function storage_depot:read_tags(tags)
  local ttags = base.read_base_tags(self, tags)
  if not ttags then return end
  if ttags.bar then
    local quality_level = self.assembler.quality and self.assembler.quality.level or 0
    local max_slots = shared.quality_supply_inventory[quality_level] or 100
    local bar = ttags.bar
    if bar > max_slots + 1 then bar = max_slots + 1 end
    if not self.fluid_mode then
      self.entity.get_output_inventory().set_bar(bar)
    end
  end
  if ttags.fluid_mode and self.set_fluid_mode then
    self:set_fluid_mode(true)
  end
  if ttags.saved_bar then
    self.saved_bar = ttags.saved_bar
  end
  if ttags.storage_filter then
    self:set_storage_filter(ttags.storage_filter)
  end
  if ttags.allow_bots then
    self:set_allow_bots(true)
  end
  if ttags.multi_pipe then
    self:set_multi_pipe(true)
  end
end

function storage_depot:save_to_blueprint_tags()
  local tags = base.save_base_tags(self) or {}
  if not self.fluid_mode then
    tags.bar = self.entity.get_output_inventory().get_bar()
  end
  if self.storage_filter_item then
    tags.storage_filter = self.storage_filter_item
  end
  if self.saved_bar then
    tags.saved_bar = self.saved_bar
  end
  if self.allow_bots then tags.allow_bots = true end
  if self.fluid_mode then tags.fluid_mode = true end
  if shared.multi_pipe_base[self.entity.name] then tags.multi_pipe = true end
  if not next(tags) then return end
  return tags
end

function storage_depot:update_contents()
  local supply = self.road_network.get_network_item_supply(self.network_id)

  local buf = self._contents_buf or {}
  local new_contents

  if base.is_writer_disabled(self) then
    for k in pairs(buf) do buf[k] = nil end
    new_contents = buf
  end

  if not new_contents then
    if self.fluid_mode then
      -- Read from fluidbox in fluid mode
      for k in pairs(buf) do buf[k] = nil end
      local box = self.entity.fluidbox[1]
      if box then
        buf[box.name] = box.amount
      end
      new_contents = buf
    else
      new_contents = convert_contents_to_dict(self.entity.get_output_inventory().get_contents(), buf)
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
  for name, count in pairs(new_contents) do
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

function storage_depot:update_sticker()
  local filter_name = self.storage_filter_item
  local has_items = next(self.old_contents) ~= nil

  -- Only show custom sticker when filtered and empty; the game renders item icons when contents exist
  if filter_name and not has_items then
    local sprite_type = self.fluid_mode and "fluid" or "item"
    local sprite = sprite_type .. "/" .. filter_name
    if self.rendering and self.rendering.valid then
      if self.rendering.sprite ~= sprite then
        self.rendering.sprite = sprite
      end
      return
    end
    self.rendering = rendering.draw_sprite{
      sprite = sprite,
      surface = self.assembler.surface.index,
      target = {entity = self.assembler, offset = {0, -0.3}},
      only_in_alt_mode = true,
      x_scale = 0.85,
      y_scale = 0.85,
    }
  elseif self.rendering and self.rendering.valid then
    self.rendering:destroy()
    self.rendering = nil
  end
end

function storage_depot:update_circuit_reader()
  if not (self.circuit_reader and self.circuit_reader.valid) then return end

  local behavior = self.circuit_reader.get_or_create_control_behavior()
  local section = behavior.get_section(1)
  if not section then section = behavior.add_section() end

  local rconfig = storage.reader_config and storage.reader_config[self.circuit_reader.unit_number]
  local mode = rconfig and rconfig.mode or 1
  local signal_type = self.fluid_mode and "fluid" or "item"

  local slot = 1
  if mode == 1 then
    for name, count in pairs(self.old_contents) do
      if count > 0 then
        section.set_slot(slot, {value = {type = signal_type, name = name, quality = "normal"}, min = count})
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
          sum = max(0, sum - count)
        end
        if sum > 0 then
          section.set_slot(slot, {value = {type = signal_type, name = name, quality = "normal"}, min = sum})
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

function storage_depot:update()
  if not self.network_id then return end
  self:update_priority_from_circuit()
  self:update_channel_from_circuit()
  self:update_threshold_from_circuit()
  self:update_disabled_visual()

  -- Enforce bar/filter and track player changes
  if not self.fluid_mode then
    self:enforce_container_state()
  end

  if self.fluid_mode then
    -- Fluid mode: control furnace active state (like fluid depot)
    local box = self.entity.fluidbox[1]
    if not box then
      if not self.entity.active then
        self.entity.active = true
        self.entity.crafting_progress = 0
      end
    elseif self.entity.active then
      self.entity.active = false
    end
  end

  self:update_contents()
  self:update_circuit_reader()
  self:update_sticker()
end

function storage_depot:give_item(requested_name, requested_count, requested_quality)
  if self.fluid_mode then
    return self.entity.remove_fluid{name = requested_name, amount = requested_count}
  end
  local inventory = self.entity.get_output_inventory()
  local stack = inventory.find_item_stack(requested_name)
  local spoil_percent = stack and stack.spoil_percent or 0
  local remove_filter = {name = requested_name, count = requested_count}
  if requested_quality and requested_quality ~= "normal" then remove_filter.quality = requested_quality end
  local removed_count = inventory.remove(remove_filter)
  return removed_count, spoil_percent > 0 and spoil_percent or nil
end

function storage_depot:get_available_item_count(name, quality)
  if self.fluid_mode then
    return self.entity.get_fluid_count(name) - self:get_to_be_taken(name)
  end
  local key = shared.supply_key(name, quality)
  local filter = (quality and quality ~= "normal") and {name = name, quality = quality} or name
  return self.entity.get_output_inventory().get_item_count(filter) - self:get_to_be_taken(key)
end

function storage_depot:take_item(name, count, temperature, spoil_percent, quality)
  if self.storage_filter_item and self.storage_filter_item ~= name then return end
  if not self.fluid_mode and prototypes.fluid[name] then return end
  if self.fluid_mode then
    -- Insert directly into fluidbox[1] (the storage box)
    local box = self.entity.fluidbox[1]
    if box and box.name == name then
      self.entity.fluidbox[1] = {name = name, amount = box.amount + count, temperature = temperature or box.temperature}
    else
      local fluid = {name = name, amount = count}
      if temperature then fluid.temperature = temperature end
      self.entity.fluidbox[1] = fluid
    end
    return
  end
  local stack = {name = name, count = count}
  if quality and quality ~= "normal" then stack.quality = quality end
  if spoil_percent then stack.spoil_percent = spoil_percent end
  self.entity.get_output_inventory().insert(stack)
end

function storage_depot:get_push_capacity_for_item(item_name)
  if self.storage_filter_item ~= item_name then return 0 end

  if self.fluid_mode then
    local box = self.entity.fluidbox[1]
    local current = box and box.amount or 0
    local capacity = self.entity.fluidbox.get_capacity(1)
    return max(0, capacity - current - (self.items_on_the_way or 0))
  end

  local inv = self.entity.get_output_inventory()
  local empty = inv.count_empty_stacks()
  local proto = prototypes.item[item_name]
  if not proto then return 0 end
  return max(0, empty * proto.stack_size - (self.items_on_the_way or 0))
end

function storage_depot:get_request_size_for_item(item_name)
  if self.fluid_mode then
    return shared.drone_fluid_capacity
  end
  local proto = prototypes.item[item_name]
  if not proto then return 0 end
  return proto.stack_size * (1 + transport_technologies.get_transport_capacity_bonus(self.entity.force.index))
end

function storage_depot:add_to_network()
  self.network_id = self.road_network.add_depot(self, "storage")
  self:update_contents()
end

function storage_depot:remove_from_network()
  self.road_network.remove_depot(self, "storage")
  self.network_id = nil
end

function storage_depot:on_removed(event)

  if self.rendering and self.rendering.valid then
    self.rendering:destroy()
  end

  if self.corpse and self.corpse.valid then
    self.corpse.destroy()
  end

  -- In fluid mode, assembler == entity (single furnace)
  if self.fluid_mode then
    if self.entity.valid then
      self.entity.destroy()
    end
  else
    if self.assembler and self.assembler.valid then
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
end

return storage_depot
