-- Shared depot methods to eliminate duplication across depot types.
-- Usage: local base = require("script/depot_base")
--        base.mixin(my_depot, "drone", "requester")

local depot_base = {}

-- Shared constants and caches
local fuel_fluid
depot_base.get_fuel_fluid = function()
  if not fuel_fluid then
    fuel_fluid = prototypes.recipe["fuel-depots"].products[1].name
  end
  return fuel_fluid
end

-- Insert fuel into the correct fluidbox.
-- For most depots, fuel lives in fluidbox[1] (the recipe ingredient box).
-- For active depot fluid mode, box[1] may hold the handled fluid instead,
-- so fall back to insert_fluid which finds a free box.
depot_base.insert_fuel = function(entity, amount)
  local fuel_name = depot_base.get_fuel_fluid()
  local box = entity.fluidbox[1]
  if not box then
    entity.fluidbox[1] = {name = fuel_name, amount = amount}
  elseif box.name == fuel_name then
    entity.fluidbox[1] = {name = fuel_name, amount = box.amount + amount, temperature = box.temperature}
  else
    -- Box[1] holds a different fluid (e.g. handled fluid in furnace mode)
    entity.insert_fluid({name = fuel_name, amount = amount})
  end
end

-- Save/restore wire connections across entity swap (destroy + create)
function depot_base.save_wires(entity)
  local saved = {}
  for conn_id, connector in pairs(entity.get_wire_connectors()) do
    saved[conn_id] = {}
    for _, conn in pairs(connector.connections) do
      table.insert(saved[conn_id], conn.target)
    end
  end
  return saved
end

function depot_base.restore_wires(entity, saved)
  for conn_id, targets in pairs(saved) do
    local new_connectors = entity.get_wire_connectors()
    local new_conn = new_connectors[conn_id]
    if new_conn then
      for _, target in pairs(targets) do
        new_conn.connect_to(target)
      end
    end
  end
end

-- Circuit condition evaluation for writer (constant-combinator stores config in storage.writer_config)
local evaluate_comparator = function(comp, a, b)
  if comp == ">" then return a > b
  elseif comp == "<" then return a < b
  elseif comp == "=" then return a == b
  elseif comp == ">=" then return a >= b
  elseif comp == "<=" then return a <= b
  elseif comp == "!=" then return a ~= b
  end
  return false
end

depot_base.is_writer_disabled = function(depot)
  if not (depot.circuit_writer and depot.circuit_writer.valid) then return false end
  local config = storage.writer_config and storage.writer_config[depot.circuit_writer.unit_number]
  if not config or not config.condition_signal then return false end
  local value = depot.circuit_writer.get_signal(config.condition_signal,
    defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green)
  local rhs
  if config.condition_constant_signal then
    rhs = depot.circuit_writer.get_signal(config.condition_constant_signal,
      defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green)
  else
    rhs = config.condition_constant or 0
  end
  return not evaluate_comparator(config.condition_comparator or ">", value, rhs)
end

local valid_item_cache = {}
depot_base.is_valid_item = function(item_name)
  local bool = valid_item_cache[item_name]
  if bool ~= nil then return bool end
  valid_item_cache[item_name] = prototypes.item[item_name] ~= nil
  return valid_item_cache[item_name]
end

local valid_fluid_cache = {}
depot_base.is_valid_fluid = function(fluid_name)
  local bool = valid_fluid_cache[fluid_name]
  if bool ~= nil then return bool end
  valid_fluid_cache[fluid_name] = prototypes.fluid[fluid_name] ~= nil
  return valid_fluid_cache[fluid_name]
end

depot_base.convert_contents_to_dict = function(contents_array, target)
  local result = target or {}
  if target then
    for k in pairs(result) do result[k] = nil end
  end
  local supply_key = shared.supply_key
  for _, item in pairs(contents_array) do
    local key = supply_key(item.name, item.quality)
    result[key] = (result[key] or 0) + item.count
  end
  return result
end

depot_base.request_mode = {
  item = 1,
  fluid = 2
}

local band = bit32.band
depot_base.channels_match = function(a, b)
  return band(a or shared.default_channel, b or shared.default_channel) ~= 0
end

local stack_cache = {}
depot_base.get_stack_size_for_item = function(item)
  local size = stack_cache[item]
  if not size then
    local prototype = prototypes.item[item]
    if not prototype then error("Unknown item: "..item) end
    size = prototype.stack_size
    stack_cache[item] = size
  end
  return size
end

-- Create a quality-scaled drone chest at the entity's position with inventory filters set.
function depot_base.create_drone_chest(entity)
  local quality_level = entity.quality and entity.quality.level or 0
  local chest_name = shared.drone_chest_name[quality_level] or "depot-drone-chest"
  local drone_chest = entity.surface.create_entity{
    name = chest_name,
    position = entity.position,
    force = entity.force
  }
  drone_chest.destructible = false
  local drone_inv = drone_chest.get_inventory(defines.inventory.chest)
  for i = 1, #drone_inv do
    drone_inv.set_filter(i, {name = "transport-drone", quality = "normal", comparator = ">="})
  end
  return drone_chest
end

-- Base blueprint tag read/save for non-drone depots.
-- Returns the ttags subtable for callers that need to read extra fields.
function depot_base.read_base_tags(self, tags)
  if not tags or not tags.transport_depot_tags then return end
  local ttags = tags.transport_depot_tags
  if ttags.priority then
    self.base_priority = ttags.priority
    self.priority = self.base_priority
  end
  if ttags.priority_signal then
    self.priority_signal = ttags.priority_signal
  end
  if ttags.channel then
    self.base_channel = ttags.channel
    self.channel = self.base_channel
  end
  if ttags.allow_central_dispatch == false then
    self.allow_central_dispatch = false
  end
  return ttags
end

