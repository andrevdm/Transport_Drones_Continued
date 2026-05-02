local helpers = require("script/gui/helpers")
local widgets = require("script/gui/depot_widgets")

local floor = helpers.floor
local get_item_icon_and_locale = helpers.get_item_icon_and_locale
local channel_filter_match = helpers.channel_filter_match
local map_size = helpers.map_size
local depot_max_width = helpers.depot_max_width

local supply_tab = {}

local update_supply_depot_gui = function(depot, gui, filter, channel_filter)

  local flow = gui.holding_flow
  if not flow then
    flow = gui.add{type = "table", column_count = 1, name = "holding_flow"}
    flow.style.horizontally_stretchable = true
    flow.style.left_margin = 2
  end

  local visible = ((not filter) or (depot.old_contents[filter.name] ~= nil))
    and ((not channel_filter) or channel_filter_match(channel_filter, depot.channel))
  gui.visible = visible or false
  if not visible then return end

  -- Migration from old layout
  if flow.items_table or (flow.priority_flow and not flow.priority_line) then
    flow.clear()
  end
  -- Migration: add max_label to item rows
  if flow.items_flow then
    local children = flow.items_flow.children
    if children and children[1] and not children[1].max_label then
      flow.items_flow.clear()
    end
  end

  -- Compute max capacity per item
  local is_mining = depot.optional_road_connection
  local mining_max
  local inv_slots = 0
  local is_fluid = depot.entity.type == "furnace"
  if is_mining then
    local cap_setting = settings.startup["af-mining-drones-capacity"]
    mining_max = (cap_setting and cap_setting.value or 100) * 100
  elseif is_fluid then
    local fb = depot.entity.fluidbox
    inv_slots = fb and fb.get_capacity(1) or 0
  else
    local inv = depot.entity.get_output_inventory()
    if inv then inv_slots = #inv end
  end

  -- Items section: individual rows with icon + name + max
  local items_flow = flow.items_flow
  if not items_flow then
    items_flow = flow.add{type = "flow", name = "items_flow", direction = "vertical"}
    items_flow.style.horizontally_stretchable = true
    items_flow.style.padding = 0
  end

  for name, count in pairs(depot.old_contents) do
    local item_locale = get_item_icon_and_locale(name)
    if item_locale then
      local max_count
      if is_mining then
        max_count = mining_max
      elseif is_fluid then
        max_count = floor(inv_slots)
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

  -- Remove items no longer present
  for _, child in pairs(items_flow.children) do
    if not depot.old_contents[child.name] then
      child.destroy()
    end
  end

  -- Status dot: inline on first item row (after max_label)
  if flow.status_dot then flow.status_dot.destroy() end
  local first_item_row = nil
  for _, child in pairs(items_flow.children) do
    if not first_item_row then
      first_item_row = child
    elseif child.status_dot then
      child.status_dot.destroy()
    end
  end
  if first_item_row then
    widgets.update_status_dot(first_item_row, depot)
  end

  -- Progress bar: inventory/fluid fullness
  local bar_value = 0
  local bar_tooltip = ""
  if is_mining then
    local total_count = 0
    for _, c in pairs(depot.old_contents) do total_count = total_count + c end
    bar_value = mining_max > 0 and (total_count / mining_max) or 0
    bar_tooltip = floor(bar_value * 100) .. "%"
  elseif depot.entity.type == "furnace" then
    local fb = depot.entity.fluidbox
    if fb then
      local capacity = fb.get_capacity(1) or 0
      local amount = floor(depot.entity.get_fluid_count())
      bar_value = capacity > 0 and (amount / capacity) or 0
      bar_tooltip = floor(bar_value * 100) .. "%"
    end
  else
    local inv = depot.entity.get_output_inventory()
    if inv then
      local total = #inv
      local used = total - inv.count_empty_stacks()
      bar_value = total > 0 and (used / total) or 0
      bar_tooltip = floor(bar_value * 100) .. "%"
    end
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

  widgets.update_priority_section(flow, depot)
  widgets.update_channel_section(flow, depot)
  widgets.update_threshold_section(flow, depot)

  -- Allow logistics bots checkbox (supply depots only, not fluid)
  if depot.set_allow_bots then
    widgets.add_separator(flow, "bots_line")
    local bot_check = flow.supply_allow_bots
    if not bot_check then
      local player = gui.gui.player
      local unlocked = player and player.force.technologies["transport-logistics"]
        and player.force.technologies["transport-logistics"].researched
      bot_check = flow.add{
        type = "checkbox", name = "supply_allow_bots",
        caption = {"allow-bots-label"},
        tooltip = unlocked and {"allow-bots-tooltip"} or {"allow-bots-tooltip-locked"},
        state = depot.allow_bots or false,
        tags = {depot_index = depot.index}
      }
      bot_check.enabled = unlocked or false
    else
      bot_check.state = depot.allow_bots or false
    end
  end
