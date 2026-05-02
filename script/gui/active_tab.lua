local helpers = require("script/gui/helpers")
local widgets = require("script/gui/depot_widgets")

local floor = helpers.floor
local get_item_icon_and_locale = helpers.get_item_icon_and_locale
local channel_filter_match = helpers.channel_filter_match
local map_size = helpers.map_size
local depot_max_width = helpers.depot_max_width

local active_tab = {}

local update_active_depot_gui = function(depot, gui, channel_filter)

  local flow = gui.table
  if not flow then
    flow = gui.add{type = "table", column_count = 1, name = "table"}
    flow.style.horizontally_stretchable = true
    flow.style.left_margin = 2
  end

  if channel_filter then
    gui.visible = channel_filter_match(channel_filter, depot.channel)
  else
    gui.visible = true
  end
  if not gui.visible then return end

  -- Migration: old layout used table with sprite-buttons
  if flow.items_flow and flow.items_flow.type == "table" then
    flow.clear()
  end

  -- Compute inventory contents and capacity
  local contents = {}
  local inv_slots = 0
  local is_fluid = depot.fluid_mode
  if is_fluid then
    -- Fluid mode: read from fluidbox
    local fb = depot.entity.fluidbox
    if fb then
      inv_slots = floor(fb.get_capacity(1) or 0)
      for i = 1, 2 do
        local box = fb[i]
        if box and box.amount > 0 then
          contents[box.name] = (contents[box.name] or 0) + floor(box.amount)
        end
      end
    end
  elseif depot.item_chest and depot.item_chest.valid then
    local inv = depot.item_chest.get_inventory(defines.inventory.chest)
    if inv then
      inv_slots = #inv
      for _, item in pairs(inv.get_contents()) do
        contents[item.name] = (contents[item.name] or 0) + item.count
      end
    end
  end

  -- Items section: individual rows with icon + name + max
  local items_flow = flow.items_flow
  if not items_flow then
    items_flow = flow.add{type = "flow", name = "items_flow", direction = "vertical"}
    items_flow.style.horizontally_stretchable = true
    items_flow.style.padding = 0
  end

  if next(contents) then
    for name, count in pairs(contents) do
      local item_locale = get_item_icon_and_locale(name)
      if item_locale then
        local max_count
        if is_fluid then
          max_count = inv_slots
        else
          local proto = prototypes.item[item_locale.item_name or name]
          max_count = proto and (inv_slots * proto.stack_size) or 0
        end
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
    if child.name ~= "no_items_label" and not contents[child.name] then
      child.destroy()
    end
  end
  -- Remove "no items" label when items exist
  if next(contents) and items_flow.no_items_label then
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

  -- Progress bar: inventory/fluid fullness
  local bar_value = 0
  local bar_tooltip = ""
  if is_fluid then
    local total_count = 0
    for _, c in pairs(contents) do total_count = total_count + c end
    bar_value = inv_slots > 0 and (total_count / inv_slots) or 0
    bar_tooltip = floor(bar_value * 100) .. "%"
  else
    local total_slots = inv_slots
    local used_slots = 0
    if depot.item_chest and depot.item_chest.valid then
      local inv = depot.item_chest.get_inventory(defines.inventory.chest)
      if inv then
        used_slots = total_slots - inv.count_empty_stacks()
      end
    end
    bar_value = total_slots > 0 and (used_slots / total_slots) or 0
    bar_tooltip = floor(bar_value * 100) .. "%"
  end
  if bar_value > 1 then bar_value = 1 end

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

  widgets.update_drone_section(flow, depot)
  widgets.update_fuel_bar_section(flow, depot)
  widgets.update_priority_section(flow, depot)
  widgets.update_channel_section(flow, depot)
end

local update_active_depots = function(depots, gui, channel_filter)

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
      update_active_depot_gui(depot, depot_frame, channel_filter)
    end
  end

  for k, gui in pairs(gui.children) do
    if not depots[gui.name] then
      gui.destroy()
    end
  end

end

function active_tab.refresh(player, force)
  if not force and not helpers.is_tab_selected(player, "active_tab") then return end
  local tab = helpers.get_tab(player, "active_tab")
  if not tab then return end
  local network = helpers.get_selected_network(player)
  update_active_depots(network.depots.active, tab.depot_table, helpers.get_channel_filter_value(player))
end

function active_tab.add(tabbed_pane, network)
  local tab = tabbed_pane.add{type = "tab", caption = {"active-depots"}}
  local contents = tabbed_pane.add{type = "scroll-pane", name = "active_tab", style = "naked_scroll_pane"}

  local depots = network.depots.active
  if not depots then
    tab.enabled = false
    tabbed_pane.add_tab(tab, contents)
    return
  end

  local depot_table = contents.add{type = "table", column_count = 2, style = "bordered_table", name = "depot_table"}
  depot_table.style.horizontally_stretchable = true
  update_active_depots(depots, depot_table)

  tabbed_pane.add_tab(tab, contents)
end

return active_tab