function depot_base.save_base_tags(self)
  local tags = {}
  if self.base_priority and self.base_priority ~= shared.default_priority then
    tags.priority = self.base_priority
  end
  if self.priority_signal then
    tags.priority_signal = self.priority_signal
  end
  if self.base_channel and self.base_channel ~= shared.default_channel then
    tags.channel = self.base_channel
  end
  if self.allow_central_dispatch == false then
    tags.allow_central_dispatch = false
  end
  if not next(tags) then return end
  return tags
end

-- Return items from a hidden chest to the player who mined the depot,
-- spilling on the ground anything that doesn't fit.
depot_base.return_inventory = function(chest, event)
  if not (chest and chest.valid) then return end
  local inv = chest.get_inventory(defines.inventory.chest)
  if not inv then return end
  local player_inv
  if event and event.player_index then
    local player = game.get_player(event.player_index)
    if player then player_inv = player.get_main_inventory() end
  end
  for i = 1, #inv do
    local stack = inv[i]
    if stack.valid_for_read then
      if player_inv then
        local inserted = player_inv.insert(stack)
        if inserted < stack.count then
          chest.surface.spill_item_stack{
            position = chest.position,
            stack = {name = stack.name, count = stack.count - inserted, quality = stack.quality.name},
            force = chest.force
          }
        end
      else
        chest.surface.spill_item_stack{
          position = chest.position,
          stack = stack,
          force = chest.force
        }
      end
    end
  end
end

-- ============================================================
-- Common methods for ALL depot types
-- ============================================================

local common = {}

function common:get_corpse_position()
  local entity = self.assembler or self.entity
  local position = entity.position
  local offset = self.corpse_offsets[entity.direction]
  return {position.x + offset[1], position.y + offset[2]}
end

function common:get_corpse()
  if self.corpse and self.corpse.valid then
    return self.corpse
  end
  local corpse_position = self:get_corpse_position()
  local corpse_name = self.corpse_entity_name or "transport-caution-corpse"
  local corpse = self.entity.surface.create_entity{name = corpse_name, position = corpse_position}
  corpse.corpse_expires = false
  self.corpse = corpse
  self.node_position = {math.floor(corpse_position[1]), math.floor(corpse_position[2])}
  return corpse
end

function common:say(string, player_index)
  local params = {text = string, surface = self.entity.surface, target = self.entity.position, color = {0.5, 1, 0.5}, time_to_live = 120, scale = 1.5}
  if player_index then params.players = {player_index} end
  rendering.draw_text(params)
end

function common:update_priority_from_circuit()
  local new_priority
  if not (self.circuit_writer and self.circuit_writer.valid) then
    new_priority = self.base_priority
  else
    local signal = self.priority_signal or {type = "virtual", name = "signal-P"}
    local value = self.circuit_writer.get_signal(
      signal,
      defines.wire_connector_id.circuit_red,
      defines.wire_connector_id.circuit_green
    )
    new_priority = value ~= 0 and value or self.base_priority
  end
  if self.priority ~= new_priority then
    self.priority = new_priority
    self:mark_bucket_dirty()
  end
end

local default_channel_signal = {type = "virtual", name = "signal-C"}

function common:update_channel_from_circuit()
  local new_channel
  if not (self.circuit_writer and self.circuit_writer.valid) then
    new_channel = self.base_channel
  else
    local value = self.circuit_writer.get_signal(
      default_channel_signal,
      defines.wire_connector_id.circuit_red,
      defines.wire_connector_id.circuit_green
    )
    new_channel = value ~= 0 and value or self.base_channel
  end
  if self.channel ~= new_channel then
    self.channel = new_channel
  end
end

local default_threshold_signal = {type = "virtual", name = "signal-T"}

function common:update_threshold_from_circuit()
  if not (self.circuit_writer and self.circuit_writer.valid) then
    self.circuit_threshold = nil
    return
  end
  local value = self.circuit_writer.get_signal(
    default_threshold_signal,
    defines.wire_connector_id.circuit_red,
    defines.wire_connector_id.circuit_green
  )
  self.circuit_threshold = value ~= 0 and value or nil
end

function common:get_supply_threshold()
  return self.circuit_threshold or self.supply_threshold or 0
end

function common:update_disabled_visual()
  local status = nil
  if depot_base.is_writer_disabled(self) then
    status = {
      diode = defines.entity_status_diode.red,
      label = {"writer-depot-disabled"}
    }
  end
  if self.entity and self.entity.valid then
    self.entity.custom_status = status
  end
  if self.assembler and self.assembler.valid then
    self.assembler.custom_status = status
  end
end

-- Shared circuit reader update: supports depot-content / network / network-excl. modes
-- local_count: this depot's local content for the item (used by mode 3 to subtract).
-- Returns true if network mode was handled, false if caller should use legacy local-content logic.
function common:update_circuit_reader_network(item_name, signal_type, local_count)
  if not (self.circuit_reader and self.circuit_reader.valid) then return true end
  if not self.network_id then return true end

  local rconfig = storage.reader_config and storage.reader_config[self.circuit_reader.unit_number]
  local mode = rconfig and rconfig.mode or 1  -- 1=depot, 2=network, 3=network excl.
  if mode == 1 then return false end  -- caller handles local content

  local behavior = self.circuit_reader.get_or_create_control_behavior()
  local section = behavior.get_section(1)
  if not section then section = behavior.add_section() end

  if not item_name then
    section.clear_slot(1)
    return true
  end

  local supply = self.road_network.get_network_item_supply(self.network_id)
  local quality = self.item_quality or "normal"
  local key = shared.supply_key(item_name, quality)
  local counts = supply and supply[key]
  local sum = 0
  if counts then
    for _, count in pairs(counts) do
      sum = sum + count
    end
  end

  if mode == 3 then
    sum = math.max(0, sum - (local_count or 0))
  end

  local signal_value = {type = signal_type or "item", name = item_name, quality = quality}
  section.set_slot(1, {value = signal_value, min = sum})
  return true
end

