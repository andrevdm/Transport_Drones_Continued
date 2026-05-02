local depot_base = require("script/depot_base")
local helpers = require("script/gui/helpers")
local widgets = require("script/gui/depot_widgets")

local floor = helpers.floor
local channel_filter_match = helpers.channel_filter_match
local map_size = helpers.map_size
local depot_max_width = helpers.depot_max_width

local fuel_tab = {}

local update_fuel_depot_gui = function(depot, gui)

  local flow = gui.table

  if not flow then
    flow = gui.add{type = "table", column_count = 1, name = "table"}
    flow.style.horizontally_stretchable = true
    flow.style.left_margin = 2
  end

  -- Migration: old layout had drone_flow first, then fuel_flow
  if flow.drone_flow and not flow.header_flow then
    flow.clear()
  end

  -- Fuel header: icon with count + name + right-aligned capacity
  local fuel_fluid = depot_base.get_fuel_fluid()
  local fuel_amount = floor(depot:get_fuel_amount())
  local fuel_capacity = depot.entity.fluidbox and depot.entity.fluidbox.get_capacity(1) or 0
  local fuel_bar_value = fuel_capacity > 0 and (fuel_amount / fuel_capacity) or 0
  local fuel_tooltip = floor(fuel_bar_value * 100) .. "%"
  if fuel_bar_value > 1 then fuel_bar_value = 1 end
  local header_flow = flow.header_flow
  if not header_flow then
    header_flow = flow.add{type = "flow", name = "header_flow"}
    header_flow.style.vertical_align = "center"
    header_flow.add{
      type = "sprite-button",
      sprite = "fluid/" .. fuel_fluid,
      number = fuel_amount,
      tooltip = fuel_tooltip,
      style = "transparent_slot",
      name = "fuel_icon"
    }
    local name_label = header_flow.add{type = "label", caption = prototypes.fluid[fuel_fluid].localised_name}
    name_label.style.left_padding = 3
    header_flow.add{type = "empty-widget"}.style.horizontally_stretchable = true
    header_flow.add{
      type = "label", name = "max_label",
      caption = "/ " .. util.format_number(floor(fuel_capacity), true),
      tooltip = tostring(floor(fuel_capacity))
    }.style.font_color = {0.6, 0.6, 0.6}
    widgets.update_status_dot(header_flow, depot)
  else
    header_flow.fuel_icon.number = fuel_amount
    header_flow.fuel_icon.tooltip = fuel_tooltip
    widgets.update_status_dot(header_flow, depot)
  end

  -- Fuel progress bar
  local fuel_bar = flow.fuel_bar
  if not fuel_bar then
    fuel_bar = flow.add{type = "progressbar", name = "fuel_bar", value = fuel_bar_value}
    fuel_bar.style.horizontally_stretchable = true
    fuel_bar.style.height = 8
    fuel_bar.tooltip = fuel_tooltip
  else
    fuel_bar.value = fuel_bar_value
    fuel_bar.tooltip = fuel_tooltip
  end

  widgets.update_drone_section(flow, depot)
  widgets.update_priority_section(flow, depot)
  widgets.update_channel_section(flow, depot)
end

local update_fuel_depots = function(depots, gui, channel_filter)

  if not depots or not gui then return end

  for index, depot in pairs (depots) do
    if depot.entity.valid then
      local depot_frame = gui[index]
      if not depot_frame then
        depot_frame = gui.add{type = "flow", name = index}
        depot_frame.style.horizontally_stretchable = true
        depot_frame.style.maximal_width = depot_max_width
        widgets.add_depot_map_button(depot, depot_frame, map_size)
      end
      update_fuel_depot_gui(depot, depot_frame)
      if channel_filter then
        depot_frame.visible = channel_filter_match(channel_filter, depot.channel)
      else
        depot_frame.visible = true
      end
    end
  end

  for k, gui in pairs (gui.children) do
    if not depots[gui.name] then
      gui.destroy()
    end
  end
end

function fuel_tab.refresh(player, force)
  if not force and not helpers.is_tab_selected(player, "fuel_tab") then return end
  local tab = helpers.get_tab(player, "fuel_tab")
  if not tab then return end
  local network = helpers.get_selected_network(player)
  update_fuel_depots(network.depots.fuel, tab.depot_table, helpers.get_channel_filter_value(player))
end

function fuel_tab.add(tabbed_pane, network)
  local tab = tabbed_pane.add{type = "tab", caption = {"fuel-depots-tab"}}
  local contents = tabbed_pane.add{type = "scroll-pane", name = "fuel_tab", style = "naked_scroll_pane"}

  local depots = network.depots.fuel

  if not depots then
    tab.enabled = false
    tabbed_pane.add_tab(tab, contents)
    return
  end

  local depot_table = contents.add{type = "table", column_count = 2, style = "bordered_table", name = "depot_table"}
  depot_table.style.horizontally_stretchable = true

  update_fuel_depots(depots, depot_table)

  tabbed_pane.add_tab(tab, contents)
end

return fuel_tab
