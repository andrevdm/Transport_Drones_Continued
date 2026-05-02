-- Custom GUI for the transport depot writer (constant-combinator).
-- Config stored in storage.writer_config[unit_number].

local depot_base = require("script/depot_base")

local lib = {}

local player_open_writer = {}  -- player_index → {entity, depot}

local frame_name = "writer_gui_frame"

local comparator_items = {">", "<", "=", ">=", "<=", "!="}
local comparator_index = {}
for i, v in pairs(comparator_items) do comparator_index[v] = i end

-- Find the depot that has this writer entity attached
local function find_depot_for_writer(writer_entity)
  local depot_data = storage.transport_depots
  if not depot_data then return nil end
  local writer_un = writer_entity.unit_number
  for _, depot in pairs(depot_data.depots) do
    if depot.circuit_writer and depot.circuit_writer.valid
       and depot.circuit_writer.unit_number == writer_un then
      return depot
    end
  end
  return nil
end

-- Determine if depot is a requester-type (has circuit_limit / recipe mechanics)
local function is_requester_depot(depot)
  if not depot then return false end
  local entity = depot.assembler or depot.entity
  if not (entity and entity.valid) then return false end
  local name = entity.name
  return name == "request-depot" or name == "buffer-depot"
end

local function get_depot_display_name(depot)
  if not depot then return "" end
  local entity = depot.assembler or depot.entity
  if not (entity and entity.valid) then return "" end
  return entity.localised_name
end

local function get_config(writer_entity)
  if not storage.writer_config then return nil end
  return storage.writer_config[writer_entity.unit_number]
end

local function set_config(writer_entity, config)
  storage.writer_config = storage.writer_config or {}
  storage.writer_config[writer_entity.unit_number] = config
end

local function populate_wire_signals(scroll, writer_entity)
  scroll.clear()
  for _, wire_info in pairs({
    {id = defines.wire_connector_id.circuit_red, btn_style = "td_red_slot_button"},
    {id = defines.wire_connector_id.circuit_green, btn_style = "green_slot_button"},
  }) do
    local wire_signals = writer_entity.get_signals(wire_info.id)
    if wire_signals and #wire_signals > 0 then
      local grid = scroll.add{type = "table", column_count = 5}
      for _, entry in pairs(wire_signals) do
        local sig = entry.signal
        if sig then
          local sprite_type = sig.type == "virtual" and "virtual-signal" or sig.type == "fluid" and "fluid" or "item"
          local name_key = sig.type == "virtual" and "virtual-signal-name" or sig.type == "fluid" and "fluid-name" or "item-name"
          grid.add{
            type = "sprite-button",
            sprite = sprite_type .. "/" .. sig.name,
            number = entry.count,
            tooltip = {"", {name_key .. "." .. sig.name}, ": ", tostring(entry.count)},
            style = wire_info.btn_style
          }
        end
      end
    end
  end
end

