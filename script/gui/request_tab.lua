local helpers = require("script/gui/helpers")
local widgets = require("script/gui/depot_widgets")

local floor = helpers.floor
local get_item_icon_and_locale = helpers.get_item_icon_and_locale
local channel_filter_match = helpers.channel_filter_match
local map_size = helpers.map_size
local depot_max_width = helpers.depot_max_width

local request_tab = {}

local update_request_depot_gui = function(depot, gui, filter, channel_filter)

  local flow = gui.holding_flow
  if not flow then
    flow = gui.add{type = "table", column_count = 1, name = "holding_flow"}
    flow.style.horizontally_stretchable = true
    flow.style.left_margin = 2
  end

  local item = depot.item
  local item_key = item and shared.supply_key(item, depot.item_quality) or item
  local visible = ((not filter) or filter.name == item)
    and ((not channel_filter) or channel_filter_match(channel_filter, depot.channel))
  gui.visible = visible or false

  if not visible then return end

  local bar_value = 0
  local bar_tooltip = "0%"

  if not item then
    if flow.header_flow then
      flow.clear()
    end
    if not flow.no_request_label then
      local row = flow.add{type = "flow", name = "no_request_label"}
      row.style.vertical_align = "center"
      local spacer = row.add{type = "empty-widget"}
      spacer.style.width = 1
      spacer.style.height = 32
      local label = row.add{type = "label", caption = {"no-items-in-depot"}}
      label.style.left_padding = 3
    end
  end

  if item then
    if flow.no_request_label then
      flow.clear()
    end

    local item_locale = get_item_icon_and_locale(item_key)

    if item_locale then

      -- Item header: icon with count + name + right-aligned max
      local header_flow = flow.header_flow
      local current_count = floor(depot:get_current_amount())
      local requested_count = depot.circuit_limit or depot.storage_limit or depot:get_storage_size()
      local max_overridden = depot.circuit_limit ~= nil or depot.storage_limit ~= nil
      local max_color = max_overridden and {1, 0.7, 0} or {0.6, 0.6, 0.6}
      local max_tooltip = max_overridden and {"", {"storage-limit-override-tooltip"}, "\n", tostring(requested_count)} or tostring(requested_count)
      if not header_flow then
        header_flow = flow.add{type = "flow", name = "header_flow"}
        header_flow.style.vertical_align = "center"
        header_flow.add{
          type = "sprite-button",
          sprite = item_locale.icon,
          number = current_count,
          tooltip = current_count,
          style = "transparent_slot",
          name = "count"
        }
        local name_label = header_flow.add{type = "label", caption = item_locale.locale}
        name_label.style.left_padding = 3
        local header_pusher = header_flow.add{type = "empty-widget"}
        header_pusher.style.horizontally_stretchable = true
        local max_label = header_flow.add{
          type = "label", name = "max_label",
          caption = "/ " .. util.format_number(requested_count, true),
          tooltip = max_tooltip
        }
        max_label.style.font_color = max_color
        widgets.update_status_dot(header_flow, depot)
      else
        header_flow.count.number = current_count
        header_flow.count.tooltip = current_count
        header_flow.max_label.caption = "/ " .. util.format_number(requested_count, true)
        header_flow.max_label.tooltip = max_tooltip
        header_flow.max_label.style.font_color = max_color
        widgets.update_status_dot(header_flow, depot)
      end

      bar_value = requested_count > 0 and (current_count / requested_count) or 0
      bar_tooltip = floor(bar_value * 100) .. "%"
      if bar_value > 1 then bar_value = 1 end

    end
  end

  -- Progress bar: always shown for consistent layout
  local item_bar = flow.item_bar
  if not item_bar then
    item_bar = flow.add{type = "progressbar", name = "item_bar", value = bar_value}
    item_bar.style.horizontally_stretchable = true
    item_bar.style.height = 8
    item_bar.tooltip = bar_tooltip
  else
    item_bar.value = bar_value
    item_bar.tooltip = bar_tooltip
  end

  widgets.update_drone_section(flow, depot)
  widgets.update_fuel_bar_section(flow, depot)
  widgets.update_priority_section(flow, depot)
  widgets.update_channel_section(flow, depot)

  if depot.is_buffer_depot then
    widgets.update_threshold_section(flow, depot)
  end

end

local update_request_depots = function(depots, gui, filter, channel_filter)

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
      update_request_depot_gui(depot, depot_frame, filter, channel_filter)
    end
  end

  for k, gui in pairs (gui.children) do
    if not depots[gui.name] then
      gui.destroy()
    end
  end

end

function request_tab.refresh(player, force)
  if not force and not helpers.is_tab_selected(player, "request_tab") then return end
  local tab = helpers.get_tab(player, "request_tab")
  if not tab then return end
  local network = helpers.get_selected_network(player)
  update_request_depots(network.depots.request, tab.depot_table, helpers.get_filter_value(player), helpers.get_channel_filter_value(player))
end

function request_tab.refresh_buffer(player, force)
  if not force and not helpers.is_tab_selected(player, "buffer_tab") then return end
  local tab = helpers.get_tab(player, "buffer_tab")
  if not tab then return end
  local network = helpers.get_selected_network(player)
  update_request_depots(network.depots.buffer, tab.depot_table, helpers.get_filter_value(player), helpers.get_channel_filter_value(player))
end

function request_tab.add(tabbed_pane, network)
  local tab = tabbed_pane.add{type = "tab", caption = {"request-depots"}}
  local contents = tabbed_pane.add{type = "scroll-pane", name = "request_tab", style = "naked_scroll_pane"}

  local depots = network.depots.request
  if not depots then
    tab.enabled = false
    tabbed_pane.add_tab(tab, contents)
    return
  end

  local depot_table = contents.add{type = "table", column_count = 2, style = "bordered_table", name = "depot_table"}
  depot_table.style.horizontally_stretchable = true
  update_request_depots(depots, depot_table)

  tabbed_pane.add_tab(tab, contents)
end

function request_tab.add_buffer(tabbed_pane, network)
  local tab = tabbed_pane.add{type = "tab", caption = {"buffer-depots"}}
  local contents = tabbed_pane.add{type = "scroll-pane", name = "buffer_tab", style = "naked_scroll_pane"}

  local depots = network.depots.buffer
  if not depots then
    tab.enabled = false
    tabbed_pane.add_tab(tab, contents)
    return
  end

  local depot_table = contents.add{type = "table", column_count = 2, style = "bordered_table", name = "depot_table"}
  depot_table.style.horizontally_stretchable = true
  update_request_depots(depots, depot_table)

  tabbed_pane.add_tab(tab, contents)
end

return request_tab
