local helpers = require("script/gui/helpers")
local widgets = require("script/gui/depot_widgets")

local floor = helpers.floor
local channel_filter_match = helpers.channel_filter_match
local map_size = helpers.map_size
local depot_max_width = helpers.depot_max_width

local dispatcher_tab = {}

local update_dispatcher_depot_gui = function(depot, gui)

  local flow = gui.table

  if not flow then
    flow = gui.add{type = "table", column_count = 1, name = "table"}
    flow.style.horizontally_stretchable = true
    flow.style.left_margin = 2
  end

  -- Migration: recreate if new slot bars are missing
  if flow.inv_bar and not flow.user_bar then
    flow.clear()
  end

  -- Drone inventory: count per slot region (blue=user, red=return)
  local inv = depot.entity.get_inventory(defines.inventory.chest)
  local inv_size = inv and #inv or 0
  local stack_size = prototypes.item["transport-drone"] and prototypes.item["transport-drone"].stack_size or 50
  local bar_pos = inv and inv.supports_bar() and inv.get_bar() or (inv_size + 1)
  local user_drone_count = 0
  local return_drone_count = 0
  if inv then
    for i = 1, inv_size do
      local stack = inv[i]
      if stack.valid_for_read and stack.name == "transport-drone" then
        if i < bar_pos then
          user_drone_count = user_drone_count + stack.count
        else
          return_drone_count = return_drone_count + stack.count
        end
      end
    end
  end
  local drone_count = user_drone_count + return_drone_count
  local capacity = inv_size * stack_size
  local bar_value = capacity > 0 and (drone_count / capacity) or 0
  local bar_tooltip = floor(bar_value * 100) .. "%"
  if bar_value > 1 then bar_value = 1 end

  local header_flow = flow.header_flow
  if not header_flow then
    header_flow = flow.add{type = "flow", name = "header_flow"}
    header_flow.style.vertical_align = "center"
    header_flow.add{
      type = "sprite-button",
      sprite = "item/transport-drone",
      number = drone_count,
      tooltip = bar_tooltip,
      style = "transparent_slot",
      name = "drone_icon"
    }
    local name_label = header_flow.add{type = "label", caption = prototypes.item["transport-drone"].localised_name}
    name_label.style.left_padding = 3
    header_flow.add{type = "empty-widget"}.style.horizontally_stretchable = true
    header_flow.add{
      type = "label", name = "max_label",
      caption = "/ " .. util.format_number(capacity, true),
      tooltip = tostring(capacity)
    }.style.font_color = {0.6, 0.6, 0.6}
    widgets.update_status_dot(header_flow, depot)
  else
    header_flow.drone_icon.number = drone_count
    header_flow.drone_icon.tooltip = bar_tooltip
    local max_label = header_flow.max_label
    if max_label then
      max_label.caption = "/ " .. util.format_number(capacity, true)
      max_label.tooltip = tostring(capacity)
    end
    widgets.update_status_dot(header_flow, depot)
  end

  -- Inventory progress bar
  local inv_bar = flow.inv_bar
  if not inv_bar then
    inv_bar = flow.add{type = "progressbar", name = "inv_bar", value = bar_value}
    inv_bar.style.horizontally_stretchable = true
    inv_bar.style.height = 8
    inv_bar.tooltip = bar_tooltip
  else
    inv_bar.value = bar_value
    inv_bar.tooltip = bar_tooltip
  end

  -- User slots progress bar (blue tint)
  local user_capacity = (bar_pos - 1) * stack_size
  local user_bar_value = user_capacity > 0 and (user_drone_count / user_capacity) or 0
  if user_bar_value > 1 then user_bar_value = 1 end
  local user_bar_tooltip = {"dispatcher-user-bar-tooltip", user_drone_count, user_capacity}
  local user_bar = flow.user_bar
  if not user_bar then
    user_bar = flow.add{type = "progressbar", name = "user_bar", value = user_bar_value}
    user_bar.style.horizontally_stretchable = true
    user_bar.style.height = 8
    user_bar.style.color = {0.3, 0.5, 0.8}
    user_bar.tooltip = user_bar_tooltip
  else
    user_bar.value = user_bar_value
    user_bar.tooltip = user_bar_tooltip
  end

  -- Return slots progress bar (red tint)
  local return_capacity = (inv_size - bar_pos + 1) * stack_size
  local return_bar_value = return_capacity > 0 and (return_drone_count / return_capacity) or 0
  if return_bar_value > 1 then return_bar_value = 1 end
  local return_bar_tooltip = {"dispatcher-return-bar-tooltip", return_drone_count, return_capacity}
  local return_bar = flow.return_bar
  if not return_bar then
    return_bar = flow.add{type = "progressbar", name = "return_bar", value = return_bar_value}
    return_bar.style.horizontally_stretchable = true
    return_bar.style.height = 8
    return_bar.style.color = {0.8, 0.3, 0.3}
    return_bar.tooltip = return_bar_tooltip
  else
    return_bar.value = return_bar_value
    return_bar.tooltip = return_bar_tooltip
  end

  widgets.update_priority_section(flow, depot)
  widgets.update_channel_section(flow, depot)
end

local update_dispatcher_depots = function(depots, gui, channel_filter)

  if not depots or not gui then return end

  for index, depot in pairs(depots) do
    if depot.entity.valid then
      local depot_frame = gui[index]
      if not depot_frame then
        depot_frame = gui.add{type = "flow", name = index}
        depot_frame.style.horizontally_stretchable = true
        depot_frame.style.maximal_width = depot_max_width
        widgets.add_depot_map_button(depot, depot_frame, map_size)
      end
      update_dispatcher_depot_gui(depot, depot_frame)
      if channel_filter then
        depot_frame.visible = channel_filter_match(channel_filter, depot.channel)
      else
        depot_frame.visible = true
      end
    end
  end

  for k, gui in pairs(gui.children) do
    if not depots[gui.name] then
      gui.destroy()
    end
  end
end

function dispatcher_tab.refresh(player, force)
  if not force and not helpers.is_tab_selected(player, "dispatcher_tab") then return end
  local tab = helpers.get_tab(player, "dispatcher_tab")
  if not tab then return end
  local network = helpers.get_selected_network(player)
  update_dispatcher_depots(network.depots.dispatcher, tab.depot_table, helpers.get_channel_filter_value(player))
end

function dispatcher_tab.add(tabbed_pane, network)
  local tab = tabbed_pane.add{type = "tab", caption = {"dispatcher-depots-tab"}}
  local contents = tabbed_pane.add{type = "scroll-pane", name = "dispatcher_tab", style = "naked_scroll_pane"}

  local depots = network.depots.dispatcher

  if not depots then
    tab.enabled = false
    tabbed_pane.add_tab(tab, contents)
    return
  end

  local depot_table = contents.add{type = "table", column_count = 2, style = "bordered_table", name = "depot_table"}
  depot_table.style.horizontally_stretchable = true

  update_dispatcher_depots(depots, depot_table)

  tabbed_pane.add_tab(tab, contents)
end

return dispatcher_tab
