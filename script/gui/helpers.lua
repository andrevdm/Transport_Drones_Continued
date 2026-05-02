local road_network = require("script/road_network")
local factorissimo = require("script/factorissimo")

local helpers = {}

helpers.map_size = 64 * 3
helpers.depot_max_width = helpers.map_size * 2.5

local floor = math.floor
helpers.floor = floor

local band = bit32.band


function helpers.network_size(network)
  local sum = 0
  for category, depots in pairs (network.depots) do
    sum = sum + table_size(depots)
  end
  return sum
end

function helpers.get_surface_networks()
  local result = {}
  local resolved_cache = {}
  local networks = road_network.get_networks()
  for net_id, network in pairs(networks) do
    local seen = {}
    for category, depots in pairs(network.depots) do
      for _, depot in pairs(depots) do
        if depot.entity and depot.entity.valid then
          local raw_si = depot.entity.surface_index
          local si = resolved_cache[raw_si]
          if si == nil then
            si = factorissimo.resolve_planet_surface(raw_si)
            resolved_cache[raw_si] = si
          end
          if not seen[si] then
            seen[si] = true
            if not result[si] then result[si] = {} end
            result[si][net_id] = true
          end
        end
      end
    end
  end
  return result
end

function helpers.capitalize(s)
  return s:sub(1, 1):upper() .. s:sub(2)
end

function helpers.surface_dropdown_caption(surface)
  local planet = surface.planet
  if planet then
    return "[img=space-location/" .. planet.name .. "]  " .. helpers.capitalize(surface.name)
  end
  return helpers.capitalize(surface.name)
end

function helpers.channel_filter_match(filter_channel, depot_channel)
  return band(filter_channel or shared.default_channel, depot_channel or shared.default_channel) ~= 0
end

-- Item/signal caches

-- Parse compound supply key "item:quality" -> item_name, quality
function helpers.parse_supply_key(key)
  local sep = key:find(":", 1, true)
  if sep then
    return key:sub(1, sep - 1), key:sub(sep + 1)
  end
  return key, nil
end

local item_cache = {}
function helpers.get_item_icon_and_locale(key)
  if item_cache[key] then
    return item_cache[key]
  end

  local name, quality = helpers.parse_supply_key(key)
  local quality_suffix = quality and (" (" .. quality .. ")") or nil

  local items = prototypes.item
  if items[name] then
    local icon = "item/"..name
    local locale = items[name].localised_name
    if quality_suffix then
      locale = {"", locale, " (", {"quality-name." .. quality}, ")"}
    end
    local value = {icon = icon, locale = locale, item_name = name, quality = quality}
    item_cache[key] = value
    return value
  end

  local fluids = prototypes.fluid
  if fluids[name] then
    local icon = "fluid/"..name
    local locale = fluids[name].localised_name
    local value = {icon = icon, locale = locale, item_name = name}
    item_cache[key] = value
    return value
  end
end

local signal_cache = {}
function helpers.get_signal_id(name)
  if signal_cache[name] then
    return signal_cache[name]
  end

  local items = prototypes.item
  if items[name] then
    local value = {type = "item", name = name}
    signal_cache[name] = value
    return value
  end

  local fluids = prototypes.fluid
  if fluids[name] then
    local value = {type = "fluid", name = name}
    signal_cache[name] = value
    return value
  end
end

-- Frame accessors

function helpers.get_frame(player)
  local gui = player.gui.screen
  return gui.road_network_frame
end

function helpers.get_network_by_dropdown_index(player, selected_index)
  local frame = helpers.get_frame(player)
  if not frame then return end
  local dropdown = frame.title_flow.road_network_drop_down
  if not dropdown then return end
  local tags = dropdown.tags
  if not tags or not tags.networks then return end
  local net_id = tags.networks[selected_index]
  if not net_id then return end
  return road_network.get_network_by_id(net_id)
end

function helpers.get_selected_network(player)
  local frame = helpers.get_frame(player)
  if not frame then return end
  local dropdown = frame.title_flow.road_network_drop_down
  if not dropdown then return end
  return helpers.get_network_by_dropdown_index(player, dropdown.selected_index)
end

function helpers.get_tab_pane(player)
  local frame = helpers.get_frame(player)
  if not frame then return end
  return frame.inner_frame.tab_pane
end

function helpers.get_tab(player, tab_name)
  local pane = helpers.get_tab_pane(player)
  if not pane then return end
  return pane[tab_name]
end

function helpers.get_selected_tab_index(player)
  local tab_pane = helpers.get_tab_pane(player)
  if tab_pane then return tab_pane.selected_tab_index end
end

function helpers.is_tab_selected(player, tab_name)
  local tab_pane = helpers.get_tab_pane(player)
  if not tab_pane then return false end
  local idx = tab_pane.selected_tab_index
  if not idx then return false end
  local tab = tab_pane.tabs[idx]
  return tab and tab.content and tab.content.name == tab_name
end

function helpers.get_filter_value(player)
  local frame = helpers.get_frame(player)
  if not frame then return end
  return frame.title_flow.depot_filter_button.elem_value
end

function helpers.set_filter_value(player, value)
  local frame = helpers.get_frame(player)
  if not frame then return end
  frame.title_flow.depot_filter_button.elem_value = value
end

function helpers.get_channel_filter_value(player)
  local frame = helpers.get_frame(player)
  if not frame then return nil end
  local tf = frame.title_flow and frame.title_flow.channel_filter_field
  if not tf then return nil end
  local val = tonumber(tf.text)
  if not val or val == shared.default_channel then return nil end
  return val
end

return helpers