local function build_gui(player, writer_entity, depot)
  local screen = player.gui.screen
  if screen[frame_name] then screen[frame_name].destroy() end

  local frame = screen.add{type = "frame", name = frame_name, direction = "vertical"}
  frame.auto_center = true

  -- Title bar
  local title_flow = frame.add{type = "flow", name = "title_flow"}
  title_flow.add{type = "label", caption = {"writer-gui-title"}, style = "frame_title"}
  local pusher = title_flow.add{type = "empty-widget", style = "draggable_space_header"}
  pusher.style.vertically_stretchable = true
  pusher.style.horizontally_stretchable = true
  pusher.drag_target = frame
  title_flow.add{
    type = "sprite-button",
    name = "writer-close-button",
    sprite = "utility/close",
    style = "close_button"
  }

  local inner = frame.add{type = "frame", name = "inner", style = "inside_shallow_frame_with_padding", direction = "vertical"}
  inner.style.minimal_width = 230

  if not depot then
    inner.add{type = "label", caption = {"writer-not-attached"}}
    return frame
  end

  local is_req = is_requester_depot(depot)
  local config = get_config(writer_entity) or {}

  -- Attached depot info with status indicator
  local disabled = depot_base.is_writer_disabled(depot)
  local status_tooltip
  if not config.condition_signal then
    status_tooltip = {"writer-status-no-condition"}
  elseif disabled then
    status_tooltip = {"writer-status-disabled"}
  else
    status_tooltip = {"writer-status-enabled"}
  end

  local attached_flow = inner.add{type = "flow", direction = "horizontal"}
  attached_flow.style.vertical_align = "center"
  attached_flow.style.bottom_margin = 4
  local status_dot = attached_flow.add{
    type = "label",
    name = "writer-status-dot",
    caption = "●",
    tooltip = status_tooltip
  }
  status_dot.style.font_color = disabled and {0.8, 0, 0} or {0, 0.8, 0}
  status_dot.style.right_padding = 4
  attached_flow.add{type = "label", caption = {"writer-attached-to"}}
  attached_flow.add{type = "label", caption = get_depot_display_name(depot), style = "bold_label"}

  if is_req then
    -- === Requester/Buffer mode ===
    -- Show scanned wire signal
    inner.add{type = "line", direction = "horizontal"}.style.top_margin = 4

    -- Get merged signals (sum of both wires) to find item/fluid signal
    local circuit_red_id = defines.wire_connector_id.circuit_red
    local circuit_green_id = defines.wire_connector_id.circuit_green
    local found_sig, found_count, wire_color, wire_btn_style = nil, 0, nil, "slot_button"
    local signals = writer_entity.get_signals(circuit_red_id, circuit_green_id)
    if signals then
      for _, entry in pairs(signals) do
        local sig = entry.signal
        if sig and sig.type ~= "virtual" and entry.count > 0 and entry.count > found_count then
          found_sig = sig
          found_count = entry.count
        end
      end
    end
    -- Determine wire color: red-only, green-only, or default if both
    if found_sig then
      local red_val = writer_entity.get_signal(found_sig, circuit_red_id)
      local green_val = writer_entity.get_signal(found_sig, circuit_green_id)
      if red_val > 0 and green_val > 0 then
        wire_color = nil  -- both wires, use default color
      elseif red_val > 0 then
        wire_color = {1, 0.2, 0.2}
        wire_btn_style = "td_red_slot_button"
      elseif green_val > 0 then
        wire_color = {0.2, 0.8, 0.2}
        wire_btn_style = "green_slot_button"
      end
    end

    local sig_flow = inner.add{type = "flow", direction = "horizontal"}
    sig_flow.style.vertical_align = "center"
    sig_flow.style.top_margin = 4
    if found_sig then
      local sprite_type = found_sig.type == "fluid" and "fluid" or "item"
      local name_key = found_sig.type == "fluid" and "fluid-name" or "item-name"
      local tip
      if config.use_as_limit and depot.get_max_storage_size then
        local cap = depot:get_max_storage_size()
        local capped = math.min(found_count, cap)
        tip = {"", {name_key .. "." .. found_sig.name}, ": ", tostring(found_count), " / ", tostring(cap)}
      else
        tip = {"", {name_key .. "." .. found_sig.name}, ": ", tostring(found_count)}
      end
      local icon = sig_flow.add{
        type = "sprite-button",
        sprite = sprite_type .. "/" .. found_sig.name,
        number = found_count,
        tooltip = tip,
        style = wire_btn_style
      }
      local label = sig_flow.add{
        type = "label",
        caption = {name_key .. "." .. found_sig.name},
        style = "bold_label"
      }
      label.style.left_padding = 4
      if depot.get_max_storage_size then
        sig_flow.add{type = "empty-widget"}.style.horizontally_stretchable = true
        local cap_label = sig_flow.add{
          type = "label",
          caption = "/ " .. util.format_number(depot:get_max_storage_size(), true),
          tooltip = tostring(depot:get_max_storage_size())
        }
        cap_label.style.font_color = {0.6, 0.6, 0.6}
      end
    else
      sig_flow.add{type = "label", caption = {"writer-no-signal"}}
    end

    inner.add{type = "line", direction = "horizontal"}.style.top_margin = 4

    local limit_check = inner.add{
      type = "checkbox",
      name = "writer-use-as-limit",
      caption = {"writer-use-as-limit"},
      tooltip = {"writer-use-as-limit-tooltip"},
      state = config.use_as_limit or false
    }
    limit_check.style.top_margin = 4

    local recipe_check = inner.add{
      type = "checkbox",
      name = "writer-set-recipe",
      caption = {"writer-set-recipe"},
      tooltip = {"writer-set-recipe-tooltip"},
      state = config.set_recipe or false
    }
    recipe_check.style.top_margin = 2
  end

  -- === Enable/disable condition (all depot types) ===
  inner.add{type = "line", direction = "horizontal"}.style.top_margin = 4

  local cond_label = inner.add{type = "label", caption = {"writer-condition-label"}, tooltip = {"writer-condition-tooltip"}}
  cond_label.style.top_margin = 4

  local current_signal = config.condition_signal or nil
  local current_comp = config.condition_comparator or ">"
  local current_const = config.condition_constant or 0

  local cond_flow = inner.add{type = "flow", name = "condition_flow", direction = "horizontal"}
  cond_flow.style.vertical_align = "center"
  cond_flow.style.top_margin = 2
  local lhs_tooltip = nil
  if current_signal then
    local lhs_val = writer_entity.get_signal(current_signal,
      defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green)
    lhs_tooltip = {"", {"writer-condition-value"}, ": ", tostring(lhs_val)}
  end
  cond_flow.add{
    type = "choose-elem-button",
    name = "writer-condition-signal",
    elem_type = "signal",
    signal = current_signal,
    tooltip = lhs_tooltip
  }
  cond_flow.add{
    type = "drop-down",
    name = "writer-comparator",
    items = comparator_items,
    selected_index = comparator_index[current_comp] or 1
  }.style.width = 50
  local use_signal_rhs = config.condition_constant_signal ~= nil
  if use_signal_rhs then
    local rhs_val = writer_entity.get_signal(config.condition_constant_signal,
      defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green)
    cond_flow.add{
      type = "choose-elem-button",
      name = "writer-condition-rhs-signal",
      elem_type = "signal",
      signal = config.condition_constant_signal,
      tooltip = {"", {"writer-condition-value"}, ": ", tostring(rhs_val)}
    }
  else
    local const_field = cond_flow.add{
      type = "textfield",
      name = "writer-constant",
      text = tostring(current_const)
    }
    const_field.style.width = 80
    const_field.style.horizontal_align = "center"
  end
  cond_flow.add{
    type = "sprite-button",
    name = "writer-toggle-rhs",
    sprite = use_signal_rhs and "virtual-signal/signal-0" or "virtual-signal/signal-info",
    tooltip = use_signal_rhs and {"writer-rhs-switch-constant"} or {"writer-rhs-switch-signal"},
    style = "tool_button"
  }


  -- === Wire signals section ===
  inner.add{type = "line", direction = "horizontal"}.style.top_margin = 4

  local signals_label = inner.add{type = "label", caption = {"writer-signals-label"}}
  signals_label.style.top_margin = 4

  local signals_scroll = inner.add{type = "scroll-pane", name = "writer-signals-scroll", direction = "vertical"}
  signals_scroll.style.maximal_height = 200
  signals_scroll.style.top_margin = 2

  populate_wire_signals(signals_scroll, writer_entity)

  return frame
