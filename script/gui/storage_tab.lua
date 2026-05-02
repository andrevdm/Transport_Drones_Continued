local helpers = require("script/gui/helpers")
local widgets = require("script/gui/depot_widgets")

local floor = helpers.floor
local get_item_icon_and_locale = helpers.get_item_icon_and_locale
local channel_filter_match = helpers.channel_filter_match
local map_size = helpers.map_size
local depot_max_width = helpers.depot_max_width

local storage_tab = {}

local update_storage_depot_gui = function(depot, gui, filter, channel_filter)

  local flow = gui.holding_flow
  if not flow then
    flow = gui.add{type = "table", column_count = 1, name = "holding_flow"}
    flow.style.horizontally_stretchable = true
    flow.style.left_margin = 2
  end

  local sf_name = depot.storage_filter_item
  local filter_match = (not filter) or (depot.old_contents[filter.name] ~= nil) or (sf_name and sf_name == filter.name)
  local visible = filter_match
    and ((not channel_filter) or channel_filter_match(channel_filter, depot.channel))
  gui.visible = visible or false
  if not visible then return end

  -- Compute inventory contents and capacity
  local inv_slots = 0
  if depot.entity and depot.entity.valid then
    local inv = depot.entity.get_output_inventory()
    if inv then
      inv_slots = #inv
    end
  end

  -- Remove legacy filter row if present
  if flow.filter_row then flow.filter_row.destroy() end

  -- Items section: individual rows with icon + name + max
  -- When empty but filtered, show the filter item at count 0
  local items_flow = flow.items_flow
  if not items_flow then
    items_flow = flow.add{type = "flow", name = "items_flow", direction = "vertical"}
    items_flow.style.horizontally_stretchable = true
    items_flow.style.padding = 0
  end

  local display_contents = depot.old_contents
  if not next(display_contents) and sf_name then
    display_contents = {[sf_name] = 0}
  end

  if next(display_contents) then
    for name, count in pairs(display_contents) do
      local item_locale = get_item_icon_and_locale(name)
      if item_locale then
        local proto = prototypes.item[item_locale.item_name or name]
        local max_count = proto and (inv_slots * proto.stack_size) or 0
        local item_row = items_flow[name]
        if not item_row then
          item_row = items_flow.add{type = "flow", name = name, direction = "horizontal"}
          item_row.style.vertical_align = "center"
          item_row.style.horizontally_stretchable = true
          item_row.add{
            type = "sprite-button",
            sprite = item_locale.icon,
            number = count,
            tooltip = floor(count),
            style = "transparent_slot",
            name = "icon"
          }
          local label = item_row.add{type = "label", caption = item_locale.locale, name = "name_label"}
          label.style.left_padding = 3
          item_row.add{type = "empty-widget"}.style.horizontally_stretchable = true
          local max_label = item_row.add{
            type = "label", name = "max_label",
            caption = "/ " .. util.format_number(max_count, true),
            tooltip = tostring(floor(max_count))
          }
          max_label.style.font_color = {0.6, 0.6, 0.6}
        else
          item_row.icon.number = count
          item_row.icon.tooltip = floor(count)
          item_row.max_label.caption = "/ " .. util.format_number(max_count, true)
          item_row.max_label.tooltip = tostring(floor(max_count))
        end
      end
    end
  else
    if not items_flow.no_items_label then
      local row = items_flow.add{type = "flow", name = "no_items_label"}
      row.style.vertical_align = "center"
      local spacer = row.add{type = "empty-widget"}
      spacer.style.width = 1
      spacer.style.height = 32
      row.add{type = "label", caption = {"no-items-in-depot"}}.style.left_padding = 3
    end
  end

  -- Remove items no longer present
  for _, child in pairs(items_flow.children) do
    if child.name ~= "no_items_label" and not display_contents[child.name] then
      child.destroy()
    end
  end
  -- Remove "no items" label when items exist
  if next(display_contents) and items_flow.no_items_label then
    items_flow.no_items_label.destroy()
  end

  -- Status dot: inline on first item row (after max_label)
  if flow.status_dot then flow.status_dot.destroy() end
  local first_item_row = nil
  for _, child in pairs(items_flow.children) do
    if child.name ~= "no_items_label" then
      if not first_item_row then
        first_item_row = child
      elseif child.status_dot then
        child.status_dot.destroy()
      end
    end
  end
  if first_item_row then
    widgets.update_status_dot(first_item_row, depot)
  end

  -- Progress bar: inventory fullness
  local bar_value = 0
  local bar_tooltip = "0%"
  if depot.entity and depot.entity.valid then
    local inv = depot.entity.get_output_inventory()
    if inv then
      local total = #inv
      local used = total - inv.count_empty_stacks()
      bar_value = total > 0 and (used / total) or 0
      bar_tooltip = floor(bar_value * 100) .. "%"
      if bar_value > 1 then bar_value = 1 end
    end
  end

  local capacity_bar = flow.capacity_bar
  if not capacity_bar then
    capacity_bar = flow.add{type = "progressbar", name = "capacity_bar", value = bar_value}
    capacity_bar.style.horizontally_stretchable = true
    capacity_bar.style.height = 8
    capacity_bar.tooltip = bar_tooltip
  else
    capacity_bar.value = bar_value
    capacity_bar.tooltip = bar_tooltip
  end

  widgets.update_priority_section(flow, depot)
  widgets.update_channel_section(flow, depot)
  widgets.update_threshold_section(flow, depot)
end

local update_storage_depots = function(depots, gui, filter, channel_filter)

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
      update_storage_depot_gui(depot, depot_frame, filter, channel_filter)
    end
  end

  for k, gui in pairs(gui.children) do
    if not depots[gui.name] then
      gui.destroy()
    end
  end

end

function storage_tab.refresh(player, force)
  if not force and not helpers.is_tab_selected(player, "storage_tab") then return end
  local tab = helpers.get_tab(player, "storage_tab")
  if not tab then return end
  local network = helpers.get_selected_network(player)
  update_storage_depots(network.depots.storage, tab.depot_table, helpers.get_filter_value(player), helpers.get_channel_filter_value(player))
end

function storage_tab.add(tabbed_pane, network)
  local tab = tabbed_pane.add{type = "tab", caption = {"storage-depots"}}
  local contents = tabbed_pane.add{type = "scroll-pane", name = "storage_tab", style = "naked_scroll_pane"}

  local depots = network.depots.storage

  if not depots or not next(depots) then
    tab.enabled = false
    tabbed_pane.add_tab(tab, contents)
    return
  end

  local depot_table = contents.add{type = "table", column_count = 2, style = "bordered_table", name = "depot_table"}
  depot_table.style.horizontally_stretchable = true

  update_storage_depots(depots, depot_table)

  tabbed_pane.add_tab(tab, contents)
end

return storage_tab
