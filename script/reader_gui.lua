-- Custom GUI for the transport-depot-reader (constant-combinator).
-- Config stored in storage.reader_config[unit_number].

local depot_base = require("script/depot_base")
local road_network = require("script/road_network")

local lib = {}

local player_open_reader = {}  -- player_index → {entity, depot, choosers}

local frame_name = "reader_gui_frame"

local mode_items = {"reader-mode-depot", "reader-mode-network", "reader-mode-network-excl"}

local default_drone_signal = {type = "virtual", name = "signal-D"}
local default_active_signal = {type = "virtual", name = "signal-A"}
local default_fuel_signal = {type = "virtual", name = "fuel-signal"}
local default_capacity_signal = {type = "virtual", name = "signal-M"}
local default_stack_size_signal = {type = "virtual", name = "signal-S"}
local default_max_stacks_signal = {type = "virtual", name = "signal-T"}
local default_used_stacks_signal = {type = "virtual", name = "signal-U"}
local default_returning_signal = {type = "virtual", name = "signal-R"}

-- Find the depot that has this reader entity attached
local function find_depot_for_reader(reader_entity)
  local depot_data = storage.transport_depots
  if not depot_data then return nil end
  local reader_un = reader_entity.unit_number
  for _, depot in pairs(depot_data.depots) do
    if depot.circuit_reader and depot.circuit_reader.valid
       and depot.circuit_reader.unit_number == reader_un then
      return depot
    end
  end
  return nil
end

local function get_depot_display_name(depot)
  if not depot then return "" end
  local entity = depot.assembler or depot.entity
  if not (entity and entity.valid) then return "" end
  return entity.localised_name
end

local function get_config(reader_entity)
  if not storage.reader_config then return nil end
  return storage.reader_config[reader_entity.unit_number]
end

local function set_config(reader_entity, config)
  storage.reader_config = storage.reader_config or {}
  storage.reader_config[reader_entity.unit_number] = config
end

-- Check if the depot has drone methods (drone mixin)
local function depot_has_drones(depot)
  return depot and depot.get_drone_item_count ~= nil
end

-- Check if depot deals with items (not fluids) - for stack size / max stacks signals
local function depot_has_item_stacks(depot)
  if not depot then return false end
  if depot.player_slots then return true end  -- dispatcher depot
  if depot.item_chest then return true end  -- active depot
  if depot.item and depot.item ~= false then
    return depot.mode ~= depot_base.request_mode.fluid
  end
  if depot.old_contents then
    -- Check first content isn't a fluid (fluid-depot uses old_contents too)
    local name = next(depot.old_contents)
    if name and prototypes.fluid[name] then return false end
    -- Also check entity type - fluid depots have fluidboxes, not inventories
    if depot.entity and depot.entity.valid and depot.entity.fluidbox and #depot.entity.fluidbox >= 1 then
      return false
    end
    return true
  end
  return false
end