-- Helper: write a signal to a circuit reader section slot. Returns the next slot index.
local function write_signal(section, slot, rconfig, config_key, default_signal, value)
  local sig = (rconfig and rconfig[config_key]) or default_signal
  section.set_slot(slot, {value = {type = sig.type, name = sig.name, quality = sig.quality or "normal"}, min = value})
  return slot + 1
end

-- Get the item inventory for circuit reader purposes.
-- Handles active depot's item_chest and standard entity inventory.
function common:get_reader_inventory()
  if self.item_chest and self.item_chest.valid then
    return self.item_chest.get_inventory(defines.inventory.chest)
  end
  if self.entity and self.entity.valid then
    return self.entity.get_output_inventory()
  end
end

-- Get the item name for circuit reader stack/capacity lookups.
function common:get_reader_item()
  if self.item and self.item ~= false then return self.item end
  if self.old_contents then
    local name = next(self.old_contents)
    if name then return name end
    if self.storage_filter_item then return self.storage_filter_item end
    if self.entity and self.entity.valid and self.entity.type == "logistic-container" then
      local sf = self.entity.storage_filter
      if sf then return sf.name.name end
    end
  end
  if self.item_chest and self.item_chest.valid then
    local inv = self.item_chest.get_inventory(defines.inventory.chest)
    if inv then
      local contents = inv.get_contents()
      if contents[1] then return contents[1].name end
    end
  end
end