end

-- === Event handlers ===

local function on_gui_opened(event)
  if not event.entity then return end
  if event.entity.name ~= "transport-depot-writer" then return end

  local player = game.get_player(event.player_index)
  if not player then return end

  local writer_entity = event.entity
  local depot = find_depot_for_writer(writer_entity)

  -- Close vanilla GUI and open custom one
  player.opened = nil

  local frame = build_gui(player, writer_entity, depot)
  player.opened = frame
  player_open_writer[event.player_index] = {entity = writer_entity, depot = depot}
end

local function on_gui_closed(event)
  if not event.element then return end
  if not event.element.valid then return end
  if event.element.name ~= frame_name then return end

  event.element.destroy()
  player_open_writer[event.player_index] = nil
end

local rebuild_gui
local function on_gui_click(event)
  local element = event.element
  if not element or not element.valid then return end
  if element.name == "writer-close-button" then
    local player = game.get_player(event.player_index)
    if player then player.opened = nil end
    return
  end
  if element.name == "writer-toggle-rhs" then
    local data = player_open_writer[event.player_index]
    if not data or not (data.entity and data.entity.valid) then return end
    local config = get_config(data.entity) or {}
    if config.condition_constant_signal then
      -- Switch to constant mode - remember the signal for later
      config.condition_last_signal = config.condition_constant_signal
      config.condition_constant_signal = nil
      config.condition_constant = config.condition_constant or 0
    else
      -- Switch to signal mode - restore previous signal if any
      config.condition_constant_signal = config.condition_last_signal or {type = "virtual", name = "signal-0"}
    end
    set_config(data.entity, config)
    rebuild_gui(event.player_index)
    return
  end
