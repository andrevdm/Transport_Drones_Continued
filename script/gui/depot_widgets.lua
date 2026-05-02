local helpers = require("script/gui/helpers")
local depot_base = require("script/depot_base")

local floor = helpers.floor

local widgets = {}

function widgets.add_depot_map_button(depot, gui, size)
  local button = gui.add{type = "button", name = "open_depot_map_"..depot.index, tooltip = {"map-button-tooltip"}}
  button.style.minimal_width = size + 8
  button.style.minimal_height = size + 8
  button.style.horizontal_align = "center"
  button.style.vertical_align = "center"
  button.style.padding = {0,0,0,0}
  local entity = depot.entity
  local map = button.add
  {
    type = "minimap",
    position = entity.position,
    surface_index = entity.surface.index,
    force = entity.force.name,
    zoom = 2,
    ignored_by_interaction = true
  }
  map.style.minimal_width = size
  map.style.minimal_height = size
end

function widgets.add_separator(flow, name)
  if not flow[name] then
    local line = flow.add{type = "line", name = name, direction = "horizontal"}
    line.style.top_margin = -2
    line.style.bottom_margin = -2
  end
end

function widgets.update_drone_section(flow, depot)
  local active = depot:get_active_drone_count()
  local total_drones = depot:get_drone_item_count()
  local available = total_drones - active
  if available < 0 then available = 0 end
  local drone_bar_value = total_drones > 0 and (available / total_drones) or 0

  -- Overall drone icon + progress bar (always shown)
  local drone_flow = flow.drone_flow
  if drone_flow and not drone_flow.drone_icon then
    drone_flow.destroy()
    drone_flow = nil
  end
  if drone_flow and drone_flow.drone_max then
    drone_flow.destroy()
    drone_flow = nil
  end
  if not drone_flow then
    drone_flow = flow.add{type = "flow", name = "drone_flow", direction = "horizontal"}
    drone_flow.style.vertical_align = "center"
    drone_flow.add{
      type = "sprite-button",
      sprite = "item/transport-drone",
      number = total_drones,
      style = "transparent_slot",
      name = "drone_icon",
      tooltip = {"drones-active-available", active, available}
    }
    local dbar = drone_flow.add{type = "progressbar", name = "drone_bar", value = drone_bar_value}
    dbar.style.horizontally_stretchable = true
    dbar.style.height = 8
    dbar.style.color = {0.3, 0.6, 1.0}
    dbar.tooltip = {"drone-bar-tooltip", floor(drone_bar_value * 100)}
  else
    drone_flow.drone_icon.number = total_drones
    drone_flow.drone_icon.tooltip = {"drones-active-available", active, available}
    drone_flow.drone_bar.value = drone_bar_value
    drone_flow.drone_bar.tooltip = {"drone-bar-tooltip", floor(drone_bar_value * 100)}
  end

  -- Per-quality breakdown (only when mixed qualities)
  local quality_counts = depot:get_drone_counts_by_quality()
  local quality_flow = flow.drone_quality_flow
  if #quality_counts <= 1 then
    if quality_flow then quality_flow.destroy() end
    drone_flow.visible = true
    return
  end

  -- Hide overall row when showing per-quality breakdown
  drone_flow.visible = false

  if quality_flow then quality_flow.clear() else
    quality_flow = flow.add{type = "flow", name = "drone_quality_flow", direction = "vertical"}
  end
  for _, qc in pairs(quality_counts) do
    local qtotal = qc.inventory
    local qavail = qtotal - qc.active
    if qavail < 0 then qavail = 0 end
    local qbar_value = qtotal > 0 and (qavail / qtotal) or 0
    local qrow = quality_flow.add{type = "flow", direction = "horizontal"}
    qrow.style.vertical_align = "center"
    qrow.add{
      type = "sprite-button",
      sprite = "item/transport-drone",
      quality = qc.quality,
      number = qtotal,
      style = "transparent_slot",
      tooltip = {"drones-active-available", qc.active, qavail}
    }
    local qbar = qrow.add{type = "progressbar", value = qbar_value}
    qbar.style.horizontally_stretchable = true
    qbar.style.height = 8
    qbar.style.color = {0.3, 0.6, 1.0}
    qbar.tooltip = {"drone-bar-tooltip", floor(qbar_value * 100)}
  end
