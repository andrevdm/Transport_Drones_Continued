local road_network = require("script/road_network")
local depot_common = require("script/depot_common")
local factorissimo = require("script/factorissimo")

local helpers = require("script/gui/helpers")
local contents_tab = require("script/gui/contents_tab")
local supply_tab = require("script/gui/supply_tab")
local fuel_tab = require("script/gui/fuel_tab")
local request_tab = require("script/gui/request_tab")
local active_tab = require("script/gui/active_tab")
local storage_tab = require("script/gui/storage_tab")
local dispatcher_tab = require("script/gui/dispatcher_tab")


-- ===== Network frame =====

local make_network_gui = function(inner, network, saved_tab_index)

  local tabbed_pane = inner.add{type = "tabbed-pane", name = "tab_pane"}
  tabbed_pane.style.horizontally_stretchable = true
  tabbed_pane.style.vertically_stretchable = true
  contents_tab.add(tabbed_pane, network)
  active_tab.add(tabbed_pane, network)
  storage_tab.add(tabbed_pane, network)
  supply_tab.add(tabbed_pane, network)
  request_tab.add_buffer(tabbed_pane, network)
  request_tab.add(tabbed_pane, network)
  supply_tab.add_mining(tabbed_pane, network)
  dispatcher_tab.add(tabbed_pane, network)
  fuel_tab.add(tabbed_pane, network)
  tabbed_pane.selected_tab_index = saved_tab_index or 1

end

local refresh_network_gui = function(player, selected_index, saved_tab_index)

  local frame = helpers.get_frame(player)
  if not frame then return end

  local network = helpers.get_network_by_dropdown_index(player, selected_index)

  if not network then return end

  local inner = frame.add{type = "frame", style = "inside_deep_frame", name = "inner_frame", direction = "vertical"}
  inner.style.horizontally_stretchable = true
  inner.style.vertically_stretchable = true

  make_network_gui(inner, network, saved_tab_index)

end

local close_gui = function(player)

  local gui = player.gui.screen
  local frame = gui.road_network_frame

  if frame then
    frame.destroy()
  end
end

local refresh_gui = function(player, force)

  local frame = helpers.get_frame(player)
  if not frame then return end

  local network = helpers.get_selected_network(player)
  if not network then
    close_gui(player)
  end

  contents_tab.refresh(player, force)
  active_tab.refresh(player, force)
  storage_tab.refresh(player, force)
  supply_tab.refresh(player, force)
  request_tab.refresh_buffer(player, force)
  request_tab.refresh(player, force)
  supply_tab.refresh_mining(player, force)
  fuel_tab.refresh(player, force)
  dispatcher_tab.refresh(player, force)

end