end

rebuild_gui = function(player_index)
  local data = player_open_writer[player_index]
  if not data then return end
  local player = game.get_player(player_index)
  if not player then return end
  if not (data.entity and data.entity.valid) then
    local screen = player.gui.screen
    if screen[frame_name] then screen[frame_name].destroy() end
    player_open_writer[player_index] = nil
    return
  end
  local depot = find_depot_for_writer(data.entity)
  data.depot = depot
  local frame = build_gui(player, data.entity, depot)
  player.opened = frame
end

local function on_checked_changed(event)
  local element = event.element
  if not element or not element.valid then return end

  local data = player_open_writer[event.player_index]
  if not data or not (data.entity and data.entity.valid) then return end

  if element.name == "writer-use-as-limit" then
    local config = get_config(data.entity) or {}
    config.use_as_limit = element.state
    if not element.state then
      config.set_recipe = false
      -- Unlock recipe
      if data.depot then
        local depot_entity = data.depot.assembler or data.depot.entity
        if depot_entity and depot_entity.valid then
          depot_entity.recipe_locked = false
        end
      end
    end
    set_config(data.entity, config)
    rebuild_gui(event.player_index)
    return
  end

  if element.name == "writer-set-recipe" then
    local config = get_config(data.entity) or {}
    config.set_recipe = element.state
    -- Unlock recipe when turning off
    if not element.state and data.depot then
      local depot_entity = data.depot.assembler or data.depot.entity
      if depot_entity and depot_entity.valid then
        depot_entity.recipe_locked = false
      end
    end
    set_config(data.entity, config)
    rebuild_gui(event.player_index)
    return
  end
end

local function on_elem_changed(event)
  local element = event.element
  if not element or not element.valid then return end

  local data = player_open_writer[event.player_index]
  if not data or not (data.entity and data.entity.valid) then return end

  if element.name == "writer-condition-signal" then
    local config = get_config(data.entity) or {}
    config.condition_signal = element.elem_value or nil
    if not config.condition_signal then
      config.condition_comparator = nil
      config.condition_constant = nil
      config.condition_constant_signal = nil
      config.condition_last_signal = nil
    else
      config.condition_comparator = config.condition_comparator or ">"
      if not config.condition_constant_signal then
        config.condition_constant = config.condition_constant or 0
      end
    end
    set_config(data.entity, config)
    rebuild_gui(event.player_index)
    return
  end

  if element.name == "writer-condition-rhs-signal" then
    local config = get_config(data.entity) or {}
    config.condition_constant_signal = element.elem_value or nil
    if not config.condition_constant_signal then
      -- Cleared the signal - switch back to constant mode, restore remembered constant
      config.condition_constant = config.condition_constant or 0
    end
    set_config(data.entity, config)
    rebuild_gui(event.player_index)
    return
  end
end