end

function widgets.update_priority_section(flow, depot)
  widgets.add_separator(flow, "priority_line")
  local base_pri = depot.base_priority or shared.default_priority
  local effective_pri = depot.priority or base_pri
  local priority_flow = flow.priority_flow
  if not priority_flow then
    priority_flow = flow.add{type = "flow", name = "priority_flow", direction = "horizontal"}
    priority_flow.style.vertical_align = "center"
    priority_flow.style.top_padding = 2
    priority_flow.style.bottom_padding = 2
    priority_flow.add{type = "label", caption = {"priority-label"}, tooltip = {"priority-slider-tooltip"}}
    local slider = priority_flow.add{
      type = "slider", name = "supply-priority-slider",
      minimum_value = 0, maximum_value = 100,
      value = base_pri,
      value_step = 1, discrete_slider = true,
      tooltip = {"priority-slider-tooltip"},
      tags = {depot_index = depot.index}
    }
    slider.style.horizontally_stretchable = true
    local value_label = priority_flow.add{
      type = "label", name = "priority-value",
      caption = util.format_number(effective_pri, true)
    }
    value_label.style.width = 36
    value_label.style.horizontal_align = "right"
    if effective_pri ~= base_pri then
      value_label.style.font_color = {1, 0.7, 0}
      value_label.tooltip = {"", {"priority-override-tooltip"}, "\n", tostring(effective_pri)}
    end
  else
    local value_label = priority_flow["priority-value"]
    value_label.caption = util.format_number(effective_pri, true)
    if effective_pri ~= base_pri then
      value_label.style.font_color = {1, 0.7, 0}
      value_label.tooltip = {"", {"priority-override-tooltip"}, "\n", tostring(effective_pri)}
    else
      value_label.style.font_color = {1, 1, 1}
      value_label.tooltip = ""
    end
  end
end

function widgets.update_channel_section(flow, depot)
  widgets.add_separator(flow, "channel_line")
  local overridden = depot.channel ~= (depot.base_channel or shared.default_channel)
  local ch_flow = flow.channel_flow
  if not ch_flow then
    ch_flow = flow.add{type = "flow", name = "channel_flow", direction = "horizontal"}
    ch_flow.style.vertical_align = "center"
    ch_flow.style.horizontally_stretchable = true
    ch_flow.add{type = "label", caption = {"channel-label"}, tooltip = {"channel-tooltip"}}
    ch_flow.add{type = "empty-widget"}.style.horizontally_stretchable = true
    if overridden then
      local ch_tip = {"", {"channel-override-tooltip"}, "\n", tostring(depot.channel)}
      local override_label = ch_flow.add{type = "label", name = "channel-override-label", caption = util.format_number(depot.channel, true), tooltip = ch_tip}
      override_label.style.font_color = {1, 0.7, 0}
      override_label.style.right_margin = 4
    end
    local ch_field = ch_flow.add{
      type = "textfield", name = "supply-channel-field",
      text = tostring(depot.base_channel or shared.default_channel),
      tooltip = {"channel-tooltip"},
      tags = {depot_index = depot.index}
    }
    ch_field.style.width = 70
    ch_field.style.horizontal_align = "center"
  else
    local override_label = ch_flow["channel-override-label"]
    if overridden then
      local ch_tip = {"", {"channel-override-tooltip"}, "\n", tostring(depot.channel)}
      if not override_label then
        override_label = ch_flow.add{type = "label", name = "channel-override-label", caption = util.format_number(depot.channel, true), tooltip = ch_tip, index = 3}
        override_label.style.font_color = {1, 0.7, 0}
        override_label.style.right_margin = 4
      else
        override_label.caption = util.format_number(depot.channel, true)
        override_label.tooltip = ch_tip
      end
    elseif override_label then
      override_label.destroy()
    end
  end
end