-- Compute max capacity for a depot (items or fluid).
local function compute_max_capacity(self)
  if self.get_max_storage_size then
    return self:get_max_storage_size()
  end
  if self.entity and self.entity.valid and self.entity.fluidbox and #self.entity.fluidbox >= 1 then
    return self.entity.fluidbox.get_capacity(1)
  end
  if not (self.entity and self.entity.valid) then return 0 end
  local inv = self.entity.get_output_inventory()
  if not inv then return 0 end
  local slots = (inv.supports_bar() and inv.get_bar() or (#inv + 1)) - 1
  if slots <= 1 and not inv.supports_bar() then
    local cap_setting = settings.startup["af-mining-drones-capacity"]
    return cap_setting and (cap_setting.value * 100) or 0
  end
  local item_name = self:get_reader_item()
  if item_name then
    local proto = prototypes.item[item_name]
    if proto then return slots * proto.stack_size end
  end
  return slots
end

-- Compute max stacks for a depot.
local function compute_max_stacks(self)
  if self.get_max_storage_size then
    local item_name = self:get_reader_item()
    if item_name then
      local proto = prototypes.item[item_name]
      if proto then return math.floor(self:get_max_storage_size() / proto.stack_size) end
    end
    return 0
  end
  local inv = self:get_reader_inventory()
  if not inv then return 0 end
  if #inv <= 1 and not inv.supports_bar() then
    local cap_setting = settings.startup["af-mining-drones-capacity"]
    if cap_setting then
      local item_name = self:get_reader_item()
      if item_name then
        local proto = prototypes.item[item_name]
        if proto then return math.floor((cap_setting.value * 100) / proto.stack_size) end
      end
    end
    return 0
  end
  return (inv.supports_bar() and inv.get_bar() or (#inv + 1)) - 1
end

-- Compute used stacks for a depot.
local function compute_used_stacks(self)
  local inv = self:get_reader_inventory()
  if not inv then return 0 end
  if #inv <= 1 and not inv.supports_bar() then
    local item_name = self:get_reader_item()
    if item_name then
      local proto = prototypes.item[item_name]
      if proto then
        local total = 0
        for _, item in pairs(inv.get_contents()) do if item.name == item_name then total = total + item.count end end
        return math.ceil(total / proto.stack_size)
      end
    end
    return 0
  end
  local bar = inv.supports_bar() and inv.get_bar() or (#inv + 1)
  local limit = math.min(bar - 1, #inv)
  local used = 0
  for i = 1, limit do
    if inv[i].valid_for_read then used = used + 1 end
  end
  return used
end

-- Write configurable extra signals (drones, active, fuel, capacity) after content slots.
-- Safe for all depot types - skips drone/active/fuel if methods don't exist.
-- Returns the next free slot index.
function common:write_reader_extra_signals(section, start_slot)
  if not (self.circuit_reader and self.circuit_reader.valid) then return start_slot end
  local rconfig = storage.reader_config and storage.reader_config[self.circuit_reader.unit_number]
  local slot = start_slot

  -- Drone count (default: on, signal-D)
  if self.get_drone_item_count and not (rconfig and rconfig.show_drones == false) then
    slot = write_signal(section, slot, rconfig, "drone_signal", {type = "virtual", name = "signal-D"}, self:get_drone_item_count())
  end

  -- Active drone count (default: off)
  if self.get_active_drone_count and rconfig and rconfig.show_active then
    slot = write_signal(section, slot, rconfig, "active_signal", {type = "virtual", name = "signal-A"}, self:get_active_drone_count())
  end

  -- Fuel available (default: off)
  if self.get_fuel_amount and rconfig and rconfig.show_fuel then
    slot = write_signal(section, slot, rconfig, "fuel_signal", {type = "virtual", name = "fuel-signal"}, self:get_fuel_amount())
  end

  -- Max capacity (default: off)
  if rconfig and rconfig.show_capacity then
    slot = write_signal(section, slot, rconfig, "capacity_signal", {type = "virtual", name = "signal-M"}, math.floor(compute_max_capacity(self)))
  end

  -- Stack size (default: off)
  if rconfig and rconfig.show_stack_size then
    local item_name = self:get_reader_item()
    if item_name then
      local proto = prototypes.item[item_name]
      if proto then
        slot = write_signal(section, slot, rconfig, "stack_size_signal", {type = "virtual", name = "signal-S"}, proto.stack_size)
      end
    end
  end

  -- Max stacks (default: off)
  if rconfig and rconfig.show_max_stacks then
    local max_stacks = compute_max_stacks(self)
    if max_stacks > 0 then
      slot = write_signal(section, slot, rconfig, "max_stacks_signal", {type = "virtual", name = "signal-T"}, max_stacks)
    end
  end

  -- Used stacks (default: off)
  if rconfig and rconfig.show_used_stacks then
    local used = compute_used_stacks(self)
    if used > 0 then
      slot = write_signal(section, slot, rconfig, "used_stacks_signal", {type = "virtual", name = "signal-U"}, used)
    end
  end

  -- Returning stacks (default: off, dispatcher only)
  if self.player_slots and rconfig and rconfig.show_returning then
    local returning = 0
    local inv = self:get_reader_inventory()
    if inv then
      local bar = inv.supports_bar() and inv.get_bar() or (#inv + 1)
      for i = bar, #inv do
        if inv[i].valid_for_read then returning = returning + 1 end
      end
    end
    slot = write_signal(section, slot, rconfig, "returning_signal", {type = "virtual", name = "signal-R"}, returning)
  end

  return slot
end

-- Swap the main entity to a different prototype, preserving all state.
-- Used for multi-pipe toggle (entity variant swap).
function common:swap_fluid_entity(new_name)
  local old = self.entity
  if old.name == new_name then return end

  -- Save fluidbox contents
  local saved_fluids = {}
  for i = 1, #old.fluidbox do
    saved_fluids[i] = old.fluidbox[i]
  end

  -- Save recipe (assembling machines)
  local saved_recipe = nil
  local saved_recipe_locked = false
  if old.type == "assembling-machine" then
    local recipe = old.get_recipe()
    if recipe then saved_recipe = recipe.name end
    saved_recipe_locked = old.recipe_locked
  end

  local saved_active = old.active

  local saved_wires = depot_base.save_wires(old)

  local pos = old.position
  local force = old.force
  local surface = old.surface
  local direction = old.direction
  local quality = old.quality and old.quality.name

  -- Remove from data structures
  local depots = storage.transport_depots.depots
  self:remove_from_network()
  local node = self.road_network.get_node(self.surface_index, self.node_position[1], self.node_position[2])
  if node and node.depots then node.depots[self.index] = nil end
  depots[self.index] = nil

  -- Try fast_replace first (preserves pipe connections with neighbors)
  local create_params = {name = new_name, position = pos, force = force, direction = direction, fast_replace = true, spill = false}
  if quality then create_params.quality = quality end
  local new_entity = surface.create_entity(create_params)

  if not new_entity then
    -- Fast replace failed (incompatible types), fall back to destroy + create
    old.destroy()
    create_params.fast_replace = nil
    create_params.spill = nil
    new_entity = surface.create_entity(create_params)
  end

  -- Update self
  self.entity = new_entity
  self.index = tostring(new_entity.unit_number)
  new_entity.rotatable = false

  -- Restore recipe before fluid (assembling machines)
  if saved_recipe and new_entity.type == "assembling-machine" then
    new_entity.set_recipe(saved_recipe)
    new_entity.recipe_locked = saved_recipe_locked
  end

  new_entity.active = saved_active

  -- Restore fluidbox contents
  for i, fluid in pairs(saved_fluids) do
    if fluid and i <= #new_entity.fluidbox then
      new_entity.fluidbox[i] = fluid
    end
  end

  depot_base.restore_wires(new_entity, saved_wires)

  -- Clear stale caches
  self.output_inventory = nil
  self._drone_count_cache = nil

  -- Destroy old rendering (sticker + quality overlay)
  if self.rendering and self.rendering.valid then
    self.rendering:destroy()
    self.rendering = nil
  end
  if self.quality_rendering and self.quality_rendering.valid then
    self.quality_rendering:destroy()
    self.quality_rendering = nil
  end

  -- Re-register
  depots[self.index] = self
  script.register_on_object_destroyed(new_entity)
  if node and node.depots then node.depots[self.index] = self end
  self:add_to_network()
  if self.add_to_update_bucket then
    self.add_to_update_bucket(self.index)
  end
end

function common:set_multi_pipe(value)
  local base_name = shared.multi_pipe_base[self.entity.name] or self.entity.name
  local is_multi = shared.multi_pipe_base[self.entity.name] ~= nil
  if is_multi == value then return end

  local target_name
  if value then
    target_name = shared.multi_pipe_variants[base_name]
  else
    target_name = base_name
  end
  if not target_name then return end

  self:swap_fluid_entity(target_name)
end

-- ============================================================
-- Drone-bearing depot methods (request, buffer, fuel)
-- ============================================================

local fuel_amount_per_drone = shared.fuel_amount_per_drone
local max = math.max

local drone = {}

function drone:get_drone_inventory()
  if not self.drone_inventory then
    self.drone_inventory = self.drone_chest.get_inventory(defines.inventory.chest)
  end
  return self.drone_inventory
end

function drone:get_drone_item_count()
  if self._drone_count_cache then
    return self._drone_count_cache
  end
  local count = 0
  for _, item in pairs(self:get_drone_inventory().get_contents()) do
    if item.name == "transport-drone" then
      count = count + item.count
    end
  end
  self._drone_count_cache = count
  return count
end

local quality_order = {"normal", "uncommon", "rare", "epic", "legendary"}

function drone:get_next_drone_quality()
  local active_by_quality = {}
  if self.drones then
    for _, d in pairs(self.drones) do
      local q = d.quality or "normal"
      active_by_quality[q] = (active_by_quality[q] or 0) + 1
    end
  end
  local available = {}
  for _, item in pairs(self:get_drone_inventory().get_contents()) do
    if item.name == "transport-drone" then
      local active = active_by_quality[item.quality] or 0
      if item.count > active then
        available[item.quality] = true
      end
    end
  end
  -- Prefer highest quality (legendary first)
  for i = #quality_order, 1, -1 do
    if available[quality_order[i]] then
      return quality_order[i]
    end
  end
end

function drone:get_active_drone_count()
  if self._active_count == nil then
    self._active_count = table_size(self.drones)
  end
  return self._active_count
end

function drone:register_active_drone(d)
  self.drones[d.index] = d
  self._active_count = (self._active_count or 0) + 1
end

function drone:unregister_active_drone(key)
  if self.drones[key] then
    self.drones[key] = nil
    self._active_count = max((self._active_count or 1) - 1, 0)
  end
end

function drone:get_drone_counts_by_quality()
  local counts = {}
  for _, item in pairs(self:get_drone_inventory().get_contents()) do
    if item.name == "transport-drone" then
      local q = item.quality
      if not counts[q] then counts[q] = {inventory = 0, active = 0} end
      counts[q].inventory = counts[q].inventory + item.count
    end
  end
  if self.drones then
    for _, d in pairs(self.drones) do
      local q = d.quality or "normal"
      if not counts[q] then counts[q] = {inventory = 0, active = 0} end
      counts[q].active = counts[q].active + 1
    end
  end
  -- Return ordered array of {quality, inventory, active, total}
  local result = {}
  for _, q in pairs(quality_order) do
    local c = counts[q]
    if c then
      result[#result + 1] = {quality = q, inventory = c.inventory, active = c.active, total = c.inventory + c.active}
    end
  end
  return result
end

function drone:can_spawn_drone()
  return self:get_drone_item_count() > self:get_active_drone_count()
end

function drone:check_drone_validity()
  self._validity_counter = (self._validity_counter or 0) + 1
  if self._validity_counter < 5 then return end
  self._validity_counter = 0
  for k, drone in pairs (self.drones) do
    if not drone.entity or not drone.entity.valid then
      if drone.clear_drone_data then
        drone:clear_drone_data()
      end
      self:unregister_active_drone(k)
    elseif k ~= drone.index then
      -- Stale key from portal transit (index changed, old key left behind)
      self:unregister_active_drone(k)
    end
  end
end

function drone:remove_drone(drone, remove_item)
  self:unregister_active_drone(drone.index)
  if remove_item then
    self:get_drone_inventory().remove{name = "transport-drone", count = 1, quality = drone.quality or "normal"}
    self._drone_count_cache = nil
  end
  self:update_sticker()
end

function drone:suicide_all_drones()
  for k, drone in pairs (self.drones) do
    if drone.entity.valid then
      drone:suicide()
    else
      drone:clear_drone_data()
      self:remove_drone(drone)
    end
  end
end

function drone:remove_fuel(amount)
  self.entity.remove_fluid({name = depot_base.get_fuel_fluid(), amount = amount})
end

function drone:receive_fuel(amount)
  if amount > 0 then
    depot_base.insert_fuel(self.entity, amount)
  elseif amount < 0 then
    self.entity.remove_fluid({name = depot_base.get_fuel_fluid(), amount = -amount})
  end
end

function drone:read_tags(tags)
  if tags then
    if tags.transport_depot_tags then
      local ttags = tags.transport_depot_tags
      if ttags.drone_qualities or (ttags.drone_count and ttags.drone_count > 0) then
        -- Set logistic request on the drone chest so bots deliver drones
        local sections = self.drone_chest.get_logistic_sections()
        if sections then
          local section = sections.sections[1]
          if not section then
            section = sections.add_section()
          end
          local slot_idx = 1
          if ttags.drone_qualities then
            for quality, count in pairs(ttags.drone_qualities) do
              section.set_slot(slot_idx, {
                value = {type = "item", name = "transport-drone", quality = quality},
                min = count
              })
              slot_idx = slot_idx + 1
            end
          else
            section.set_slot(1, {
              value = {type = "item", name = "transport-drone", quality = "normal"},
              min = ttags.drone_count
            })
          end
        end
      end
      if ttags.priority then
        self.base_priority = ttags.priority
        self.priority = self.base_priority
      end
      if ttags.priority_signal then
        self.priority_signal = ttags.priority_signal
      end
      if ttags.storage_limit then
        self.storage_limit = ttags.storage_limit
      end
      if ttags.ignore_capacity_bonus then
        self.ignore_capacity_bonus = true
      end
      if ttags.full_stack_only then
        self.full_stack_only = true
      end
      if ttags.channel then
        self.base_channel = ttags.channel
        self.channel = self.base_channel
      end
      if ttags.supply_threshold then
        self.supply_threshold = ttags.supply_threshold
      end
      if ttags.requested_drones then
        self.requested_drones = ttags.requested_drones
      end
      if ttags.allow_central_dispatch == false then
        self.allow_central_dispatch = false
      end
      if shared.quality_enabled and ttags.item_quality and self.set_item_quality then
        self._pending_quality = ttags.item_quality
      end
      if ttags.fluid_mode and self.set_fluid_mode then
        self:set_fluid_mode(true)
      end
    end
  end
end

function drone:save_to_blueprint_tags()
  local tags = {}
  -- Only save drone counts if the depot has requested_drones > 0
  if self.requested_drones and self.requested_drones > 0 then
    local total = 0
    local drone_qualities = {}
    local has_quality = false
    for _, entry in ipairs(self:get_drone_counts_by_quality()) do
      total = total + entry.total
      drone_qualities[entry.quality] = entry.total
      if entry.quality ~= "normal" then has_quality = true end
    end
    -- If no actual drones, check pending logistic requests on the drone chest
    if total == 0 and self.drone_chest and self.drone_chest.valid then
      local sections = self.drone_chest.get_logistic_sections()
      if sections then
        local section = sections.sections[1]
        if section then
          for i = 1, section.filters_count do
            local slot = section.get_slot(i)
            if slot and slot.value and slot.value.name == "transport-drone" and slot.min and slot.min > 0 then
              local q = slot.value.quality or "normal"
              drone_qualities[q] = (drone_qualities[q] or 0) + slot.min
              total = total + slot.min
              if q ~= "normal" then has_quality = true end
            end
          end
        end
      end
    end
    if total > 0 then
      tags.drone_count = total
      if has_quality then
        tags.drone_qualities = drone_qualities
      end
    end
  end
  if self.base_priority and self.base_priority ~= shared.default_priority then
    tags.priority = self.base_priority
  end
  if self.priority_signal then
    tags.priority_signal = self.priority_signal
  end
  if self.storage_limit then
    tags.storage_limit = self.storage_limit
  end
  if self.ignore_capacity_bonus then
    tags.ignore_capacity_bonus = true
  end
  if self.full_stack_only then
    tags.full_stack_only = true
  end
  if self.base_channel and self.base_channel ~= shared.default_channel then
    tags.channel = self.base_channel
  end
  if self.supply_threshold then
    tags.supply_threshold = self.supply_threshold
  end
  if self.requested_drones then
    tags.requested_drones = self.requested_drones
  end
  if self.allow_central_dispatch == false then
    tags.allow_central_dispatch = false
  end
  if shared.quality_enabled and self.item_quality and self.item_quality ~= "normal" then
    tags.item_quality = self.item_quality
  end
  if self.fluid_mode then
    tags.fluid_mode = true
    local recipe = self.entity.get_recipe()
    if recipe then tags.fluid_recipe = recipe.name end
  end
  if not next(tags) then return end
  return tags
end

function drone:minimum_fuel_amount()
  return max(fuel_amount_per_drone * 2, fuel_amount_per_drone * self:get_drone_item_count() * 0.2)
end

function drone:max_fuel_amount()
  return (self:get_drone_item_count() * fuel_amount_per_drone)
end

local fuel_icon_param = {type = "virtual", name = "fuel-signal"}
function drone:show_fuel_alert(message)
  for k, player in pairs (game.connected_players) do
    player.add_custom_alert(self.entity, fuel_icon_param, message, true)
  end
end

local drone_icon_param = {type = "item", name = "transport-drone"}
function drone:show_drone_alert(message)
  for k, player in pairs (game.connected_players) do
    player.add_custom_alert(self.entity, drone_icon_param, message, true)
  end
end

function drone:on_removed(event)
  self:suicide_all_drones()
  if self.corpse and self.corpse.valid then
    self.corpse.destroy()
  end
  if self.drone_chest and self.drone_chest.valid then
    depot_base.return_inventory(self.drone_chest, event)
    self.drone_chest.destroy()
  end
end

-- ============================================================
-- Requester depot methods (request, buffer)
-- ============================================================

local requester = {}

local drone_fluid_capacity = shared.drone_fluid_capacity

function requester:check_fuel_amount()
  if not self.item then return end

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

  local channels_match = depot_base.channels_match
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

function requester:check_drone_amount()
  if not self.item then return end

  local current_amount = self:get_drone_item_count()
  if current_amount > 0 then
    return
  end

  self:show_drone_alert({"no-drone-in-depot"})
end

function requester:dispatch_drone(depot, count)
  local drone_quality = self:get_next_drone_quality()
  if not drone_quality then return false end
  local drone = self.transport_drone.new(self, self.item, drone_quality)
  if not drone then return false end
  self._drone_count_cache = nil
  drone:pickup_from_supply(depot, self.item, count, self.item_quality)
  self:remove_fuel(fuel_amount_per_drone)
  self:register_active_drone(drone)
  self:update_sticker()
  return true
end

function requester:get_stack_size()
  if self.mode == depot_base.request_mode.item then
    return depot_base.get_stack_size_for_item(self.item)
  end
  if self.mode == depot_base.request_mode.fluid then
    return drone_fluid_capacity
  end
  return 0
end

function requester:get_request_size()
  if self.ignore_capacity_bonus then
    return self:get_stack_size()
  end
  return self:get_stack_size() * (1 + self.transport_technologies.get_transport_capacity_bonus(self.entity.force.index))
end

function requester:get_storage_size()
  if self.mode == depot_base.request_mode.fluid then
    return shared.request_depot_fluid_capacity
  end
  return self:get_drone_item_count() * self:get_request_size()
end

function requester:get_max_storage_size()
  local inv = self:get_drone_inventory()
  local slots = #inv
  local size = slots * self:get_request_size()
  if self.mode == depot_base.request_mode.fluid then
    size = math.min(size, shared.request_depot_fluid_capacity)
  end
  return size
end

function requester:get_minimum_request_size()
  local stack_size = self:get_stack_size()

  if self.full_stack_only then
    return stack_size
  end

  local current_amount = self:get_current_amount()
  if current_amount < stack_size and self:get_active_drone_count() == 0 then
    return 1
  end
  local request_size = self:get_request_size()
  if current_amount < request_size then
    return stack_size
  end
  return request_size
end

function requester:should_order()
  if self:get_fuel_amount() < fuel_amount_per_drone then
    return
  end

  if self.circuit_limit == 0 then return end

  local size = self.circuit_limit or self.storage_limit or self:get_storage_size()
  local missing = size - self:get_current_amount() - (self.items_on_the_way or 0)

  local should_send_drone_count = math.ceil(missing / self:get_request_size())
  return self:get_active_drone_count() < should_send_drone_count
end

local overfill_multiplier
local function get_overfill_multiplier()
  if not overfill_multiplier then
    overfill_multiplier = 1 + (settings.global["active-depot-overfill-percent"].value / 100)
  end
  return overfill_multiplier
end

local cached_priority_weight
local cached_balance_threshold
local cached_max_dispatches
depot_base.get_dispatch_settings = function()
  if not cached_priority_weight then
    cached_priority_weight = settings.global["transport-drone-priority-weight"].value
    cached_balance_threshold = settings.global["transport-drone-load-balance-threshold"].value
    cached_max_dispatches = settings.global["transport-drone-max-dispatches-per-tick"].value
  end
  return cached_priority_weight, cached_balance_threshold, cached_max_dispatches
end

depot_base.refresh_settings_cache = function()
  overfill_multiplier = nil
  cached_priority_weight = nil
  cached_balance_threshold = nil
  cached_max_dispatches = nil
end

function requester:get_push_capacity()
  if not self.item or not self.mode then return 0 end
  if self.circuit_limit == 0 then return 0 end
  local size = self.circuit_limit or self.storage_limit or self:get_storage_size()
  local push_size = math.floor(size * get_overfill_multiplier())
  local current = self:get_current_amount()
  local on_the_way = self.items_on_the_way or 0
  return max(0, push_size - current - on_the_way)
end

function requester:set_request_mode()
  self.mode = nil
  local recipe = self.entity.get_recipe()
  if not recipe then return end
  local product = recipe.products and recipe.products[1]
  if not product then return end

  local product_type = product.type
  if product_type == "item" then
    self.mode = depot_base.request_mode.item
    return
  end

  if product_type == "fluid" then
    self.mode = depot_base.request_mode.fluid
    return
  end
end

function requester:get_requested_item()
  local recipe = self.entity.get_recipe()
  if not recipe then return end
  local product = recipe.products and recipe.products[1]
  if not product then return end
  return product.name
end

function requester:update_circuit_writer()
  if not self.circuit_writer then return end

  if not self.circuit_writer.valid then
    self.circuit_writer = nil
    self.circuit_limit = nil
    self.entity.recipe_locked = false
    return
  end

  local config = storage.writer_config and storage.writer_config[self.circuit_writer.unit_number]
  if not config then
    self.circuit_limit = nil
    return
  end

  if not config.use_as_limit and not config.set_recipe then
    self.circuit_limit = nil
    return
  end

  -- Scan wire for first item/fluid signal
  local signals = self.circuit_writer.get_signals(defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green)
  if not signals then
    if config.set_recipe then
      self.entity.recipe_locked = false
      if self.item then
        self.entity.set_recipe(nil)
        self:check_request_change()
      end
    end
    if config.use_as_limit then
      self.circuit_limit = 0
    end
    return
  end

  -- Find the non-virtual signal with the highest count
  local best_sig, best_count = nil, 0
  for _, entry in pairs(signals) do
    local sig = entry.signal
    if sig and sig.type ~= "virtual" and entry.count > 0 and entry.count > best_count
       and prototypes.recipe["request-" .. sig.name] then
      best_sig = sig
      best_count = entry.count
    end
  end

  local found = best_sig ~= nil
  if found then
    if config.set_recipe then
      if best_sig.name ~= self.item then
        self.entity.set_recipe("request-" .. best_sig.name)
        self:check_request_change()
      end
      self.entity.recipe_locked = true
    end
    if config.use_as_limit then
      self.circuit_limit = math.min(best_count, self:get_max_storage_size())
    end
  end

  if not found then
    if config.set_recipe then
      -- Keep last recipe locked; circuit_limit=0 prevents dispatching
      self.entity.recipe_locked = true
    end
    if config.use_as_limit then
      self.circuit_limit = 0
    end
  end
end

function requester:update_sticker()
  if not self.item then
    if self.rendering and self.rendering.valid then
      self.rendering:destroy()
      self.rendering = nil
    end
    if self.quality_rendering and self.quality_rendering.valid then
      self.quality_rendering:destroy()
      self.quality_rendering = nil
    end
    return
  end

  if self.rendering and self.rendering.valid then
    self.rendering.text = self:get_active_drone_count().."/"..self:get_drone_item_count()
  else
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

  local quality = self.item_quality
  if quality and quality ~= "normal" then
    if self.quality_rendering and self.quality_rendering.valid then
      self.quality_rendering.sprite = "quality/" .. quality
    else
      self.quality_rendering = rendering.draw_sprite
      {
        sprite = "quality/" .. quality,
        surface = self.entity.surface.index,
        target = {entity = self.entity, offset = {-0.22, -0.06}},
        only_in_alt_mode = true,
        forces = {self.entity.force},
        x_scale = 0.44,
        y_scale = 0.44
      }
    end
  else
    if self.quality_rendering and self.quality_rendering.valid then
      self.quality_rendering:destroy()
      self.quality_rendering = nil
    end
  end
end

function requester:eject_wrong_quality(player)
  if not self.item or self.mode ~= depot_base.request_mode.item then return end
  local quality = self.item_quality or "normal"
  local inv = self.entity.get_output_inventory()
  for i = 1, #inv do
    local stack = inv[i]
    if stack and stack.valid_for_read then
      if (stack.name ~= self.item) or (stack.quality and stack.quality.name ~= quality) then
        local item_def = {name = stack.name, count = stack.count, quality = stack.quality.name}
        local remaining = item_def.count
        if player and player.valid then
          remaining = remaining - player.insert(item_def)
        end
        if remaining > 0 then
          item_def.count = remaining
          self.entity.surface.spill_item_stack{
            position = self.entity.position,
            stack = item_def,
            force = self.entity.force,
            allow_belts = false
          }
        end
        stack.clear()
      end
    end
  end
end

-- ============================================================
-- Supply-side methods (supply, buffer, fluid, mining)
-- ============================================================

local supplier = {}

function supplier:get_to_be_taken(name)
  return self.to_be_taken[name] or 0
end

function supplier:add_to_be_taken(name, count)
  self.to_be_taken[name] = (self.to_be_taken[name] or 0) + count
end

function supplier:swap_chest_entity(new_name)
  local old = self.entity
  if old.name == new_name then return end

  -- Save inventory
  local inv = old.get_output_inventory()
  local items = {}
  for _, item in pairs(inv.get_contents()) do
    table.insert(items, {name = item.name, count = item.count, quality = item.quality})
  end
  local bar = inv.supports_bar() and inv.get_bar()

  local saved_wires = depot_base.save_wires(old)

  -- Remove from data structures
  local depots = storage.transport_depots.depots
  self:remove_from_network()
  local node = self.road_network.get_node(self.surface_index, self.node_position[1], self.node_position[2])
  if node and node.depots then node.depots[self.index] = nil end
  depots[self.index] = nil

  -- Destroy old, create new
  local pos, force, surface = old.position, old.force, old.surface
  old.destroy()
  local new_entity = surface.create_entity{name = new_name, position = pos, force = force}

  -- Restore inventory
  self.entity = new_entity
  self.index = tostring(new_entity.unit_number)
  local new_inv = new_entity.get_output_inventory()
  for _, item in pairs(items) do
    local inserted = new_inv.insert(item)
    if inserted < item.count then
      surface.spill_item_stack{position = pos, stack = {name = item.name, count = item.count - inserted, quality = item.quality}, force = force}
    end
  end
  if bar and bar <= #new_inv + 1 then new_inv.set_bar(bar) end

  depot_base.restore_wires(new_entity, saved_wires)

  -- Re-register in data structures
  depots[self.index] = self
  script.register_on_object_destroyed(new_entity)
  if node and node.depots then node.depots[self.index] = self end
  self:add_to_network()
  if self.add_to_update_bucket then
    self.add_to_update_bucket(self.index)
  end
end

-- ============================================================
-- Shared request dispatch engine (request, buffer depots)
-- ============================================================

local big = math.huge
local min = math.min
local random = math.random

local function distance(a, b)
  local dx = a[1] - b[1]
  local dy = a[2] - b[2]
  return ((dx * dx) + (dy * dy)) ^ 0.5
end

depot_base.effective_distance = function(depot, node_pos, surface_idx, portal_dist_fn)
  if surface_idx and portal_dist_fn
     and depot.entity.valid and depot.entity.surface_index ~= surface_idx then
    return portal_dist_fn(surface_idx, node_pos,
      depot.entity.surface_index, depot.node_position)
      or distance(depot.node_position, node_pos)
  end
  return distance(depot.node_position, node_pos)
end

local _c_depots = {}
local _c_indices = {}
local _c_scores = {}

function depot_base.make_request_from_supply(self, heuristic_fn)
  local name = self.item
  if not name then return end

  if depot_base.is_writer_disabled(self) then return end
  if not self:can_spawn_drone() then return end
  if not self:should_order() then return end

  local supply_key = shared.supply_key(name, self.item_quality)
  local supply_depots = self.road_network.get_supply_depots(self.network_id, supply_key)
  if not supply_depots then return end

  local request_size = self:get_request_size()
  local minimum_size = self:get_minimum_request_size()

  local active_limit = self.circuit_limit or self.storage_limit
  if active_limit then
    local missing = active_limit - self:get_current_amount() - (self.items_on_the_way or 0)
    request_size = math.min(missing, request_size)
    minimum_size = 1
  end

  local priority_weight, balance_threshold, max_dispatches = depot_base.get_dispatch_settings()
  local node_pos = self.node_position
  local surface_idx = self.entity.surface_index
  local portal_dist = self.road_network.portal_distance
  local channels_match = depot_base.channels_match

  -- Score all supply depots
  local candidate_count = 0
  local get_depot = self.get_depot
  local my_channel = self.channel
  for depot_index, count in pairs(supply_depots) do
    if count >= minimum_size then
      local depot = get_depot(depot_index)
      if depot and channels_match(my_channel, depot.channel) then
        local score = heuristic_fn(depot, count, request_size, minimum_size, priority_weight, node_pos, surface_idx, portal_dist)
        if score < big then
          candidate_count = candidate_count + 1
          _c_depots[candidate_count] = depot
          _c_indices[candidate_count] = depot_index
          _c_scores[candidate_count] = score
        end
      end
    end
  end

  if candidate_count == 0 then return end

  -- Sort candidates by score (ascending = best first)
  for i = 2, candidate_count do
    local key_d, key_i, key_s = _c_depots[i], _c_indices[i], _c_scores[i]
    local j = i - 1
    while j > 0 and _c_scores[j] > key_s do
      _c_depots[j+1] = _c_depots[j]
      _c_indices[j+1] = _c_indices[j]
      _c_scores[j+1] = _c_scores[j]
      j = j - 1
    end
    _c_depots[j+1] = key_d
    _c_indices[j+1] = key_i
    _c_scores[j+1] = key_s
  end

  -- Load balancing: pick random start among eligible candidates
  local ci = 1
  if balance_threshold > 0 and candidate_count > 1 then
    local threshold = _c_scores[1] + balance_threshold
    local eligible = 1
    for i = 2, candidate_count do
      if _c_scores[i] <= threshold then
        eligible = i
      else
        break
      end
    end
    if eligible > 1 then
      ci = random(1, eligible)
    end
  end

  -- Dispatch loop
  local dispatched = 0
  while ci <= candidate_count do
    local depot_index = _c_indices[ci]
    local count = supply_depots[depot_index]
    if not count or count < minimum_size then
      ci = ci + 1
    else
      local send = min(request_size, count)
      if not self:dispatch_drone(_c_depots[ci], send) then break end
      dispatched = dispatched + 1
      if dispatched >= max_dispatches then break end
      if send >= count then
        supply_depots[depot_index] = nil
        ci = ci + 1
      else
        supply_depots[depot_index] = count - send
      end
      if not self:can_spawn_drone() then break end
      if not self:should_order() then break end
    end
  end

  -- Cleanup candidate arrays
  for i = 1, candidate_count do
    _c_depots[i] = nil
    _c_indices[i] = nil
    _c_scores[i] = nil
  end

  self._redispatch = dispatched > 0 and self:can_spawn_drone() and self:should_order()
end

-- ============================================================
-- Mixin function
-- ============================================================

local mixin_groups = {
  common = common,
  drone = drone,
  requester = requester,
  supplier = supplier,
}

function depot_base.mixin(target, ...)
  -- Always apply common
  for name, func in pairs(common) do
    if not target[name] then
      target[name] = func
    end
  end
  -- Apply requested groups
  for _, group_name in ipairs({...}) do
    local group = mixin_groups[group_name]
    if group then
      for name, func in pairs(group) do
        if not target[name] then
          target[name] = func
        end
      end
    end
  end
end

return depot_base