local function on_selection_changed(event)
  local element = event.element
  if not element or not element.valid then return end
  if element.name ~= "writer-comparator" then return end

  local data = player_open_writer[event.player_index]
  if not data or not (data.entity and data.entity.valid) then return end

  local config = get_config(data.entity) or {}
  config.condition_comparator = comparator_items[element.selected_index] or ">"
  set_config(data.entity, config)
end

local function on_text_changed(event)
  local element = event.element
  if not element or not element.valid then return end
  if element.name ~= "writer-constant" then return end

  local data = player_open_writer[event.player_index]
  if not data or not (data.entity and data.entity.valid) then return end

  local value = util.parse_math_input(element.text)
  if not value then return end
  local config = get_config(data.entity) or {}
  config.condition_constant = math.floor(value)
  set_config(data.entity, config)
end

local function on_confirmed(event)
  local element = event.element
  if not element or not element.valid then return end
  if element.name ~= "writer-constant" then return end

  local data = player_open_writer[event.player_index]
  if not data or not (data.entity and data.entity.valid) then return end

  local config = get_config(data.entity) or {}
  element.text = tostring(config.condition_constant or 0)
end

local function update_live_values(data)
  if not data or not data.depot or not (data.entity and data.entity.valid) then return end
  local player = data.player
  if not player then return end
  local screen = player.gui.screen
  local frame = screen[frame_name]
  if not frame then return end

  local inner = frame.inner
  if not inner then return end

  -- Update status dot
  local status_dot = inner.children[1] and inner.children[1]["writer-status-dot"]
  if status_dot and status_dot.valid then
    local disabled = depot_base.is_writer_disabled(data.depot)
    status_dot.style.font_color = disabled and {0.8, 0, 0} or {0, 0.8, 0}
    local config = storage.writer_config and storage.writer_config[data.entity.unit_number]
    if not config or not config.condition_signal then
      status_dot.tooltip = {"writer-status-no-condition"}
    elseif disabled then
      status_dot.tooltip = {"writer-status-disabled"}
    else
      status_dot.tooltip = {"writer-status-enabled"}
    end
  end

  -- Update condition signal tooltips
  local cond_flow = inner["condition_flow"]
  if cond_flow then
    local config = storage.writer_config and storage.writer_config[data.entity.unit_number]
    if config then
      local lhs_btn = cond_flow["writer-condition-signal"]
      if lhs_btn and lhs_btn.valid and config.condition_signal then
        local lhs_val = data.entity.get_signal(config.condition_signal,
          defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green)
        lhs_btn.tooltip = {"", {"writer-condition-value"}, ": ", tostring(lhs_val)}
      end
      local rhs_btn = cond_flow["writer-condition-rhs-signal"]
      if rhs_btn and rhs_btn.valid and config.condition_constant_signal then
        local rhs_val = data.entity.get_signal(config.condition_constant_signal,
          defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green)
        rhs_btn.tooltip = {"", {"writer-condition-value"}, ": ", tostring(rhs_val)}
      end
    end
  end

  -- Update wire signals
  local scroll = inner["writer-signals-scroll"]
  if scroll and scroll.valid then
    populate_wire_signals(scroll, data.entity)
  end
end

local function on_tick()
  for player_index, data in pairs(player_open_writer) do
    if not data.player then
      data.player = game.get_player(player_index)
    end
    update_live_values(data)
  end
end

lib.events = {
  [defines.events.on_gui_opened] = on_gui_opened,
  [defines.events.on_gui_closed] = on_gui_closed,
  [defines.events.on_gui_click] = on_gui_click,
  [defines.events.on_gui_elem_changed] = on_elem_changed,
  [defines.events.on_gui_checked_state_changed] = on_checked_changed,
  [defines.events.on_gui_selection_state_changed] = on_selection_changed,
  [defines.events.on_gui_text_changed] = on_text_changed,
  [defines.events.on_gui_confirmed] = on_confirmed,
}

lib.on_nth_tick = {
  [30] = on_tick,
}

return lib