local title_caption = {"road-networks"}
local open_gui = function(player, target_surface, target_network_id)
  local networks = road_network.get_networks()
  if not next(networks) then
    player.print({"no-networks"})
    return
  end

  -- Build surface -> network mapping
  local surface_nets = helpers.get_surface_networks()
  if not next(surface_nets) then
    player.print({"no-networks"})
    return
  end

  -- Collect and sort surfaces
  local surface_order = {}
  for si in pairs(surface_nets) do
    surface_order[#surface_order + 1] = si
  end
  table.sort(surface_order)

  -- Pick target surface: explicit > player's current > first available
  local selected_surface = nil
  if target_surface then
    for i, si in ipairs(surface_order) do
      if si == target_surface then selected_surface = i; break end
    end
  end
  if not selected_surface then
    local player_si = factorissimo.resolve_planet_surface(player.surface.index)
    for i, si in ipairs(surface_order) do
      if si == player_si then selected_surface = i; break end
    end
  end
  if not selected_surface then selected_surface = 1 end

  local current_surface_index = surface_order[selected_surface]

  local gui = player.gui.screen

  local frame = gui.road_network_frame
  local saved_tab_index = storage.gui_tab_index and storage.gui_tab_index[player.index]
  if frame then
    if not saved_tab_index then
      local inner = frame.inner_frame
      if inner then
        local tab_pane = inner.tab_pane
        if tab_pane then saved_tab_index = tab_pane.selected_tab_index end
      end
    end
    frame.clear()
  else
    frame = gui.add{type = "frame", direction = "vertical", name = "road_network_frame"}
  end
  local max_h = (player.display_resolution.height * 0.9) / player.display_scale
  local max_w = (player.display_resolution.width * 0.9) / player.display_scale
  frame.style.width = math.min(1000, max_w)
  frame.style.height = math.min(765, max_h)

  local title_flow = frame.add{type = "flow", name = "title_flow"}

  local title = title_flow.add{type = "label", caption = title_caption, style = "frame_title"}
  title.drag_target = frame

  local pusher = title_flow.add{type = "empty-widget", style = "draggable_space_header"}
  pusher.style.horizontally_stretchable = true
  pusher.style.height = 24
  pusher.drag_target = frame

  -- Surface dropdown
  local surface_drop = title_flow.add{type = "drop-down", name = "road_network_surface_drop_down", tooltip = {"surface-dropdown-tooltip"}}
  for _, si in ipairs(surface_order) do
    local surface = game.surfaces[si]
    if surface then
      surface_drop.add_item(helpers.surface_dropdown_caption(surface))
    end
  end
  surface_drop.style.minimal_width = 150
  surface_drop.style.bottom_margin = 1
  surface_drop.tags = {surfaces = surface_order}
  surface_drop.selected_index = selected_surface

  -- Network dropdown (filtered to current surface)
  local net_drop = title_flow.add{type = "drop-down", name = "road_network_drop_down", tooltip = {"network-dropdown-tooltip"}}

  local net_ids_on_surface = surface_nets[current_surface_index] or {}
  local network_order = {}
  local net_selected
  local big = 0
  local count = 0
  local found_target = false
  for net_id, network in pairs(networks) do
    if net_ids_on_surface[net_id] then
      count = count + 1
      network_order[count] = net_id
      local size = helpers.network_size(network)
      net_drop.add_item({"road-network-size", count, size})
      if target_network_id and net_id == target_network_id then
        net_selected = count
        found_target = true
      elseif not found_target and size > big then
        big = size
        net_selected = count
      end
    end
  end
  net_drop.tags = {networks = network_order}
  net_drop.style.bottom_margin = 1

  -- Channel filter
  local channel_label = title_flow.add{type = "label", caption = {"channel-filter"}, tooltip = {"channel-filter-tooltip"}}
  channel_label.style.font_color = {0.7, 0.7, 0.7}
  channel_label.style.left_margin = 2
  channel_label.style.top_margin = 3
  local channel_field = title_flow.add{type = "textfield", name = "channel_filter_field", text = "-1", tooltip = {"channel-filter-tooltip"}}
  channel_field.style.width = 50
  channel_field.style.height = 28
  channel_field.style.horizontal_align = "center"
  channel_field.style.top_padding = 0
  channel_field.style.bottom_padding = 0
  channel_field.style.top_margin = -2
  local reset_btn = title_flow.add{type = "sprite-button", name = "channel_filter_reset", sprite = "utility/reset", style = "tool_button", tooltip = {"channel-filter-tooltip"}}
  reset_btn.style.size = 26
  reset_btn.style.top_margin = 1
  reset_btn.style.bottom_margin = 1

  -- Item filter
  local filter_label = title_flow.add{type = "label", caption = {"filter"}, tooltip = {"filter-label-tooltip"}}
  filter_label.style.font_color = {0.7, 0.7, 0.7}
  filter_label.style.left_margin = 2
  filter_label.style.top_margin = 3
  local filter = title_flow.add{type = "choose-elem-button", name = "depot_filter_button", elem_type = "signal", tooltip = {"filter-label-tooltip"}}
  filter.style.width = 28
  filter.style.height = 28
  filter.style.right_margin = 4
  filter.style.top_margin = -1
  filter.style.bottom_margin = 1

  local close_btn = title_flow.add{type = "sprite-button", style = "frame_action_button", sprite = "utility/close", name = "close_road_network_gui"}
  close_btn.style.bottom_margin = 1

  if count == 0 then
    if not frame.auto_center then frame.auto_center = true end
    player.opened = frame
    return
  end

  net_selected = net_selected or 1
  net_drop.selected_index = net_selected

  refresh_network_gui(player, net_selected, saved_tab_index)

  if not frame.auto_center then frame.auto_center = true end
  player.opened = frame

end

-- ===== Event handlers =====

local split = function(str)
  local sep, fields = "/", {}
  local pattern = string.format("([^%s]+)", sep)
  string.gsub(str, pattern, function(c) fields[#fields+1] = c end)
  return fields
end

local on_gui_click = function(event)
  local gui = event.element
  if not (gui and gui.valid) then return end

  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  if not helpers.get_frame(player) then return end
  if gui.get_mod() ~= "Transport_Drones_Continued" then return end

  if gui.name:find("open_depot_map_") then
    local depot_index = gui.name:sub(("open_depot_map_"):len() + 1)
    local depot = depot_common.get_depot_by_index(depot_index)
    if depot then
      player.set_controller({type = defines.controllers.remote, position = depot.entity.position, surface = depot.entity.surface})
      close_gui(player)
    end
    return
  end

  if gui.name == "close_road_network_gui" then
    close_gui(player)
    return
  end

  -- Right-click on any element: clear item filter
  if event.button == defines.mouse_button_type.right then
    helpers.set_filter_value(player, nil)
    refresh_gui(player, true)
    return
  end

  if (gui.name == "supply_info" or gui.name == "request_info") and gui.tags and gui.tags.item_filter then
    local frame = helpers.get_frame(player)
    if frame then
      local item_name = gui.tags.item_filter
      local tab_name = gui.tags.tab_name
      helpers.set_filter_value(player, helpers.get_signal_id(item_name))
      local tab_pane = helpers.get_tab_pane(player)
      if tab_pane and tab_name then
        for i, tab in pairs(tab_pane.tabs) do
          if tab.content and tab.content.name == tab_name then
            tab_pane.selected_tab_index = i
            break
          end
        end
      end
      refresh_gui(player, true)
    end
    return
  end

  if gui.name == "channel_info" and gui.tags and gui.tags.channel_filter then
    local frame = helpers.get_frame(player)
    if frame then
      local channels = gui.tags.channel_filter
      if #channels == 0 or channels[1] == shared.default_channel then
        frame.title_flow.channel_filter_field.text = tostring(shared.default_channel)
      else
        local combined = 0
        for _, ch in pairs(channels) do
          combined = bit32.bor(combined, ch)
        end
        frame.title_flow.channel_filter_field.text = tostring(combined)
      end
      refresh_gui(player, true)
    end
    return
  end

  if gui.name == "channel_filter_reset" then
    local frame = helpers.get_frame(player)
    if frame then
      frame.title_flow.channel_filter_field.text = "-1"
      refresh_gui(player, true)
    end
    return
  end

  if gui.type == "sprite-button" then
    local sprite = gui.sprite
    if sprite and sprite ~= "" then
      local result = split(sprite)
      local signal = {type = result[1], name = result[2]}
      helpers.set_filter_value(player, signal)
      refresh_gui(player, true)
      return
    end
  end

end

local on_gui_selection_state_changed = function(event)
  local gui = event.element
  if not (gui and gui.valid) then return end

  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  if gui.name == "road_network_surface_drop_down" then
    local tags = gui.tags
    if tags and tags.surfaces then
      local si = tags.surfaces[gui.selected_index]
      if si then
        open_gui(player, si, nil)
      end
    end
    return
  end

  if gui.name == "road_network_drop_down" then
    -- Read current surface from surface dropdown
    local frame = helpers.get_frame(player)
    local surface_idx
    if frame then
      local surface_drop = frame.title_flow.road_network_surface_drop_down
      if surface_drop then
        local stags = surface_drop.tags
        if stags and stags.surfaces then
          surface_idx = stags.surfaces[surface_drop.selected_index]
        end
      end
    end
    -- Read selected network_id from tags
    local net_id
    local tags = gui.tags
    if tags and tags.networks then
      net_id = tags.networks[gui.selected_index]
    end
    open_gui(player, surface_idx, net_id)
    return
  end

end

local on_tick = function(event)
  if game.tick % 60 ~= 0 then return end
  for k, player in pairs (game.connected_players) do
    refresh_gui(player)
  end
end

local on_gui_elem_changed = function(event)

  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  refresh_gui(player, true)

end

local on_gui_confirmed = function(event)
  local gui = event.element
  if not (gui and gui.valid) then return end

  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  if gui.name == "channel_filter_field" then
    -- Resolve expression, then refresh
    local value = util.parse_math_input(gui.text)
    if value then gui.text = tostring(math.floor(value)) end
    refresh_gui(player, true)
    return
  end

  -- Resolve expressions on Enter for inline depot fields
  local depot_index = gui.tags and gui.tags.depot_index
  if not depot_index then return end
  local depot = depot_common.get_depot_by_index(depot_index)
  if not depot then return end

  if gui.name == "supply-channel-field" then
    gui.text = tostring(depot.base_channel or shared.default_channel)
  elseif gui.name == "request-storage-limit-field" then
    local value = depot.storage_limit
    gui.text = value and tostring(value) or ""
  elseif gui.name == "supply-threshold-field" then
    local value = depot.supply_threshold
    gui.text = value and tostring(value) or ""
  end
end

local on_gui_text_changed = function(event)
  local gui = event.element
  if not (gui and gui.valid) then return end

  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  if gui.name == "channel_filter_field" then
    refresh_gui(player, true)
    return
  end

  if gui.name == "supply-channel-field" then
    local text = gui.text
    if text == "" or text == "-" then return end
    local value = util.parse_math_input(text)
    if not value then return end
    local depot_index = gui.tags and gui.tags.depot_index
    if not depot_index then return end
    local depot = depot_common.get_depot_by_index(depot_index)
    if not depot then return end
    depot.base_channel = math.floor(value)
    depot.channel = depot.base_channel
    return
  end

  if gui.name == "request-storage-limit-field" then
    local depot_index = gui.tags and gui.tags.depot_index
    if not depot_index then return end
    local depot = depot_common.get_depot_by_index(depot_index)
    if not depot or not depot.drones then return end
    local text = gui.text
    if text == "" then
      depot.storage_limit = nil
    else
      local value = util.parse_math_input(text)
      if value and value > 0 then
        depot.storage_limit = math.floor(value)
      end
    end
    return
  end

  if gui.name == "supply-threshold-field" then
    local depot_index = gui.tags and gui.tags.depot_index
    if not depot_index then return end
    local depot = depot_common.get_depot_by_index(depot_index)
    if not depot then return end
    local text = gui.text
    if text == "" then
      depot.supply_threshold = nil
    else
      local value = util.parse_math_input(text)
      if value and value > 0 then
        depot.supply_threshold = math.floor(value)
      end
    end
    return
  end
end

local on_gui_checked_state_changed = function(event)
  local gui = event.element
  if not (gui and gui.valid) then return end
  if gui.name ~= "supply_allow_bots" then return end

  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  local depot_index = gui.tags and gui.tags.depot_index
  if not depot_index then return end

  local depot = depot_common.get_depot_by_index(depot_index)
  if not depot or not depot.set_allow_bots then return end

  local unlocked = player.force.technologies["transport-logistics"]
    and player.force.technologies["transport-logistics"].researched
  if not unlocked then
    gui.state = false
    return
  end

  depot:set_allow_bots(gui.state)
end

local on_gui_value_changed = function(event)
  local gui = event.element
  if not (gui and gui.valid) then return end
  if gui.name ~= "supply-priority-slider" then return end

  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  if not helpers.get_frame(player) then return end

  local depot_index = gui.tags and gui.tags.depot_index
  if not depot_index then return end

  local depot = depot_common.get_depot_by_index(depot_index)
  if not depot then return end

  local value = math.floor(gui.slider_value)
  depot.base_priority = value
  if depot.update_priority_from_circuit then
    depot:update_priority_from_circuit()
  else
    depot.priority = value
  end

  local flow = gui.parent
  if flow then
    local label = flow["priority-value"]
    if label then
      local effective = depot.priority or value
      label.caption = util.format_number(effective, true)
      if effective ~= value then
        label.style.font_color = {1, 0.7, 0}
      else
        label.style.font_color = {1, 1, 1}
      end
    end
  end
end

local on_gui_selected_tab_changed = function(event)

  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  local tab_index = helpers.get_selected_tab_index(player)
  if tab_index then
    if not storage.gui_tab_index then storage.gui_tab_index = {} end
    storage.gui_tab_index[player.index] = tab_index
  end

  refresh_gui(player)

end

local on_gui_closed = function(event)
  local element = event.element
  if not (element and element.valid) then return end
  if element.name == "road_network_frame" then
    element.destroy()
    return
  end
end

local toggle_gui = function(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end

  local frame = helpers.get_frame(player)
  if frame then
    frame.destroy()
    return
  end

  local nearby_network_id
  local tile_names = {"transport-drone-road", "transport-drone-road-better"}
  local nearby_road_tile = player.surface.find_tiles_filtered{name = tile_names, limit = 1, position = player.position, radius = 32}[1]

  if nearby_road_tile then
    local node = road_network.get_node(player.surface.index, nearby_road_tile.position.x, nearby_road_tile.position.y)
    if node and node.id ~= 0 then
      nearby_network_id = node.id
    end
  end

  -- Resolve factory surfaces to their parent planet
  local target_surface = factorissimo.resolve_planet_surface(player.surface.index)
  open_gui(player, target_surface, nearby_network_id)

end

local on_lua_shortcut = function(event)
  if event.prototype_name ~= "transport-drones-gui" then return end
  toggle_gui(event)
end

commands.add_command("toggle-transport-depot-gui", "idk",
function(command)
  local player = game.player
  if not player then return end
  open_gui(player)
end)

local lib = {}

lib.on_configuration_changed = function()
  for _, player in pairs(game.players) do
    local frame = player.gui.screen.road_network_frame
    if frame then frame.destroy() end
  end
end

lib.events =
{
  [defines.events.on_tick] = on_tick,
  [defines.events.on_gui_click] = on_gui_click,
  [defines.events.on_gui_selection_state_changed] = on_gui_selection_state_changed,
  [defines.events.on_gui_selected_tab_changed] = on_gui_selected_tab_changed,
  [defines.events.on_gui_elem_changed] = on_gui_elem_changed,
  [defines.events.on_gui_confirmed] = on_gui_confirmed,
  [defines.events.on_gui_text_changed] = on_gui_text_changed,
  [defines.events.on_gui_value_changed] = on_gui_value_changed,
  [defines.events.on_gui_checked_state_changed] = on_gui_checked_state_changed,
  [defines.events.on_gui_closed] = on_gui_closed,
  ["toggle-road-network-gui"] = toggle_gui,
  [defines.events.on_lua_shortcut] = on_lua_shortcut
}

return lib