function widgets.update_threshold_section(flow, depot)
  widgets.add_separator(flow, "threshold_line")
  local effective = depot:get_supply_threshold()
  local overridden = depot.circuit_threshold ~= nil
  local th_flow = flow.threshold_flow
  if not th_flow then
    th_flow = flow.add{type = "flow", name = "threshold_flow", direction = "horizontal"}
    th_flow.style.vertical_align = "center"
    th_flow.style.horizontally_stretchable = true
    th_flow.add{type = "label", caption = {"supply-threshold-label"}, tooltip = {"supply-threshold-tooltip"}}
    th_flow.add{type = "empty-widget"}.style.horizontally_stretchable = true
    if overridden then
      local th_tip = {"", {"threshold-override-tooltip"}, "\n", tostring(effective)}
      local override_label = th_flow.add{type = "label", name = "threshold-override-label", caption = util.format_number(effective, true), tooltip = th_tip}
      override_label.style.font_color = {1, 0.7, 0}
      override_label.style.right_margin = 4
    end
    local th_field = th_flow.add{
      type = "textfield", name = "supply-threshold-field",
      text = depot.supply_threshold and tostring(depot.supply_threshold) or "",
      tooltip = {"supply-threshold-tooltip"},
      tags = {depot_index = depot.index}
    }
    th_field.style.width = 70
    th_field.style.horizontal_align = "center"
  else
    local override_label = th_flow["threshold-override-label"]
    if overridden then
      local th_tip = {"", {"threshold-override-tooltip"}, "\n", tostring(effective)}
      if not override_label then
        override_label = th_flow.add{type = "label", name = "threshold-override-label", caption = util.format_number(effective, true), tooltip = th_tip, index = 3}
        override_label.style.font_color = {1, 0.7, 0}
        override_label.style.right_margin = 4
      else
        override_label.caption = util.format_number(effective, true)
        override_label.tooltip = th_tip
      end
    elseif override_label then
      override_label.destroy()
    end
  end
end

function widgets.update_fuel_bar_section(flow, depot)
  local fuel_amount = floor(depot:get_fuel_amount())
  local fuel_capacity = depot.max_fuel_amount and floor(depot:max_fuel_amount()) or 0
  local fuel_bar_value = fuel_capacity > 0 and (fuel_amount / fuel_capacity) or 0
  if fuel_bar_value > 1 then fuel_bar_value = 1 end
  local fuel_tooltip = fuel_amount .. " / " .. floor(fuel_capacity) .. " fuel"
  local fuel_bar = flow.fuel_bar
  if not fuel_bar then
    fuel_bar = flow.add{type = "progressbar", name = "fuel_bar", value = fuel_bar_value}
    fuel_bar.style.horizontally_stretchable = true
    fuel_bar.style.height = 8
    fuel_bar.style.color = {0.5, 0.5, 0.5}
    fuel_bar.tooltip = fuel_tooltip
  else
    fuel_bar.value = fuel_bar_value
    fuel_bar.tooltip = fuel_tooltip
  end
end

function widgets.update_status_dot(parent, depot, insert_index)
  local has_writer = depot.circuit_writer and depot.circuit_writer.valid
  local writer_config = has_writer and storage.writer_config and storage.writer_config[depot.circuit_writer.unit_number]
  local has_condition = writer_config and writer_config.condition_signal

  local dot = parent.status_dot

  if not (has_writer and has_condition) then
    if dot then dot.destroy() end
    return
  end

  local disabled = depot_base.is_writer_disabled(depot)
  local tooltip = disabled and {"depot-status-disabled"} or {"depot-status-enabled"}
  local color = disabled and {0.8, 0, 0} or {0, 0.8, 0}

  if not dot then
    local params = {type = "label", name = "status_dot", caption = "●", tooltip = tooltip}
    if insert_index then params.index = insert_index end
    dot = parent.add(params)
    dot.style.font_color = color
    dot.style.padding = 0
    dot.style.left_padding = 2
  else
    dot.tooltip = tooltip
    dot.style.font_color = color
  end
end

return widgets
