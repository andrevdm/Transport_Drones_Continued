local depot_common = require("script/depot_common")
local helpers = require("script/gui/helpers")

local floor = helpers.floor
local get_item_icon_and_locale = helpers.get_item_icon_and_locale
local channel_filter_match = helpers.channel_filter_match

local contents_tab = {}

local update_contents_table = function(contents_table, network, filter, sort, channel_filter)

  local supply = network.item_supply

  -- Pre-compute requester counts per item
  local request_counts = {}
  if network.depots then
    for _, category in pairs({"request", "buffer"}) do
      local depots = network.depots[category]
      if depots then
        for _, depot in pairs(depots) do
          if depot.item and depot.entity.valid then
            if not channel_filter or channel_filter_match(channel_filter, depot.channel) then
              local key = shared.supply_key(depot.item, depot.item_quality)
              request_counts[key] = (request_counts[key] or 0) + 1
            end
          end
        end
      end
    end
  end

  -- Compute per-item stats: sum, depot_count, channels, capacity
  local cached_stats = {}
  for name, counts in pairs(supply) do
    local sum = 0
    local depot_count = 0
    local channels = {}
    local capacity = 0
    local item_name = helpers.parse_supply_key(name)
    local is_fluid = prototypes.fluid[item_name] ~= nil
    local stack_size = (not is_fluid) and (prototypes.item[item_name] and prototypes.item[item_name].stack_size or 1) or 1
    for depot_id, count in pairs(counts) do
      if not channel_filter then
        sum = sum + count
        depot_count = depot_count + 1
        local depot = depot_common.get_depot_by_index(depot_id)
        if depot then
          channels[depot.channel or shared.default_channel] = true
          if depot.entity.valid then
            if depot.optional_road_connection then
              local cap_setting = settings.startup["af-mining-drones-capacity"]
              capacity = capacity + (cap_setting and cap_setting.value or 100) * 100
            elseif is_fluid then
              local fb = depot.entity.fluidbox
              if fb then capacity = capacity + fb.get_capacity(1) end
            else
              local inv = depot.entity.get_output_inventory()
              if inv then capacity = capacity + #inv * stack_size end
            end
          end
        end
      else
        local depot = depot_common.get_depot_by_index(depot_id)
        if depot and channel_filter_match(channel_filter, depot.channel) then
          sum = sum + count
          depot_count = depot_count + 1
          channels[depot.channel or shared.default_channel] = true
          if depot.entity.valid then
            if depot.optional_road_connection then
              local cap_setting = settings.startup["af-mining-drones-capacity"]
              capacity = capacity + (cap_setting and cap_setting.value or 100) * 100
            elseif is_fluid then
              local fb = depot.entity.fluidbox
              if fb then capacity = capacity + fb.get_capacity(1) end
            else
              local inv = depot.entity.get_output_inventory()
              if inv then capacity = capacity + #inv * stack_size end
            end
          end
        end
      end
    end
    cached_stats[name] = {sum = sum, depot_count = depot_count, channels = channels, capacity = capacity}
  end

  if sort then
    local sorted_supply = {}
    local k = 1
    for name, counts in pairs(supply) do
      sorted_supply[k] = {name, cached_stats[name].sum, counts}
      k = k + 1
    end
    table.sort(sorted_supply, function(a, b) return a[2] > b[2] end)
    supply = {}
    for k = 1, #sorted_supply do
      local entry = sorted_supply[k]
      supply[entry[1]] = entry[3]
    end
  end

  for name, counts in pairs(supply) do
    local item_locale = get_item_icon_and_locale(name)

    if item_locale then
      local item_visible = (not filter or filter.name == name)
      local flow = contents_table[name]
      local stats = cached_stats[name]
      local sum = floor(stats.sum)

      if item_visible and sum > 0 then
        local req_count = request_counts[name] or 0
        local supply_text = stats.depot_count .. " Supply"
        local request_text = req_count .. " Request"
        local capacity = stats.capacity
        local bar_value = capacity > 0 and math.min(sum / capacity, 1) or 1
        local capacity_label = capacity > 0 and ("/ " .. util.format_number(capacity, true)) or ""
        local bar_tooltip = floor(bar_value * 100) .. "%"

        -- Build channel caption
        local ch_channels = {}
        for ch in pairs(stats.channels) do
          if ch ~= shared.default_channel then ch_channels[#ch_channels + 1] = ch end
        end
        table.sort(ch_channels)
        local ch_text = #ch_channels > 0 and ("Channel " .. table.concat(ch_channels, ",")) or ("Channel " .. shared.default_channel)

        if not flow then
          flow = contents_table.add{type = "flow", name = name, direction = "horizontal"}
          flow.style.vertical_align = "top"
          -- Left column: icon+name top, progress bar bottom
          local left = flow.add{type = "flow", name = "left", direction = "vertical"}
          left.style.horizontally_stretchable = true
          left.style.vertically_stretchable = true
          local header = left.add{type = "flow", name = "header"}
          header.style.vertical_align = "center"
          header.add{
            type = "sprite-button",
            sprite = item_locale.icon,
            number = sum,
            style = "transparent_slot",
            name = "count",
            tooltip = sum
          }
          local name_label = header.add{type = "label", caption = item_locale.locale}
          name_label.style.left_padding = 3
          header.add{type = "empty-widget"}.style.horizontally_stretchable = true
          header.add{
            type = "label", name = "max_label",
            caption = capacity_label,
            tooltip = capacity > 0 and tostring(capacity) or ""
          }.style.font_color = {0.6, 0.6, 0.6}
          local pusher = left.add{type = "empty-widget"}
          pusher.style.vertically_stretchable = true
          local bar = left.add{type = "progressbar", name = "bar", value = bar_value}
          bar.style.horizontally_stretchable = true
          bar.style.height = 8
          bar.style.bottom_margin = 4
          bar.tooltip = bar_tooltip
          -- Right column: supply / request / channel stacked vertically
          local stats_flow = flow.add{type = "flow", name = "stats", direction = "vertical"}
          stats_flow.style.left_margin = 12
          local supply_label = stats_flow.add{type = "label", name = "supply_info", caption = supply_text, tags = {item_filter = name, tab_name = "supply_tab"}}
          supply_label.style.font_color = {1, 0.5, 0.5}
          supply_label.style.hovered_font_color = {1, 0.8, 0.8}
          supply_label.tooltip = {"supply-click-tooltip"}
          local req_label = stats_flow.add{type = "label", name = "request_info", caption = request_text, tags = {item_filter = name, tab_name = "request_tab"}}
          req_label.style.font_color = {0.5, 0.7, 1}
          req_label.style.hovered_font_color = {0.8, 0.9, 1}
          req_label.tooltip = {"request-click-tooltip"}
          local ch_tags = #ch_channels > 0 and ch_channels or {shared.default_channel}
          local ch_label = stats_flow.add{type = "label", name = "channel_info", caption = ch_text, tags = {channel_filter = ch_tags}}
          ch_label.style.font_color = {0.6, 0.6, 0.6}
          ch_label.style.hovered_font_color = {0.9, 0.9, 0.9}
          ch_label.tooltip = {"channel-click-tooltip"}
        else
          flow.left.header.count.number = sum
          flow.left.header.count.tooltip = sum
          flow.left.header.max_label.caption = capacity_label
          flow.left.header.max_label.tooltip = capacity > 0 and tostring(capacity) or ""
          flow.left.bar.value = bar_value
          flow.left.bar.tooltip = bar_tooltip
          local stats_flow = flow.stats
          stats_flow.supply_info.caption = supply_text
          stats_flow.request_info.caption = request_text
          stats_flow.channel_info.caption = ch_text
          local ch_tags = #ch_channels > 0 and ch_channels or {shared.default_channel}
          stats_flow.channel_info.tags = {channel_filter = ch_tags}
        end
      end
      local show = item_visible and sum > 0
      if flow then flow.visible = show end
    end
  end
  for k, gui in pairs(contents_table.children) do
    if not network.item_supply[gui.name] then gui.destroy() end
  end
end

function contents_tab.refresh(player, force)
  if not force and not helpers.is_tab_selected(player, "contents_tab") then return end
  local tab = helpers.get_tab(player, "contents_tab")
  if not tab then return end
  local network = helpers.get_selected_network(player)
  update_contents_table(tab.contents_table, network, helpers.get_filter_value(player), nil, helpers.get_channel_filter_value(player))
end

function contents_tab.add(tabbed_pane, network)
  local tab = tabbed_pane.add{type = "tab", caption = {"contents"}}
  local contents = tabbed_pane.add{type = "scroll-pane",  name = "contents_tab", style = "naked_scroll_pane"}
  contents.style.maximal_width = 1900

  local contents_table = contents.add{type = "table", column_count = 4, style = "bordered_table", name = "contents_table"}
  contents_table.style.vertically_stretchable = false

  update_contents_table(contents_table, network, nil, true)

  tabbed_pane.add_tab(tab, contents)
end

return contents_tab