end

local update_supply_depots = function(depots, gui, filter, channel_filter)

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
      update_supply_depot_gui(depot, depot_frame, filter, channel_filter)
    end
  end

  for k, gui in pairs (gui.children) do
    if not depots[gui.name] then
      gui.destroy()
    end
  end

end

function supply_tab.refresh(player, force)
  if not force and not helpers.is_tab_selected(player, "supply_tab") then return end
  local tab = helpers.get_tab(player, "supply_tab")
  if not tab then return end
  local network = helpers.get_selected_network(player)
  local all_supply = {}
  if network.depots.supply then
    for k, v in pairs(network.depots.supply) do all_supply[k] = v end
  end
  if network.depots.fluid then
    for k, v in pairs(network.depots.fluid) do all_supply[k] = v end
  end
  update_supply_depots(all_supply, tab.depot_table, helpers.get_filter_value(player), helpers.get_channel_filter_value(player))
end

function supply_tab.add(tabbed_pane, network)
  local tab = tabbed_pane.add{type = "tab", caption = {"supply-depots"}}
  local contents = tabbed_pane.add{type = "scroll-pane", name = "supply_tab", style = "naked_scroll_pane"}

  local all_supply = {}
  if network.depots.supply then
    for k, v in pairs(network.depots.supply) do all_supply[k] = v end
  end
  if network.depots.fluid then
    for k, v in pairs(network.depots.fluid) do all_supply[k] = v end
  end

  if not next(all_supply) then
    tab.enabled = false
    tabbed_pane.add_tab(tab, contents)
    return
  end

  local depot_table = contents.add{type = "table", column_count = 2, style = "bordered_table", name = "depot_table"}
  depot_table.style.horizontally_stretchable = true

  update_supply_depots(all_supply, depot_table)

  tabbed_pane.add_tab(tab, contents)
end

function supply_tab.refresh_mining(player, force)
  local tab = helpers.get_tab(player, "mining_tab")
  if not tab then return end
  local network = helpers.get_selected_network(player)
  local depots = network.depots.mining
  local has_depots = depots and next(depots)

  -- Always update tab enabled state (even when not selected)
  local tabbed_pane = tab.parent
  if tabbed_pane then
    for _, tab_and_content in pairs(tabbed_pane.tabs) do
      if tab_and_content.content == tab then
        tab_and_content.tab.enabled = has_depots and true or false
        break
      end
    end
  end

  -- Only update contents when selected
  if not force and not helpers.is_tab_selected(player, "mining_tab") then return end

  if has_depots then
    if not tab.depot_table then
      local depot_table = tab.add{type = "table", column_count = 2, style = "bordered_table", name = "depot_table"}
      depot_table.style.horizontally_stretchable = true
    end
    update_supply_depots(depots, tab.depot_table, helpers.get_filter_value(player), helpers.get_channel_filter_value(player))
  else
    if tab.depot_table then
      tab.depot_table.destroy()
    end
  end
end

function supply_tab.add_mining(tabbed_pane, network)
  if not prototypes.entity["mining-depot"] then return end

  local tab = tabbed_pane.add{type = "tab", caption = {"mining-depots"}}
  local contents = tabbed_pane.add{type = "scroll-pane", name = "mining_tab", style = "naked_scroll_pane"}

  local depots = network.depots.mining

  if not depots or not next(depots) then
    tab.enabled = false
    tabbed_pane.add_tab(tab, contents)
    return
  end

  local depot_table = contents.add{type = "table", column_count = 2, style = "bordered_table", name = "depot_table"}
  depot_table.style.horizontally_stretchable = true

  update_supply_depots(depots, depot_table)

  tabbed_pane.add_tab(tab, contents)
end

return supply_tab