-- Get the item inventory for a depot (handles active depot's item_chest)
local function get_item_inventory(depot)
  if depot.item_chest and depot.item_chest.valid then
    return depot.item_chest.get_inventory(defines.inventory.chest)
  end
  if depot.entity and depot.entity.valid then
    return depot.entity.get_output_inventory()
  end
  return nil
end

local floor = math.floor

-- Get the depot's item info (name, sprite_type, locale_key, amount) or nil
-- mode: 1=depot, 2=network, 3=network-excl
local function get_depot_item_info(depot, mode)
  if not depot or not depot.entity or not depot.entity.valid then return nil end
  local item_name, sprite_type, name_key, local_amount
  if depot.item then
    local is_fluid = depot.mode == depot_base.request_mode.fluid
    sprite_type = is_fluid and "fluid" or "item"
    name_key = is_fluid and "fluid-name" or "item-name"
    item_name = depot.item
    local_amount = depot.get_current_amount and floor(depot:get_current_amount()) or 0
  elseif depot.entity.name == "fuel-depot" then
    item_name = depot_base.get_fuel_fluid()
    sprite_type = "fluid"
    name_key = "fluid-name"
    local_amount = depot.get_fuel_amount and floor(depot:get_fuel_amount()) or 0
  elseif depot.player_slots then
    -- Dispatcher depot: item is always transport-drone
    item_name = "transport-drone"
    sprite_type = "item"
    name_key = "item-name"
    local_amount = depot.get_drone_item_count and floor(depot:get_drone_item_count()) or 0
  elseif depot.old_contents then
    -- Supply/storage/mining/fluid: show first item from contents
    item_name = next(depot.old_contents)
    if not item_name then return nil end
    if prototypes.fluid[item_name] then
      sprite_type = "fluid"
      name_key = "fluid-name"
    else
      sprite_type = "item"
      name_key = "item-name"
    end
    local_amount = depot.old_contents[item_name] or 0
  else
    return nil
  end

  local amount = local_amount
  mode = mode or 1
  if mode ~= 1 and depot.network_id then
    local sum = 0
    if depot.entity.name == "fuel-depot" then
      -- Fuel depots: sum fuel available across all fuel depots on the network
      local network = road_network.get_network_by_id(depot.network_id)
      local fuel_depots = network and network.depots and network.depots.fuel
      if fuel_depots then
        for _, fd in pairs(fuel_depots) do
          if fd.entity and fd.entity.valid and fd.get_fuel_amount then
            sum = sum + fd:get_fuel_amount()
          end
        end
      end
    else
      local supply = road_network.get_network_item_supply(depot.network_id)
      local counts = supply and supply[item_name]
      if counts then
        for _, c in pairs(counts) do sum = sum + c end
      end
    end
    if mode == 3 then sum = math.max(0, sum - local_amount) end
    amount = floor(sum)
  end

  local locale
  local proto_table = sprite_type == "fluid" and prototypes.fluid or prototypes.item
  local proto = proto_table[item_name]
  locale = proto and proto.localised_name or {name_key .. "." .. item_name}

  return {name = item_name, sprite = sprite_type .. "/" .. item_name, locale = locale, amount = amount}
end

-- Get item name for the depot (for stack size lookups)
local function get_depot_item_name(depot)
  if depot.player_slots then return "transport-drone" end  -- dispatcher depot
  if depot.item and depot.item ~= false then return depot.item end
  if depot.old_contents then
    local name = next(depot.old_contents)
    if name then return name end
    if depot.entity and depot.entity.valid and depot.entity.type == "logistic-container" then
      local sf = depot.entity.storage_filter
      if sf then return sf.name.name end
    end
  end
  -- Active depot: peek at first item in chest
  if depot.item_chest and depot.item_chest.valid then
    local inv = depot.item_chest.get_inventory(defines.inventory.chest)
    if inv then
      local contents = inv.get_contents()
      if contents[1] then return contents[1].name end
    end
  end
  return nil
end

local function get_depot_capacity(depot)
  if depot.get_max_storage_size then
    return floor(depot:get_max_storage_size())
  elseif depot.entity and depot.entity.valid and depot.entity.fluidbox and #depot.entity.fluidbox >= 1 then
    return floor(depot.entity.fluidbox.get_capacity(1))
  else
    local inv = get_item_inventory(depot)
    if inv then
      local slots = (inv.supports_bar() and inv.get_bar() or (#inv + 1)) - 1
      -- Single-slot bulk inventories (e.g. mining depots): use mining capacity setting
      if slots <= 1 and not inv.supports_bar() then
        local cap_setting = settings.startup["af-mining-drones-capacity"]
        if cap_setting then return cap_setting.value * 100 end
        return 0
      end
      local item_name = get_depot_item_name(depot)
      if item_name then
        local proto = prototypes.item[item_name]
        if proto then return slots * proto.stack_size end
      end
      return slots
    end
  end
  return 0
end

-- Count non-empty stacks within a slot range
local function count_used_stacks(inv, from, to)
  local used = 0
  for i = from, to do
    if inv[i].valid_for_read then used = used + 1 end
  end
  return used
end

local function get_stack_info(depot)
  local item_name = get_depot_item_name(depot)
  if not item_name then return 0, 0, 0 end
  local proto = prototypes.item[item_name]
  if not proto then return 0, 0, 0 end
  local stack_size = proto.stack_size
  local max_stacks = 0
  local used_stacks = 0
  local inv = get_item_inventory(depot)
  if depot.get_max_storage_size then
    max_stacks = floor(depot:get_max_storage_size() / stack_size)
    if inv then
      local bar = inv.supports_bar() and inv.get_bar() or (#inv + 1)
      used_stacks = count_used_stacks(inv, 1, math.min(bar - 1, #inv))
    end
  elseif inv then
    if #inv <= 1 and not inv.supports_bar() then
      -- Single-slot bulk inventory: used from raw count, max from capacity setting
      local raw_total = 0
      for _, item in pairs(inv.get_contents()) do if item.name == item_name then raw_total = raw_total + item.count end end
      used_stacks = math.ceil(raw_total / stack_size)
      local cap_setting = settings.startup["af-mining-drones-capacity"]
      if cap_setting then
        max_stacks = floor((cap_setting.value * 100) / stack_size)
      end
    else
      max_stacks = (inv.supports_bar() and inv.get_bar() or (#inv + 1)) - 1
      used_stacks = count_used_stacks(inv, 1, math.min(max_stacks, #inv))
    end
  end
  return stack_size, max_stacks, used_stacks
end

-- Count used stacks in the return zone (after bar) — dispatcher only
local function get_returning_stacks(depot)
  if not depot.player_slots then return 0 end
  local inv = depot.entity and depot.entity.valid and depot.entity.get_inventory(defines.inventory.chest)
  if not inv then return 0 end
  local bar = inv.supports_bar() and inv.get_bar() or (#inv + 1)
  return count_used_stacks(inv, bar, #inv)
end

local function get_signal_values(depot)
  if not depot or not depot.entity or not depot.entity.valid then
    return 0, 0, 0, 0, 0, 0, 0, 0
  end
  local drones = depot.get_drone_item_count and depot:get_drone_item_count() or 0
  local active = depot.get_active_drone_count and depot:get_active_drone_count() or 0
  local fuel = depot.get_fuel_amount and floor(depot:get_fuel_amount()) or 0
  local capacity = get_depot_capacity(depot)
  local stack_size, max_stacks, used_stacks = 0, 0, 0
  if depot_has_item_stacks(depot) then
    stack_size, max_stacks, used_stacks = get_stack_info(depot)
  end
  local returning = get_returning_stacks(depot)
  return drones, active, fuel, capacity, stack_size, max_stacks, used_stacks, returning
end

local function update_live_values(data, player_index)
  if not data then return end
  local depot = data.depot
  if not depot or not depot.entity or not depot.entity.valid then return end

  -- Update status dot
  local player = game.get_player(player_index)
  if player then
    local frame = player.gui.screen[frame_name]
    if frame then
      local inner = frame.inner
      if inner then
        local status_dot = inner.children[1] and inner.children[1]["reader-status-dot"]
        if status_dot and status_dot.valid then
          local disabled = depot_base.is_writer_disabled(depot)
          status_dot.style.font_color = disabled and {0.8, 0, 0} or {0, 0.8, 0}
          local has_writer = depot.circuit_writer and depot.circuit_writer.valid
          local writer_config = has_writer and storage.writer_config and storage.writer_config[depot.circuit_writer.unit_number]
          local has_condition = writer_config and writer_config.condition_signal
          if not has_writer then
            status_dot.tooltip = {"reader-status-no-writer"}
          elseif not has_condition then
            status_dot.tooltip = {"reader-status-no-condition"}
          elseif disabled then
            status_dot.tooltip = {"reader-status-disabled"}
          else
            status_dot.tooltip = {"reader-status-enabled"}
          end
        end
      end
    end
  end

  -- Update item amount
  if data.item_amount_label and data.item_amount_label.valid then
    local rconfig = storage.reader_config and storage.reader_config[data.entity.unit_number]
    local mode = rconfig and rconfig.mode or 1
    local info = get_depot_item_info(depot, mode)
    if info then
      data.item_amount_label.number = info.amount
      data.item_amount_label.tooltip = info.amount
    end
  end

  -- Update extra signal values
  local c = data.choosers
  if not c then return end
  local drones, active, fuel, capacity, stack_size, max_stacks, used_stacks, returning = get_signal_values(depot)
  if c.drone and c.drone.valid then c.drone.caption = util.format_number(drones, true) end
  if c.active and c.active.valid then c.active.caption = util.format_number(active, true) end
  if c.fuel and c.fuel.valid then c.fuel.caption = util.format_number(fuel, true) end
  if c.capacity and c.capacity.valid then c.capacity.caption = util.format_number(capacity, true) end
  if c.stack_size and c.stack_size.valid then c.stack_size.caption = util.format_number(stack_size, true) end
  if c.max_stacks and c.max_stacks.valid then c.max_stacks.caption = util.format_number(max_stacks, true) end
  if c.used_stacks and c.used_stacks.valid then c.used_stacks.caption = util.format_number(used_stacks, true) end
  if c.returning and c.returning.valid then c.returning.caption = util.format_number(returning, true) end
end

local function add_signal_toggle_row(inner, checkbox_name, chooser_name, value_name, label_key, is_checked, current_signal, default_signal, number_value)
  local flow = inner.add{type = "flow", direction = "horizontal"}
  flow.style.vertical_align = "center"
  flow.style.top_margin = 4
  flow.add{
    type = "checkbox",
    name = checkbox_name,
    caption = {label_key},
    state = is_checked
  }
  flow.add{type = "empty-widget"}.style.horizontally_stretchable = true
  local value_label = flow.add{type = "label", name = value_name, caption = util.format_number(number_value or 0, true)}
  value_label.style.font_color = {1, 0.7, 0}
  value_label.style.right_margin = 6
  value_label.style.minimal_width = 30
  value_label.style.horizontal_align = "right"
  flow.add{
    type = "choose-elem-button",
    name = chooser_name,
    elem_type = "signal",
    signal = current_signal or default_signal
  }
  return value_label
end

local function build_gui(player, reader_entity, depot)
  local screen = player.gui.screen
  if screen[frame_name] then screen[frame_name].destroy() end

  local frame = screen.add{type = "frame", name = frame_name, direction = "vertical"}
  frame.auto_center = true

  -- Title bar
  local title_flow = frame.add{type = "flow", name = "title_flow"}
  title_flow.add{type = "label", caption = {"reader-gui-title"}, style = "frame_title"}
  local pusher = title_flow.add{type = "empty-widget", style = "draggable_space_header"}
  pusher.style.vertically_stretchable = true
  pusher.style.horizontally_stretchable = true
  pusher.drag_target = frame
  title_flow.add{
    type = "sprite-button",
    name = "reader-close-button",
    sprite = "utility/close",
    style = "close_button"
  }

  local inner = frame.add{type = "frame", name = "inner", style = "inside_shallow_frame_with_padding", direction = "vertical"}
  inner.style.minimal_width = 260

  local choosers = nil
  local item_amount_label = nil

  if not depot then
    inner.add{type = "label", caption = {"reader-not-attached"}}
    return frame, choosers, item_amount_label
  end

  local config = get_config(reader_entity) or {}
  local current_mode = config.mode or 1

  -- Attached depot info with status indicator
  local disabled = depot_base.is_writer_disabled(depot)
  local has_writer = depot.circuit_writer and depot.circuit_writer.valid
  local writer_config = has_writer and storage.writer_config and storage.writer_config[depot.circuit_writer.unit_number]
  local has_condition = writer_config and writer_config.condition_signal
  local status_tooltip
  if not has_writer then
    status_tooltip = {"reader-status-no-writer"}
  elseif not has_condition then
    status_tooltip = {"reader-status-no-condition"}
  elseif disabled then
    status_tooltip = {"reader-status-disabled"}
  else
    status_tooltip = {"reader-status-enabled"}
  end

  local attached_flow = inner.add{type = "flow", direction = "horizontal"}
  attached_flow.style.vertical_align = "center"
  attached_flow.style.bottom_margin = 4
  local status_dot = attached_flow.add{
    type = "label",
    name = "reader-status-dot",
    caption = "●",
    tooltip = status_tooltip
  }
  status_dot.style.font_color = disabled and {0.8, 0, 0} or {0, 0.8, 0}
  status_dot.style.right_padding = 4
  attached_flow.add{type = "label", caption = {"reader-attached-to"}}
  attached_flow.add{type = "label", caption = get_depot_display_name(depot), style = "bold_label"}

  -- Item info row (single-item depots only)
  local item_info = get_depot_item_info(depot, current_mode)
  if item_info then
    inner.add{type = "line", direction = "horizontal"}.style.top_margin = 4
    local item_flow = inner.add{type = "flow", direction = "horizontal"}
    item_flow.style.vertical_align = "center"
    item_flow.style.top_margin = 4
    item_amount_label = item_flow.add{
      type = "sprite-button",
      sprite = item_info.sprite,
      number = item_info.amount,
      tooltip = item_info.amount,
      style = "slot_button"
    }
    item_flow.add{type = "label", caption = item_info.locale, style = "bold_label"}.style.left_margin = 4
  end

  inner.add{type = "line", direction = "horizontal"}.style.top_margin = 4

  -- Mode dropdown
  local mode_flow = inner.add{type = "flow", direction = "horizontal"}
  mode_flow.style.vertical_align = "center"
  mode_flow.style.top_margin = 4
  mode_flow.add{type = "label", caption = {"reader-mode-label"}, tooltip = {"reader-mode-tooltip"}}
  mode_flow.add{type = "empty-widget"}.style.horizontally_stretchable = true
  mode_flow.add{
    type = "drop-down",
    name = "reader-mode-dropdown",
    items = {{"reader-mode-depot"}, {"reader-mode-network"}, {"reader-mode-network-excl"}},
    selected_index = current_mode,
    tooltip = {"reader-mode-tooltip"}
  }

  -- Extra signal toggles
  inner.add{type = "line", direction = "horizontal"}.style.top_margin = 4

  local header = inner.add{type = "label", caption = {"reader-extra-signals"}, style = "bold_label"}
  header.style.top_margin = 4

  local drones, active, fuel, capacity, stack_size, max_stacks, used_stacks, returning = get_signal_values(depot)

  choosers = {}

  -- Drone/Active/Fuel toggles (only for drone-bearing depots)
  if depot_has_drones(depot) then
    local show_drones = config.show_drones ~= false
    choosers.drone = add_signal_toggle_row(inner, "reader-show-drones", "reader-drone-signal",
      "reader-drone-value", "reader-show-drones", show_drones, config.drone_signal, default_drone_signal, drones)

    choosers.active = add_signal_toggle_row(inner, "reader-show-active", "reader-active-signal",
      "reader-active-value", "reader-show-active", config.show_active or false, config.active_signal, default_active_signal, active)

    choosers.fuel = add_signal_toggle_row(inner, "reader-show-fuel", "reader-fuel-signal",
      "reader-fuel-value", "reader-show-fuel", config.show_fuel or false, config.fuel_signal, default_fuel_signal, fuel)
  end

  -- Capacity toggle (all depots)
  choosers.capacity = add_signal_toggle_row(inner, "reader-show-capacity", "reader-capacity-signal",
    "reader-capacity-value", "reader-show-capacity", config.show_capacity or false, config.capacity_signal, default_capacity_signal, capacity)

  -- Stack size / Max stacks toggles (item-based depots only)
  if depot_has_item_stacks(depot) then
    choosers.stack_size = add_signal_toggle_row(inner, "reader-show-stack-size", "reader-stack-size-signal",
      "reader-stack-size-value", "reader-show-stack-size", config.show_stack_size or false, config.stack_size_signal, default_stack_size_signal, stack_size)

    choosers.used_stacks = add_signal_toggle_row(inner, "reader-show-used-stacks", "reader-used-stacks-signal",
      "reader-used-stacks-value", "reader-show-used-stacks", config.show_used_stacks or false, config.used_stacks_signal, default_used_stacks_signal, used_stacks)

    choosers.max_stacks = add_signal_toggle_row(inner, "reader-show-max-stacks", "reader-max-stacks-signal",
      "reader-max-stacks-value", "reader-show-max-stacks", config.show_max_stacks or false, config.max_stacks_signal, default_max_stacks_signal, max_stacks)
  end

  -- Returning stacks (dispatcher only)
  if depot.player_slots then
    choosers.returning = add_signal_toggle_row(inner, "reader-show-returning", "reader-returning-signal",
      "reader-returning-value", "reader-show-returning", config.show_returning or false, config.returning_signal, default_returning_signal, returning)
  end

  return frame, choosers, item_amount_label
end

-- === Event handlers ===

local function on_gui_opened(event)
  if not event.entity then return end
  if event.entity.name ~= "transport-depot-reader" then return end

  local player = game.get_player(event.player_index)
  if not player then return end

  local reader_entity = event.entity
  local depot = find_depot_for_reader(reader_entity)

  -- Close vanilla GUI and open custom one
  player.opened = nil

  local frame, choosers, item_amount_label = build_gui(player, reader_entity, depot)
  player.opened = frame
  player_open_reader[event.player_index] = {entity = reader_entity, depot = depot, choosers = choosers, item_amount_label = item_amount_label}
end

local function on_gui_closed(event)
  if not event.element then return end
  if not event.element.valid then return end
  if event.element.name ~= frame_name then return end

  event.element.destroy()
  player_open_reader[event.player_index] = nil
end

local function on_gui_click(event)
  local element = event.element
  if not element or not element.valid then return end
  if element.name == "reader-close-button" then
    local player = game.get_player(event.player_index)
    if player then player.opened = nil end
  end
end

local function on_selection_changed(event)
  local element = event.element
  if not element or not element.valid then return end
  if element.name ~= "reader-mode-dropdown" then return end

  local data = player_open_reader[event.player_index]
  if not data or not (data.entity and data.entity.valid) then return end

  local config = get_config(data.entity) or {}
  config.mode = element.selected_index
  set_config(data.entity, config)
end

local checkbox_config_map = {
  ["reader-show-drones"] = "show_drones",
  ["reader-show-active"] = "show_active",
  ["reader-show-fuel"] = "show_fuel",
  ["reader-show-capacity"] = "show_capacity",
  ["reader-show-stack-size"] = "show_stack_size",
  ["reader-show-max-stacks"] = "show_max_stacks",
  ["reader-show-used-stacks"] = "show_used_stacks",
  ["reader-show-returning"] = "show_returning",
}

local function on_checked_changed(event)
  local element = event.element
  if not element or not element.valid then return end

  local config_key = checkbox_config_map[element.name]
  if not config_key then return end

  local data = player_open_reader[event.player_index]
  if not data or not (data.entity and data.entity.valid) then return end

  local config = get_config(data.entity) or {}
  config[config_key] = element.state
  set_config(data.entity, config)
end

local chooser_config_map = {
  ["reader-drone-signal"] = "drone_signal",
  ["reader-active-signal"] = "active_signal",
  ["reader-fuel-signal"] = "fuel_signal",
  ["reader-capacity-signal"] = "capacity_signal",
  ["reader-stack-size-signal"] = "stack_size_signal",
  ["reader-max-stacks-signal"] = "max_stacks_signal",
  ["reader-used-stacks-signal"] = "used_stacks_signal",
  ["reader-returning-signal"] = "returning_signal",
}

local chooser_defaults = {
  ["reader-drone-signal"] = default_drone_signal,
  ["reader-active-signal"] = default_active_signal,
  ["reader-fuel-signal"] = default_fuel_signal,
  ["reader-capacity-signal"] = default_capacity_signal,
  ["reader-stack-size-signal"] = default_stack_size_signal,
  ["reader-max-stacks-signal"] = default_max_stacks_signal,
  ["reader-used-stacks-signal"] = default_used_stacks_signal,
  ["reader-returning-signal"] = default_returning_signal,
}

local function on_elem_changed(event)
  local element = event.element
  if not element or not element.valid then return end

  local config_key = chooser_config_map[element.name]
  if not config_key then return end

  local data = player_open_reader[event.player_index]
  if not data or not (data.entity and data.entity.valid) then return end

  local config = get_config(data.entity) or {}
  if element.elem_value then
    config[config_key] = element.elem_value
  else
    -- Reset to default when cleared
    config[config_key] = nil
    element.elem_value = chooser_defaults[element.name]
  end
  set_config(data.entity, config)
end

-- Auto-refresh signal values every 0.5s
local function on_refresh_tick()
  for player_index, data in pairs(player_open_reader) do
    update_live_values(data, player_index)
  end
end

lib.events = {
  [defines.events.on_gui_opened] = on_gui_opened,
  [defines.events.on_gui_closed] = on_gui_closed,
  [defines.events.on_gui_click] = on_gui_click,
  [defines.events.on_gui_selection_state_changed] = on_selection_changed,
  [defines.events.on_gui_checked_state_changed] = on_checked_changed,
  [defines.events.on_gui_elem_changed] = on_elem_changed,
}

lib.on_nth_tick = {
  [30] = on_refresh_tick,
}

return lib
