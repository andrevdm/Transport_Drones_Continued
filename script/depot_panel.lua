local shared = require("shared")

-- All depot entity names
local depot_names = {
  ["request-depot"] = true,
  ["request-depot-multi"] = true,
  ["buffer-depot"] = true,
  ["buffer-depot-multi"] = true,
  ["fuel-depot"] = true,
  ["fuel-depot-multi"] = true,
  ["supply-depot"] = true,
  ["mining-depot"] = true,
  ["fluid-depot"] = true,
  ["fluid-depot-multi"] = true,
  ["active-depot"] = true,
  [shared.active_depot_fluid_name] = true,
  [shared.active_depot_fluid_name .. "-multi"] = true,
  ["storage-depot"] = true,
  [shared.storage_depot_fluid_name] = true,
  [shared.storage_depot_fluid_name .. "-multi"] = true,
  ["drone-dispatcher"] = true,
}

-- Depots that have a drone chest (request, buffer, fuel, active)
local drone_depot_names = {
  ["request-depot"] = true,
  ["request-depot-multi"] = true,
  ["buffer-depot"] = true,
  ["buffer-depot-multi"] = true,
  ["fuel-depot"] = true,
  ["fuel-depot-multi"] = true,
  ["active-depot"] = true,
  [shared.active_depot_fluid_name] = true,
  [shared.active_depot_fluid_name .. "-multi"] = true
}
for _, name in pairs(shared.active_chest_name) do
  drone_depot_names[name] = true
end

-- Supply chest names (player opens the chest, not the assembler)
local supply_chest_names = {}
for _, name in pairs(shared.supply_chest_name) do
  supply_chest_names[name] = true
end
for _, name in pairs(shared.supply_chest_name_logistic) do
  supply_chest_names[name] = true
end

-- Active depot chest names (player opens the item chest)
local active_chest_names = {}
for _, name in pairs(shared.active_chest_name) do
  active_chest_names[name] = true
end

-- Storage depot chest names (player opens the item chest)
local storage_chest_names = {}
for _, name in pairs(shared.storage_chest_name) do
  storage_chest_names[name] = true
end
for _, name in pairs(shared.storage_chest_name_logistic) do
  storage_chest_names[name] = true
end

-- Dispatcher chest names (player opens the dispatcher chest)
local dispatcher_chest_names = {}
for _, name in pairs(shared.dispatcher_chest_name) do
  dispatcher_chest_names[name] = true
end

-- Drone chest names
local drone_chest_names = {}
for _, name in pairs(shared.drone_chest_name) do
  drone_chest_names[name] = true
end

-- All container-gui entity names (for relative GUI anchor)
local container_panel_names = {}
for _, names in ipairs{
  shared.supply_chest_name, shared.supply_chest_name_logistic,
  shared.active_chest_name, shared.storage_chest_name,
  shared.storage_chest_name_logistic, shared.dispatcher_chest_name
} do
  for _, name in pairs(names) do
    container_panel_names[#container_panel_names + 1] = name
  end
end

local default_priority_signal = {type = "virtual", name = "signal-P"}

-- Per-entity-type description of what priority does
local priority_desc = {
  ["request-depot"] = {"priority-desc-request"},
  ["buffer-depot"] = {"priority-desc-supply"},
  ["fuel-depot"] = {"priority-desc-fuel"},
  ["supply-depot"] = {"priority-desc-supply"},
  ["mining-depot"] = {"priority-desc-supply"},
  ["fluid-depot"] = {"priority-desc-supply"},
  ["active-depot"] = {"priority-desc-request"},
  [shared.active_depot_fluid_name] = {"priority-desc-request"},
}
for _, name in pairs(shared.active_chest_name) do
  priority_desc[name] = {"priority-desc-request"}
end
for _, name in pairs(shared.supply_chest_name) do
  priority_desc[name] = {"priority-desc-supply"}
end
for _, name in pairs(shared.supply_chest_name_logistic) do
  priority_desc[name] = {"priority-desc-supply"}
end
priority_desc["storage-depot"] = {"priority-desc-supply"}
priority_desc[shared.storage_depot_fluid_name] = {"priority-desc-supply"}
for _, name in pairs(shared.storage_chest_name) do
  priority_desc[name] = {"priority-desc-supply"}
end
for _, name in pairs(shared.storage_chest_name_logistic) do
  priority_desc[name] = {"priority-desc-supply"}
end
priority_desc["drone-dispatcher"] = {"priority-desc-dispatcher"}
for _, name in pairs(shared.dispatcher_chest_name) do
  priority_desc[name] = {"priority-desc-dispatcher"}
end
-- Multi-pipe variants inherit priority description from base
for base, multi in pairs(shared.multi_pipe_variants) do
  priority_desc[multi] = priority_desc[base]
end

-- Depot types that show the "Allow central dispatch" toggle (effective_name or entity_name)
local has_central_dispatch_toggle = {
  ["request-depot"] = true, ["buffer-depot"] = true,
  ["supply-depot"] = true, ["active-depot"] = true,
  [shared.active_depot_fluid_name] = true,
  ["storage-depot"] = true,
  [shared.storage_depot_fluid_name] = true,
}
for _, names in ipairs{shared.supply_chest_name, shared.supply_chest_name_logistic, shared.active_chest_name, shared.storage_chest_name, shared.storage_chest_name_logistic} do
  for _, name in pairs(names) do has_central_dispatch_toggle[name] = true end
end

-- Depot types that show supply threshold (effective_name or entity_name)
local has_supply_threshold = {
  ["supply-depot"] = true, ["buffer-depot"] = true,
  ["fluid-depot"] = true, ["mining-depot"] = true, ["storage-depot"] = true,
  [shared.storage_depot_fluid_name] = true,
}
for _, names in ipairs{shared.supply_chest_name, shared.supply_chest_name_logistic,
  shared.storage_chest_name, shared.storage_chest_name_logistic} do
  for _, name in pairs(names) do has_supply_threshold[name] = true end
end

-- Panel layout version - bump to force recreation of persistent relative GUI panels
local PANEL_VERSION = 9

-- Frame names for the four GUI types
local frame_asm = "depot-panel-asm"
local frame_asm_recipe = "depot-panel-asm-recipe"
local frame_furnace = "depot-panel-furnace"
local frame_container = "depot-panel-container"

-- Old frame names to clean up on version upgrade
local old_frame_names = {
  "priority-frame-asm", "priority-frame-furnace", "priority-frame-container",
  "priority-frame-logistic",
  "drone-management-frame",
  "bot-toggle-frame", "buffer-bot-toggle-frame",
}

-- Drone chest back-panel (relative GUI, right of chest)
local chest_frame_name = "drone-chest-back-frame"

-- Track which depot each player has open
local player_open_depot = {}

local function get_depot_for_entity(entity)
  local depots = storage.transport_depots and storage.transport_depots.depots
  if not depots then return end

  -- Direct lookup by unit_number (works for request, buffer, fuel, mining, fluid, and supply chest)
  local depot = depots[tostring(entity.unit_number)]
  if depot and depot.base_priority ~= nil then
    return depot
  end

  -- Supply/storage/dispatcher depot assembler fallback: depot is indexed by chest unit_number
  if entity.name == "supply-depot" or entity.name == "storage-depot" or entity.name == "drone-dispatcher" then
    for _, d in pairs(depots) do
      if d.assembler and d.assembler.valid and d.assembler.unit_number == entity.unit_number then
        return d
      end
    end
  end

  -- Active depot chest: find depot that owns this item chest
  if active_chest_names[entity.name] then
    for _, d in pairs(depots) do
      if d.item_chest and d.item_chest.valid
         and d.item_chest.unit_number == entity.unit_number then
        return d
      end
    end
  end

  -- Drone chest: find depot that owns this chest
  if drone_chest_names[entity.name] then
    for _, d in pairs(depots) do
      if d.drone_chest and d.drone_chest.valid
         and d.drone_chest.unit_number == entity.unit_number then
        return d
      end
    end
  end
end

local function has_logistics_tech(player)
  local tech = player.force.technologies["transport-logistics"]
  return tech and tech.researched
end

local function has_multi_pipe_tech(player)
  local tech = player.force.technologies["transport-multi-pipe"]
  return tech and tech.researched
end

local function get_total_drone_count(depot)
  local inv = depot:get_drone_inventory()
  if not inv then return 0 end
  local count = 0
  for _, item in pairs(inv.get_contents()) do
    if item.name == "transport-drone" then
      count = count + item.count
    end
  end
  return count
end

local drone_stack_size_cache
local function get_drone_stack_size()
  if not drone_stack_size_cache then
    local proto = prototypes.item["transport-drone"]
    drone_stack_size_cache = proto and proto.stack_size or 100
  end
  return drone_stack_size_cache
end

local function get_max_drone_request(depot)
  local inv = depot:get_drone_inventory()
  if not inv then return 50 end
  return #inv * get_drone_stack_size()
end

-- Slider+textfield pair configurations (keyed by slider element name)
local slider_configs = {
  ["drone-request-slider"] = {
    header = "drone-request-header",
    field = "drone-request-field",
    set = function(depot, v) depot.requested_drones = v end,
    get = function(depot) return depot.requested_drones or 0 end,
    min = 0, max = function(depot) return get_max_drone_request(depot) end,
  },
  ["priority-slider"] = {
    header = "priority-header",
    field = "priority-field",
    set = function(depot, v) depot.base_priority = v; depot.priority = v end,
    get = function(depot) return depot.base_priority or shared.default_priority end,
    min = 0, max = 100,
  },
  ["central-dispatch-slider"] = {
    header = "central-dispatch-header",
    field = "central-dispatch-field",
    set = function(depot, v) depot.central_dispatch_percent = v end,
    get = function(depot) return depot.central_dispatch_percent or 50 end,
    min = 0, max = 100,
  },
}

-- Reverse lookup: textfield name -> {slider_name, config}
local field_to_slider = {}
for slider_name, config in pairs(slider_configs) do
  field_to_slider[config.field] = {slider = slider_name, config = config}
end

-- Parse math expressions in text input: "2k" -> 2000, "20*50" -> 1000, "2k+500" -> 2500
-- Helper: add a slider+textfield combo to a parent flow
local function add_slider_with_input(parent, prefix, opts)
  local header = parent.add{type = "flow", name = prefix .. "-header", direction = "horizontal"}
  header.style.vertical_align = "center"
  header.style.horizontally_stretchable = true
  header.add{type = "label", name = prefix .. "-label", caption = {opts.label_key}, tooltip = {opts.tooltip_key}}
  header.add{type = "empty-widget"}.style.horizontally_stretchable = true
  local field = header.add{
    type = "textfield",
    name = prefix .. "-field",
    tooltip = {opts.tooltip_key},
    numeric = true,
    allow_decimal = false,
    allow_negative = false,
    text = tostring(opts.default or 0)
  }
  field.style.width = 50
  field.style.horizontal_align = "center"
  if opts.suffix then
    header.add{type = "label", name = prefix .. "-suffix", caption = opts.suffix}
  end
  local slider = parent.add{
    type = "slider",
    name = prefix .. "-slider",
    minimum_value = opts.min or 0,
    maximum_value = opts.max or 100,
    value = opts.default or 0,
    value_step = opts.step or 1,
    discrete_slider = true,
    tooltip = {opts.tooltip_key}
  }
  slider.style.horizontally_stretchable = true
  return header, slider
end

-- Build the combined panel content
local function make_panel_content(frame)
  local inner = frame.add{type = "frame", name = "panel-inner", style = "inside_shallow_frame_with_padding", direction = "vertical"}
  inner.style.minimal_width = 230

  -- Open drone inventory / Back to depot buttons (top of panel, hidden by default)
  local drone_btn = inner.add{type = "button", name = "drone-open-chest", caption = {"drone-open-inventory"}, tooltip = {"drone-open-inventory-tooltip"}, style = "button"}
  drone_btn.style.horizontally_stretchable = true
  drone_btn.style.bottom_margin = 2
  drone_btn.visible = false
  local back_btn = inner.add{type = "button", name = "drone-back-to-depot", caption = {"drone-back-to-depot"}, tooltip = {"drone-back-to-depot-tooltip"}, style = "button"}
  back_btn.style.horizontally_stretchable = true
  back_btn.style.bottom_margin = 2
  back_btn.visible = false

  -- Drone section (request/buffer/fuel only, hidden by default)
  local drone_flow = inner.add{type = "flow", name = "drone-flow", direction = "vertical"}
  drone_flow.style.horizontally_stretchable = true
  drone_flow.style.horizontal_align = "center"
  local drone_label = drone_flow.add{type = "label", name = "drone-count-label", caption = {"drone-in-stock-active", 0, 0}, tooltip = {"drones-active-available-tooltip"}}

  add_slider_with_input(drone_flow, "drone-request", {
    label_key = "drone-request-label", tooltip_key = "drone-request-tooltip",
    default = 0, max = 50, step = 1, suffix = "/ 0"
  })

  inner.add{type = "line", name = "drone-line", direction = "horizontal"}.style.top_margin = 4
  drone_flow.visible = false
  inner["drone-line"].visible = false

  -- Storage filter section (storage depot only, hidden by default)
  local sf_flow = inner.add{type = "flow", name = "storage-filter-flow", direction = "horizontal"}
  sf_flow.style.vertical_align = "center"
  sf_flow.style.horizontally_stretchable = true
  sf_flow.add{type = "label", name = "storage-filter-label", caption = {"storage-filter-label"}, tooltip = {"storage-filter-tooltip"}}
  sf_flow.add{type = "empty-widget"}.style.horizontally_stretchable = true
  sf_flow.add{
    type = "choose-elem-button",
    name = "storage-filter-chooser",
    elem_type = "item",
    tooltip = {"storage-filter-tooltip"}
  }
  inner.add{type = "line", name = "storage-filter-line", direction = "horizontal"}.style.top_margin = 4

  sf_flow.visible = false
  inner["storage-filter-line"].visible = false

  -- Priority section (all depots)
  add_slider_with_input(inner, "priority", {
    label_key = "priority-label", tooltip_key = "priority-slider-tooltip",
    default = shared.default_priority, max = 100, step = 1
  })

  local desc = inner.add{type = "label", name = "priority-desc", caption = ""}
  desc.style.font_color = {0.6, 0.6, 0.6}
  desc.style.single_line = false

  local sig_flow = inner.add{type = "flow", name = "priority-signal-flow", direction = "horizontal"}
  sig_flow.style.vertical_align = "center"
  sig_flow.style.horizontally_stretchable = true
  local sig_hint = sig_flow.add{type = "label", caption = {"priority-circuit-hint"}, tooltip = {"priority-override-tooltip"}}
  sig_hint.style.font_color = {0.8, 0.8, 0.8}
  sig_flow.add{type = "empty-widget"}.style.horizontally_stretchable = true
  local sig_value = sig_flow.add{type = "label", name = "priority-signal-value", caption = ""}
  sig_value.visible = false
  sig_value.style.font_color = {1, 0.7, 0}
  sig_flow.add{
    type = "choose-elem-button",
    name = "priority-signal-chooser",
    elem_type = "signal",
    signal = default_priority_signal,
    tooltip = {"priority-signal-chooser-tooltip"}
  }

  -- Requester section (request/buffer only, hidden by default)
  inner.add{type = "line", name = "storage-limit-line", direction = "horizontal"}.style.top_margin = 4

  if shared.quality_enabled then
    local qf = inner.add{type = "flow", name = "quality-flow", direction = "horizontal"}
    qf.style.vertical_align = "center"
    qf.style.horizontally_stretchable = true
    qf.style.top_margin = 4
    qf.add{type = "label", name = "quality-label", caption = {"quality-label"}, tooltip = {"quality-tooltip"}}
    qf.add{type = "empty-widget"}.style.horizontally_stretchable = true
    local qd = qf.add{
      type = "drop-down",
      name = "quality-dropdown",
      items = {
        {"", "[img=quality/normal] ", {"quality-name.normal"}},
        {"", "[img=quality/uncommon] ", {"quality-name.uncommon"}},
        {"", "[img=quality/rare] ", {"quality-name.rare"}},
        {"", "[img=quality/epic] ", {"quality-name.epic"}},
        {"", "[img=quality/legendary] ", {"quality-name.legendary"}}
      },
      selected_index = 1,
      tooltip = {"quality-tooltip"}
    }
    qd.style.width = 130
    qf.visible = false
  end

  local limit_flow = inner.add{type = "flow", name = "storage-limit-flow", direction = "horizontal"}
  limit_flow.style.vertical_align = "center"
  limit_flow.style.horizontally_stretchable = true
  limit_flow.add{type = "label", name = "storage-limit-label", caption = {"storage-limit-label"}, tooltip = {"storage-limit-tooltip"}}
  limit_flow.add{type = "empty-widget"}.style.horizontally_stretchable = true
  local limit_field = limit_flow.add{
    type = "textfield",
    name = "storage-limit-field",
    tooltip = {"storage-limit-tooltip"},
    text = ""
  }
  limit_field.style.width = 70
  limit_field.style.horizontal_align = "center"

  local cap_check = inner.add{
    type = "checkbox",
    name = "ignore-capacity-checkbox",
    caption = {"ignore-capacity-label"},
    tooltip = {"ignore-capacity-tooltip"},
    state = false
  }
  cap_check.style.top_margin = 4

  local stack_check = inner.add{
    type = "checkbox",
    name = "full-stack-only-checkbox",
    caption = {"full-stack-only-label"},
    tooltip = {"full-stack-only-tooltip"},
    state = false
  }
  stack_check.style.top_margin = 4

  local transfer_flow = inner.add{type = "flow", name = "transfer-flow", direction = "horizontal"}
  transfer_flow.style.horizontally_stretchable = true
  transfer_flow.style.vertical_align = "center"
  transfer_flow.style.top_margin = 4
  transfer_flow.add{type = "label", name = "transfer-label", caption = {"transfer-to-depot-label"}, tooltip = {"transfer-to-depot-tooltip"}}
  transfer_flow.add{type = "empty-widget"}.style.horizontally_stretchable = true
  local transfer_all_btn = transfer_flow.add{type = "button", name = "transfer-all-to-depot", caption = {"transfer-all-to-depot"}, tooltip = {"transfer-all-to-depot-tooltip"}, style = "mini_button"}
  transfer_all_btn.style.minimal_width = 36
  transfer_all_btn.style.minimal_height = 24
  local transfer_stack_btn = transfer_flow.add{type = "button", name = "transfer-stack-to-depot", caption = {"transfer-stack-to-depot"}, tooltip = {"transfer-stack-to-depot-tooltip"}, style = "mini_button"}
  transfer_stack_btn.style.minimal_width = 36
  transfer_stack_btn.style.minimal_height = 24
  transfer_stack_btn.style.left_margin = 4
  transfer_flow.visible = false

  inner["storage-limit-line"].visible = false
  limit_flow.visible = false
  cap_check.visible = false
  stack_check.visible = false

  -- Channel section (all depots)
  inner.add{type = "line", name = "channel-line", direction = "horizontal"}.style.top_margin = 4

  local ch_flow = inner.add{type = "flow", name = "channel-flow", direction = "horizontal"}
  ch_flow.style.vertical_align = "center"
  ch_flow.style.horizontally_stretchable = true
  ch_flow.add{type = "label", name = "channel-label", caption = {"channel-label"}, tooltip = {"channel-tooltip"}}
  ch_flow.add{type = "empty-widget"}.style.horizontally_stretchable = true
  local ch_field = ch_flow.add{
    type = "textfield",
    name = "channel-field",
    tooltip = {"channel-tooltip"},
    text = "-1"
  }
  ch_field.style.width = 70
  ch_field.style.horizontal_align = "center"
  local ch_sig_flow = inner.add{type = "flow", name = "channel-signal-flow", direction = "horizontal"}
  ch_sig_flow.style.vertical_align = "center"
  ch_sig_flow.style.horizontally_stretchable = true
  local ch_sig_hint = ch_sig_flow.add{type = "label", caption = {"priority-circuit-hint"}, tooltip = {"channel-signal-tooltip"}}
  ch_sig_hint.style.font_color = {0.8, 0.8, 0.8}
  ch_sig_flow.add{type = "empty-widget"}.style.horizontally_stretchable = true
  local ch_sig_value = ch_sig_flow.add{type = "label", name = "channel-signal-value", caption = ""}
  ch_sig_value.visible = false
  ch_sig_value.style.font_color = {1, 0.7, 0}
  ch_sig_flow.add{
    type = "choose-elem-button",
    name = "channel-signal-icon",
    elem_type = "signal",
    signal = {type = "virtual", name = "signal-C"},
    tooltip = {"channel-signal-tooltip"}
  }

  -- Supply threshold section (supplier depots only, hidden by default)
  inner.add{type = "line", name = "supply-threshold-line", direction = "horizontal"}.style.top_margin = 4

  local th_flow = inner.add{type = "flow", name = "supply-threshold-flow", direction = "horizontal"}
  th_flow.style.vertical_align = "center"
  th_flow.style.horizontally_stretchable = true
  th_flow.add{type = "label", name = "supply-threshold-label", caption = {"supply-threshold-label"}, tooltip = {"supply-threshold-tooltip"}}
  th_flow.add{type = "empty-widget"}.style.horizontally_stretchable = true
  local th_field = th_flow.add{
    type = "textfield",
    name = "supply-threshold-field",
    tooltip = {"supply-threshold-tooltip"},
    text = ""
  }
  th_field.style.width = 70
  th_field.style.horizontal_align = "center"

  local th_sig_flow = inner.add{type = "flow", name = "threshold-signal-flow", direction = "horizontal"}
  th_sig_flow.style.vertical_align = "center"
  th_sig_flow.style.horizontally_stretchable = true
  local th_sig_hint = th_sig_flow.add{type = "label", caption = {"priority-circuit-hint"}, tooltip = {"supply-threshold-signal-tooltip"}}
  th_sig_hint.style.font_color = {0.8, 0.8, 0.8}
  th_sig_flow.add{type = "empty-widget"}.style.horizontally_stretchable = true
  local th_sig_value = th_sig_flow.add{type = "label", name = "threshold-signal-value", caption = ""}
  th_sig_value.visible = false
  th_sig_value.style.font_color = {1, 0.7, 0}
  th_sig_flow.add{
    type = "choose-elem-button",
    name = "threshold-signal-icon",
    elem_type = "signal",
    signal = {type = "virtual", name = "signal-T"},
    tooltip = {"supply-threshold-signal-tooltip"}
  }

  inner["supply-threshold-line"].visible = false
  th_flow.visible = false
  th_sig_flow.visible = false

  -- Fuel bar section (active depot fluid mode, hidden by default)
  inner.add{type = "line", name = "fuel-bar-line", direction = "horizontal"}.style.top_margin = 4
  local fuel_flow = inner.add{type = "flow", name = "fuel-bar-flow", direction = "vertical"}
  fuel_flow.style.horizontally_stretchable = true
  fuel_flow.style.vertical_spacing = 0
  local fuel_header = fuel_flow.add{type = "flow", name = "fuel-bar-header", direction = "horizontal"}
  fuel_header.style.vertical_align = "center"
  fuel_header.style.horizontally_stretchable = true
  fuel_header.add{type = "label", name = "fuel-bar-label", caption = {"fuel-bar-label"}}
  fuel_header.add{type = "empty-widget"}.style.horizontally_stretchable = true
  fuel_header.add{type = "label", name = "fuel-bar-value", caption = "0 / 0"}
  local fuel_bar = fuel_flow.add{type = "progressbar", name = "fuel-bar", value = 0}
  fuel_bar.style.horizontally_stretchable = true
  fuel_bar.style.height = 8
  fuel_bar.style.top_margin = 2
  fuel_bar.style.color = {0.5, 0.5, 0.5}
  inner["fuel-bar-line"].visible = false
  fuel_flow.visible = false

  -- Logistics section (supply chest + buffer only, hidden by default)
  inner.add{type = "line", name = "bots-line", direction = "horizontal"}.style.top_margin = 4
  local bot_check = inner.add{
    type = "checkbox",
    name = "allow-bots-checkbox",
    caption = {"allow-bots-label"},
    tooltip = {"allow-bots-tooltip"},
    state = false
  }
  bot_check.style.top_margin = 4

  inner["bots-line"].visible = false
  bot_check.visible = false

  -- Central dispatch opt-in section (request, buffer, supply, active, storage - hidden by default)
  inner.add{type = "line", name = "allow-central-dispatch-line", direction = "horizontal"}.style.top_margin = 4
  local acd_check = inner.add{
    type = "checkbox",
    name = "allow-central-dispatch-checkbox",
    caption = {"allow-central-dispatch-label"},
    tooltip = {"allow-central-dispatch-tooltip"},
    state = true
  }
  acd_check.style.top_margin = 4

  inner["allow-central-dispatch-line"].visible = false
  acd_check.visible = false

  -- Fluid mode section (active/storage depot, hidden by default)
  inner.add{type = "line", name = "fluid-mode-line", direction = "horizontal"}.style.top_margin = 4
  local fluid_check = inner.add{
    type = "checkbox",
    name = "fluid-mode-checkbox",
    caption = {"fluid-mode-label"},
    tooltip = {"fluid-mode-tooltip"},
    state = false
  }
  fluid_check.style.top_margin = 4

  inner["fluid-mode-line"].visible = false
  fluid_check.visible = false

  -- Multi-pipe section (fluid-capable depots only, hidden by default)
  inner.add{type = "line", name = "multi-pipe-line", direction = "horizontal"}.style.top_margin = 4
  local mp_check = inner.add{
    type = "checkbox",
    name = "multi-pipe-checkbox",
    caption = {"multi-pipe-label"},
    tooltip = {"multi-pipe-tooltip"},
    state = false
  }
  mp_check.style.top_margin = 4

  inner["multi-pipe-line"].visible = false
  mp_check.visible = false

  -- Dispatcher description (hidden by default)
  inner.add{type = "line", name = "dispatcher-desc-line", direction = "horizontal"}.style.top_margin = 4
  local desc_label = inner.add{type = "label", name = "dispatcher-desc", caption = {"dispatcher-desc"}}
  desc_label.style.font_color = {0.6, 0.6, 0.6}
  desc_label.style.single_line = false
  desc_label.style.maximal_width = 220
  desc_label.style.top_margin = 2
  inner["dispatcher-desc-line"].visible = false
  desc_label.visible = false

  -- Central dispatch section (dispatcher only, hidden by default)
  inner.add{type = "line", name = "central-dispatch-line", direction = "horizontal"}.style.top_margin = 4
  local cd_check = inner.add{
    type = "checkbox",
    name = "central-dispatch-checkbox",
    caption = {"central-dispatch-label"},
    tooltip = {"central-dispatch-tooltip"},
    state = false
  }
  cd_check.style.top_margin = 4

  add_slider_with_input(inner, "central-dispatch", {
    label_key = "central-dispatch-slider-label", tooltip_key = "central-dispatch-slider-tooltip",
    default = 50, max = 100, step = 5, suffix = "%"
  })

  inner["central-dispatch-line"].visible = false
  cd_check.visible = false
  inner["central-dispatch-header"].visible = false
  inner["central-dispatch-slider"].visible = false

end

-- Panel creation

local function check_panel_version(player, name)
  local existing = player.gui.relative[name]
  if not existing then return false end
  if existing.tags and existing.tags.panel_version == PANEL_VERSION then return true end
  existing.destroy()
  return false
end

local function create_asm_panel(player)
  if check_panel_version(player, frame_asm) then return end
  local frame = player.gui.relative.add{
    type = "frame",
    name = frame_asm,
    direction = "vertical",
    caption = {"depot-panel-title"},
    tags = {panel_version = PANEL_VERSION},
    anchor = {
      gui = defines.relative_gui_type.assembling_machine_gui,
      position = defines.relative_gui_position.right,
      names = {"request-depot", "request-depot-multi", "buffer-depot", "buffer-depot-multi", "fuel-depot", "fuel-depot-multi", "supply-depot", "mining-depot", "active-depot", "storage-depot"}
    }
  }
  make_panel_content(frame)
end

local function create_asm_recipe_panel(player)
  if check_panel_version(player, frame_asm_recipe) then return end
  local frame = player.gui.relative.add{
    type = "frame",
    name = frame_asm_recipe,
    direction = "vertical",
    caption = {"depot-panel-title"},
    tags = {panel_version = PANEL_VERSION},
    anchor = {
      gui = defines.relative_gui_type.assembling_machine_select_recipe_gui,
      position = defines.relative_gui_position.right,
      names = {"request-depot", "request-depot-multi", "buffer-depot", "buffer-depot-multi", "fuel-depot", "fuel-depot-multi", "supply-depot", "mining-depot", "active-depot", "storage-depot"}
    }
  }
  make_panel_content(frame)
end

local function create_furnace_panel(player)
  if check_panel_version(player, frame_furnace) then return end
  local frame = player.gui.relative.add{
    type = "frame",
    name = frame_furnace,
    direction = "vertical",
    caption = {"depot-panel-title"},
    tags = {panel_version = PANEL_VERSION},
    anchor = {
      gui = defines.relative_gui_type.furnace_gui,
      position = defines.relative_gui_position.right,
      names = {"fluid-depot", "fluid-depot-multi", shared.active_depot_fluid_name, shared.active_depot_fluid_name .. "-multi", shared.storage_depot_fluid_name, shared.storage_depot_fluid_name .. "-multi"}
    }
  }
  make_panel_content(frame)
end

local function create_container_panel(player)
  if check_panel_version(player, frame_container) then return end
  local frame = player.gui.relative.add{
    type = "frame",
    name = frame_container,
    direction = "vertical",
    caption = {"depot-panel-title"},
    tags = {panel_version = PANEL_VERSION},
    anchor = {
      gui = defines.relative_gui_type.container_gui,
      position = defines.relative_gui_position.right,
      names = container_panel_names
    }
  }
  make_panel_content(frame)
end

local function destroy_panels(player)
  local rel = player.gui.relative
  -- Destroy current panels
  if rel[frame_asm] then rel[frame_asm].destroy() end
  if rel[frame_asm_recipe] then rel[frame_asm_recipe].destroy() end
  if rel[frame_furnace] then rel[frame_furnace].destroy() end
  if rel[frame_container] then rel[frame_container].destroy() end
  -- Clean up old frame names from previous versions
  for _, name in pairs(old_frame_names) do
    if rel[name] then rel[name].destroy() end
  end
end

local function recreate_panels(player)
  destroy_panels(player)
  create_asm_panel(player)
  create_asm_recipe_panel(player)
  create_furnace_panel(player)
  create_container_panel(player)
end

-- Panel update

local function update_fuel_bar_in_frame(inner, depot)
  local fuel_bar_flow = inner["fuel-bar-flow"]
  if not fuel_bar_flow or not fuel_bar_flow.visible then return end
  if not (depot.get_fuel_amount and depot.max_fuel_amount) then return end
  local current = math.floor(depot:get_fuel_amount())
  local max_fuel = math.floor(depot:max_fuel_amount())
  local header = fuel_bar_flow["fuel-bar-header"]
  if header then
    local value_label = header["fuel-bar-value"]
    if value_label then
      value_label.caption = util.format_number(current, true) .. " / " .. util.format_number(max_fuel, true)
    end
  end
  local bar = fuel_bar_flow["fuel-bar"]
  if bar then
    bar.value = max_fuel > 0 and math.min(1, current / max_fuel) or 0
    bar.tooltip = max_fuel > 0 and (math.floor(current / max_fuel * 100) .. "%") or "0%"
  end
end

local function update_panel_frame(frame, depot, entity_name, is_chest_view, player)
  local inner = frame["panel-inner"] or frame.children[1]
  if not inner then return end

  -- Normalize multi-pipe variant names to base for visibility checks
  local effective_name = shared.multi_pipe_base[entity_name] or entity_name

  local player = game.get_player(frame.player_index)

  -- Drone section
  local has_drones = drone_depot_names[entity_name] or is_chest_view or false
  local drone_flow = inner["drone-flow"]
  local drone_line = inner["drone-line"]
  -- Hide/show buttons at top of panel
  local open_btn = inner["drone-open-chest"]
  local back_btn = inner["drone-back-to-depot"]
  if not has_drones then
    if open_btn then open_btn.visible = false end
    if back_btn then back_btn.visible = false end
  end
  if drone_flow then
    drone_flow.visible = has_drones
    if has_drones then
      local label = drone_flow["drone-count-label"]
      if label then
        local in_stock = get_total_drone_count(depot)
        local active = depot:get_active_drone_count()
        label.caption = {"drone-in-stock-active", active, in_stock}
      end
      -- Drone request slider
      local max_req = get_max_drone_request(depot)
      local req_header = drone_flow["drone-request-header"]
      if req_header then
        local req_field = req_header["drone-request-field"]
        if req_field then
          req_field.text = tostring(depot.requested_drones or 0)
        end
        local req_max = req_header["drone-request-suffix"]
        if req_max then
          req_max.caption = "/ " .. tostring(max_req)
        end
      end
      local req_slider = drone_flow["drone-request-slider"]
      if req_slider then
        req_slider.set_slider_minimum_maximum(0, max_req)
        req_slider.slider_value = math.min(max_req, depot.requested_drones or 0)
      end
      -- Toggle between "Open chest" and "Back to depot" buttons
      if open_btn then open_btn.visible = not is_chest_view end
      if back_btn then back_btn.visible = is_chest_view or false end
    end
  end
  if drone_line then drone_line.visible = has_drones end

  -- Priority section
  local desc = inner["priority-desc"]
  if desc then
    local hint = priority_desc[entity_name]
    if hint then
      desc.caption = hint
      desc.visible = true
    else
      desc.visible = false
    end
  end

  local priority = depot.priority or depot.base_priority or shared.default_priority
  local base_priority = depot.base_priority or shared.default_priority
  local priority_header = inner["priority-header"]
  if priority_header then
    local priority_field = priority_header["priority-field"]
    if priority_field then
      priority_field.text = tostring(base_priority)
    end
  end
  local slider = inner["priority-slider"]
  if slider then
    slider.slider_value = math.max(0, math.min(100, base_priority))
  end

  local sig_flow = inner["priority-signal-flow"]
  if sig_flow then
    local chooser = sig_flow["priority-signal-chooser"]
    if chooser then
      chooser.elem_value = depot.priority_signal or default_priority_signal
    end
    local sig_value = sig_flow["priority-signal-value"]
    if sig_value then
      if priority ~= base_priority then
        sig_value.caption = util.format_number(priority, true)
        sig_value.visible = true
      else
        sig_value.visible = false
      end
    end
  end

  -- Requester section (request/buffer)
  local is_requester = (effective_name == "request-depot" or effective_name == "buffer-depot")
  local limit_line = inner["storage-limit-line"]
  local limit_flow = inner["storage-limit-flow"]
  local cap_check = inner["ignore-capacity-checkbox"]
  if limit_line then limit_line.visible = is_requester end
  if limit_flow then
    limit_flow.visible = is_requester
    if is_requester then
      local field = limit_flow["storage-limit-field"]
      if field then
        field.text = depot.storage_limit and tostring(depot.storage_limit) or ""
      end
      local override = limit_flow["storage-limit-override"]
      if depot.circuit_limit and depot.circuit_limit > 0 then
        local limit_tip = {"", {"storage-limit-override-tooltip"}, "\n", tostring(depot.circuit_limit)}
        if not override then
          override = limit_flow.add{type = "label", name = "storage-limit-override", caption = util.format_number(depot.circuit_limit, true), tooltip = limit_tip, index = 3}
          override.style.font_color = {1, 0.7, 0}
          override.style.right_margin = 4
        else
          override.caption = util.format_number(depot.circuit_limit, true)
          override.tooltip = limit_tip
        end
      elseif override then
        override.destroy()
      end
    end
  end
  local quality_flow = inner["quality-flow"]
  if quality_flow then
    local is_fluid = depot.mode and depot.mode ~= 1
    local show_quality = shared.quality_enabled and is_requester and depot.item and not is_fluid
    quality_flow.visible = show_quality or false
    if show_quality then
      local qd = quality_flow["quality-dropdown"]
      if qd then
        local qi = ({normal = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5})[depot.item_quality or "normal"] or 1
        qd.selected_index = qi
      end
    end
  end
  if cap_check then
    cap_check.visible = is_requester
    if is_requester then
      cap_check.state = depot.ignore_capacity_bonus or false
    end
  end
  local stack_check = inner["full-stack-only-checkbox"]
  if stack_check then
    stack_check.visible = is_requester
    if is_requester then
      stack_check.state = depot.full_stack_only or false
    end
  end
  local transfer_flow = inner["transfer-flow"]
  if transfer_flow then
    local show_transfer = false
    local is_fluid = depot.mode and depot.mode ~= 1
    if is_requester and depot.item and player and not is_fluid then
      local player_inv = player.get_main_inventory()
      if player_inv then
        local quality = depot.item_quality
        local filter = (quality and quality ~= "normal") and {name = depot.item, quality = quality} or depot.item
        show_transfer = player_inv.get_item_count(filter) > 0
      end
    end
    transfer_flow.visible = show_transfer
  end

  -- Channel section (all depots)
  local ch_flow = inner["channel-flow"]
  if ch_flow then
    local ch_field = ch_flow["channel-field"]
    if ch_field then
      ch_field.text = tostring(depot.base_channel or shared.default_channel)
    end
  end
  local ch_sig_flow = inner["channel-signal-flow"]
  if ch_sig_flow then
    local ch_sig_value = ch_sig_flow["channel-signal-value"]
    if ch_sig_value then
      local effective_ch = depot.channel or depot.base_channel or shared.default_channel
      local base_ch = depot.base_channel or shared.default_channel
      if effective_ch ~= base_ch then
        ch_sig_value.caption = util.format_number(effective_ch, true)
        ch_sig_value.visible = true
      else
        ch_sig_value.visible = false
      end
    end
  end

  -- Supply threshold section (suppliers, not active depot)
  local is_supplier = has_supply_threshold[effective_name] or has_supply_threshold[entity_name] or false
  local th_line = inner["supply-threshold-line"]
  local th_flow = inner["supply-threshold-flow"]
  local th_sig_flow = inner["threshold-signal-flow"]
  if th_line then th_line.visible = is_supplier end
  if th_flow then
    th_flow.visible = is_supplier
    if is_supplier then
      local field = th_flow["supply-threshold-field"]
      if field then
        field.text = depot.supply_threshold and tostring(depot.supply_threshold) or ""
      end
    end
  end
  if th_sig_flow then
    th_sig_flow.visible = is_supplier
    if is_supplier then
      local th_sig_value = th_sig_flow["threshold-signal-value"]
      if th_sig_value then
        if depot.circuit_threshold then
          th_sig_value.caption = util.format_number(depot.circuit_threshold, true)
          th_sig_value.visible = true
        else
          th_sig_value.visible = false
        end
      end
    end
  end

  -- Central dispatch opt-in section (request, buffer, supply, active)
  local show_acd = has_central_dispatch_toggle[effective_name] or has_central_dispatch_toggle[entity_name] or false
  local acd_line = inner["allow-central-dispatch-line"]
  local acd_check = inner["allow-central-dispatch-checkbox"]
  if acd_line then acd_line.visible = show_acd end
  if acd_check then
    acd_check.visible = show_acd
    if show_acd then
      acd_check.state = depot.allow_central_dispatch ~= false
    end
  end

  -- Storage filter section (storage depot only)
  local is_storage = (depot.set_storage_filter ~= nil)
  local sf_line = inner["storage-filter-line"]
  local sf_flow = inner["storage-filter-flow"]
  if sf_line then sf_line.visible = is_storage end
  if sf_flow then
    sf_flow.visible = is_storage
    if is_storage then
      local chooser = sf_flow["storage-filter-chooser"]
      if chooser then
        -- Switch elem_type based on fluid mode
        local target_type = depot.fluid_mode and "fluid" or "item"
        if chooser.elem_type ~= target_type then
          -- Must recreate the button to change elem_type
          local parent = chooser.parent
          chooser.destroy()
          parent.add{
            type = "choose-elem-button",
            name = "storage-filter-chooser",
            elem_type = target_type,
            tooltip = {"storage-filter-tooltip"}
          }
          chooser = parent["storage-filter-chooser"]
        end
        chooser.elem_value = depot.storage_filter_item
      end
      -- Reset blink color (relative GUI is reused across depots)
      local label = sf_flow["storage-filter-label"]
      if label then label.style.font_color = {1, 1, 1} end
    end
  end

  -- Fuel bar section (active depot)
  local show_fuel_bar = (depot.get_fuel_amount ~= nil and depot.max_fuel_amount ~= nil) or false
  local fuel_bar_line = inner["fuel-bar-line"]
  local fuel_bar_flow = inner["fuel-bar-flow"]
  if fuel_bar_line then fuel_bar_line.visible = show_fuel_bar or false end
  if fuel_bar_flow then
    fuel_bar_flow.visible = show_fuel_bar or false
    if show_fuel_bar then
      update_fuel_bar_in_frame(inner, depot)
    end
  end

  -- Logistics section (supply chest + buffer + storage - hidden in fluid mode)
  local buffer_fluid = depot.is_buffer_depot and depot.mode and depot.mode ~= 1
  local has_bots = (depot.set_allow_bots ~= nil) and not (depot.fluid_mode) and not buffer_fluid
  local bots_line = inner["bots-line"]
  local bot_check = inner["allow-bots-checkbox"]
  if bots_line then bots_line.visible = has_bots end
  if bot_check then
    bot_check.visible = has_bots
    if has_bots then
      bot_check.state = depot.allow_bots or false
      local unlocked = has_logistics_tech(player)
      if not unlocked then
        bot_check.enabled = false
        bot_check.tooltip = {"allow-bots-tooltip-locked"}
      else
        bot_check.enabled = true
        bot_check.tooltip = {"allow-bots-tooltip"}
      end
    end
  end

  -- Fluid mode section (active/storage depot)
  local has_fluid_mode = (depot.set_fluid_mode ~= nil)
  local fluid_line = inner["fluid-mode-line"]
  local fluid_check = inner["fluid-mode-checkbox"]
  if fluid_line then fluid_line.visible = has_fluid_mode end
  if fluid_check then
    fluid_check.visible = has_fluid_mode
    if has_fluid_mode then
      fluid_check.state = depot.fluid_mode or false
    end
  end

  -- Multi-pipe section (fluid-capable depots with variant prototypes)
  -- For depots with fluid mode toggle, show but grey out when not in fluid mode
  local buffer_item = depot.is_buffer_depot and (not depot.mode or depot.mode == 1)
  local supports_multi = shared.multi_pipe_variants[effective_name] ~= nil
  local show_multi = supports_multi and not buffer_item
  local mp_line = inner["multi-pipe-line"]
  local mp_check = inner["multi-pipe-checkbox"]
  if mp_line then mp_line.visible = show_multi end
  if mp_check then
    mp_check.visible = show_multi
    if show_multi then
      mp_check.state = shared.multi_pipe_base[entity_name] ~= nil
      local mp_unlocked = has_multi_pipe_tech(player)
      if not mp_unlocked then
        mp_check.enabled = false
        mp_check.tooltip = {"multi-pipe-tooltip-locked"}
      elseif has_fluid_mode and not depot.fluid_mode then
        mp_check.enabled = false
        mp_check.tooltip = {"multi-pipe-tooltip-fluid"}
      else
        mp_check.enabled = true
        mp_check.tooltip = {"multi-pipe-tooltip"}
      end
    end
  end

  -- Dispatcher description
  local is_dispatcher = dispatcher_chest_names[entity_name] or false
  local desc_line = inner["dispatcher-desc-line"]
  local desc_label = inner["dispatcher-desc"]
  if desc_line then desc_line.visible = is_dispatcher end
  if desc_label then desc_label.visible = is_dispatcher end

  -- Central dispatch section (dispatcher only)
  local cd_line = inner["central-dispatch-line"]
  local cd_check = inner["central-dispatch-checkbox"]
  local cd_header = inner["central-dispatch-header"]
  local cd_slider = inner["central-dispatch-slider"]
  if cd_line then cd_line.visible = is_dispatcher end
  if cd_check then
    cd_check.visible = is_dispatcher
    if is_dispatcher then
      cd_check.state = depot.central_dispatch_enabled or false
    end
  end
  local cd_enabled = is_dispatcher and (depot.central_dispatch_enabled or false)
  if cd_header then
    cd_header.visible = cd_enabled
    if cd_enabled then
      local cd_field = cd_header["central-dispatch-field"]
      if cd_field then
        cd_field.text = tostring(depot.central_dispatch_percent or 50)
      end
    end
  end
  if cd_slider then
    cd_slider.visible = cd_enabled
    if cd_enabled then
      cd_slider.slider_value = depot.central_dispatch_percent or 50
    end
  end

end

local function update_panel(player, panel_frame_name, depot, entity_name)
  local frame = player.gui.relative[panel_frame_name]
  if not frame then return end
  update_panel_frame(frame, depot, entity_name, false, player)
end

-- Standalone screen panel (when writer controls recipe and no recipe is set)

local standalone_frame_name = "depot-panel-standalone"

local function destroy_standalone_panel(player)
  local frame = player.gui.screen[standalone_frame_name]
  if frame then frame.destroy() end
end

local function create_standalone_depot_panel(player, depot, entity)
  destroy_standalone_panel(player)

  local frame = player.gui.screen.add{type = "frame", name = standalone_frame_name, direction = "vertical"}
  frame.auto_center = true

  -- Title bar
  local title_flow = frame.add{type = "flow", name = "title_flow"}
  title_flow.add{type = "label", caption = {"depot-panel-title"}, style = "frame_title"}
  local pusher = title_flow.add{type = "empty-widget", style = "draggable_space_header"}
  pusher.style.vertically_stretchable = true
  pusher.style.horizontally_stretchable = true
  pusher.drag_target = frame
  title_flow.add{
    type = "sprite-button",
    name = "standalone-depot-close",
    sprite = "utility/close",
    style = "close_button"
  }

  make_panel_content(frame)
  update_panel_frame(frame, depot, entity.name, false, player)

  player.opened = frame
end

local function is_writer_controlled_recipe(depot)
  if not (depot.circuit_writer and depot.circuit_writer.valid) then return false end
  local config = storage.writer_config and storage.writer_config[depot.circuit_writer.unit_number]
  return config and config.set_recipe or false
end

-- Drone chest back-panel (gui.left)

local function destroy_chest_panel(player)
  local frame = player.gui.relative[chest_frame_name]
  if frame then frame.destroy() end
  -- Clean up old gui.left panel from previous versions
  local old = player.gui.left[chest_frame_name]
  if old then old.destroy() end
end

local function create_chest_panel(player, depot)
  destroy_chest_panel(player)
  local chest_names = {}
  for _, name in pairs(shared.drone_chest_name) do
    table.insert(chest_names, name)
  end
  local frame = player.gui.relative.add{
    type = "frame",
    name = chest_frame_name,
    direction = "vertical",
    caption = {"depot-panel-title"},
    anchor = {
      gui = defines.relative_gui_type.container_gui,
      position = defines.relative_gui_position.right,
      names = chest_names
    }
  }
  make_panel_content(frame)
  -- Find the depot entity name for proper section visibility
  local entity_name = depot.entity and depot.entity.valid and depot.entity.name or "request-depot"
  update_panel_frame(frame, depot, entity_name, true, player)
end

-- Event handlers

local function on_gui_opened(event)
  if not event.entity then return end
  local player = game.get_player(event.player_index)
  if not player then return end

  local entity = event.entity
  local is_depot = depot_names[entity.name]
  local is_chest = supply_chest_names[entity.name] or active_chest_names[entity.name] or storage_chest_names[entity.name] or dispatcher_chest_names[entity.name]
  local is_drone_chest = drone_chest_names[entity.name]

  -- Drone chest: show back-to-depot panel
  if is_drone_chest then
    local depot = get_depot_for_entity(entity)
    if depot then
      player_open_depot[event.player_index] = depot
      create_chest_panel(player, depot)
    end
    return
  end

  if not is_depot and not is_chest then return end

  local depot = get_depot_for_entity(entity)
  if not depot then return end

  -- Active depot in fluid mode: redirect chest click to main entity
  if is_chest and active_chest_names[entity.name] and depot.fluid_mode and depot.entity and depot.entity.valid then
    player.opened = depot.entity
    return
  end

  player_open_depot[event.player_index] = depot

  -- Force circuit updates so values are fresh on first open after load
  if depot.update_priority_from_circuit then depot:update_priority_from_circuit() end
  if depot.update_channel_from_circuit then depot:update_channel_from_circuit() end
  if depot.update_threshold_from_circuit then depot:update_threshold_from_circuit() end

  local effective_entity_name = shared.multi_pipe_base[entity.name] or entity.name
  if is_chest then
    create_container_panel(player)
    update_panel(player, frame_container, depot, entity.name)
  elseif effective_entity_name == "fluid-depot" or effective_entity_name == shared.active_depot_fluid_name or effective_entity_name == shared.storage_depot_fluid_name then
    create_furnace_panel(player)
    update_panel(player, frame_furnace, depot, entity.name)
  else
    -- Writer controls recipe and no recipe set: show standalone panel instead of recipe picker
    if is_writer_controlled_recipe(depot) and not entity.get_recipe() then
      player.opened = nil
      create_standalone_depot_panel(player, depot, entity)
      return
    end
    create_asm_panel(player)
    create_asm_recipe_panel(player)
    update_panel(player, frame_asm, depot, entity.name)
    update_panel(player, frame_asm_recipe, depot, entity.name)
  end
end

local function on_gui_closed(event)
  -- Standalone screen panel closed (ESC or close button)
  if event.element and event.element.valid and event.element.name == standalone_frame_name then
    event.element.destroy()
    player_open_depot[event.player_index] = nil
    return
  end

  -- Fluid mode confirmation dialog closed (ESC)
  if event.element and event.element.valid and event.element.name == "fluid-mode-confirm" then
    event.element.destroy()
    return
  end

  if not event.entity then return end
  local name = event.entity.name

  if drone_chest_names[name] then
    local player = game.get_player(event.player_index)
    if player then destroy_chest_panel(player) end
    player_open_depot[event.player_index] = nil
    return
  end

  if depot_names[name] or supply_chest_names[name] or active_chest_names[name] or storage_chest_names[name] or dispatcher_chest_names[name] then
    local depot = player_open_depot[event.player_index]
    if depot and depot.eject_wrong_quality then
      local player = game.get_player(event.player_index)
      depot:eject_wrong_quality(player)
    end
    player_open_depot[event.player_index] = nil
  end
end

local function on_slider_changed(event)
  local element = event.element
  if not element or not element.valid then return end
  local config = slider_configs[element.name]
  if not config then return end
  local depot = player_open_depot[event.player_index]
  if not depot then return end
  local value = math.floor(element.slider_value)
  config.set(depot, value)
  local header = element.parent and element.parent[config.header]
  if header then
    local field = header[config.field]
    if field then field.text = tostring(value) end
  end
end

local function on_elem_changed(event)
  local element = event.element
  if not element or not element.valid then return end

  if element.name == "priority-signal-chooser" then
    local depot = player_open_depot[event.player_index]
    if not depot then return end

    local signal = element.elem_value
    if signal then
      depot.priority_signal = signal
    else
      depot.priority_signal = nil
      element.elem_value = default_priority_signal
    end
  elseif element.name == "storage-filter-chooser" then
    local depot = player_open_depot[event.player_index]
    if not depot or not depot.set_storage_filter then return end
    depot:set_storage_filter(element.elem_value)
    depot._filter_blink = nil
    local label = element.parent and element.parent["storage-filter-label"]
    if label then label.style.font_color = {1, 1, 1} end
  elseif element.name == "threshold-signal-icon" then
    -- Fixed signal, reset if user tries to change it
    element.elem_value = {type = "virtual", name = "signal-T"}
  elseif element.name == "channel-signal-icon" then
    -- Fixed signal, reset if user tries to change it
    element.elem_value = {type = "virtual", name = "signal-C"}
  end
end

local function on_text_changed(event)
  local element = event.element
  if not element or not element.valid then return end

  local depot = player_open_depot[event.player_index]
  if not depot then return end

  if element.name == "storage-limit-field" then
    local text = element.text
    if text == "" then
      depot.storage_limit = nil
    else
      local value = util.parse_math_input(text)
      if value and value > 0 then
        depot.storage_limit = math.floor(value)
      end
    end
  elseif element.name == "channel-field" then
    local text = element.text
    if text == "" or text == "-" then
      return
    end
    local value = util.parse_math_input(text)
    if value then
      depot.base_channel = math.floor(value)
      depot.channel = depot.base_channel
    end
  elseif element.name == "supply-threshold-field" then
    local text = element.text
    if text == "" then
      depot.supply_threshold = nil
    else
      local value = util.parse_math_input(text)
      if value and value > 0 then
        depot.supply_threshold = math.floor(value)
      end
    end
  else
    local pair = field_to_slider[element.name]
    if pair then
      local text = element.text
      if text == "" then return end
      local value = tonumber(text)
      if not value then return end
      local config = pair.config
      local max = type(config.max) == "function" and config.max(depot) or config.max
      value = math.max(config.min, math.min(max, math.floor(value)))
      config.set(depot, value)
      local slider = element.parent and element.parent.parent and element.parent.parent[pair.slider]
      if slider then slider.slider_value = value end
    end
  end
end

local function on_checkbox_changed(event)
  local element = event.element
  if not element or not element.valid then return end

  local depot = player_open_depot[event.player_index]
  if not depot then return end

  if element.name == "ignore-capacity-checkbox" then
    depot.ignore_capacity_bonus = element.state or nil
  elseif element.name == "full-stack-only-checkbox" then
    depot.full_stack_only = element.state or nil
  elseif element.name == "allow-bots-checkbox" then
    local player = game.get_player(event.player_index)
    if not player then return end

    if not has_logistics_tech(player) then
      element.state = false
      return
    end

    if depot.is_buffer_depot and depot.mode and depot.mode ~= 1 then
      element.state = false
      return
    end

    if not depot.set_allow_bots then return end
    depot:set_allow_bots(element.state)

    -- Re-open the new entity so the GUI stays visible after the swap
    if depot.entity and depot.entity.valid then
      player.opened = depot.entity
    end
  elseif element.name == "multi-pipe-checkbox" then
    local player = game.get_player(event.player_index)
    if not player then return end
    if not depot.set_multi_pipe then return end
    depot:set_multi_pipe(element.state)
    -- Re-open the new entity so the GUI stays visible after the swap
    if depot.entity and depot.entity.valid then
      player.opened = depot.entity
    end
  elseif element.name == "central-dispatch-checkbox" then
    depot.central_dispatch_enabled = element.state or nil
    -- Toggle slider visibility
    local inner = element.parent
    if inner then
      local cd_header = inner["central-dispatch-header"]
      local cd_slider = inner["central-dispatch-slider"]
      if cd_header then
        cd_header.visible = element.state
        if element.state then
          local cd_field = cd_header["central-dispatch-field"]
          if cd_field then cd_field.text = tostring(depot.central_dispatch_percent or 50) end
        end
      end
      if cd_slider then
        cd_slider.visible = element.state
        if element.state then
          cd_slider.slider_value = depot.central_dispatch_percent or 50
        end
      end
    end
  elseif element.name == "allow-central-dispatch-checkbox" then
    depot.allow_central_dispatch = element.state
  elseif element.name == "fluid-mode-checkbox" then
    local player = game.get_player(event.player_index)
    if not player then return end
    if not depot.set_fluid_mode then return end

    local has_contents = false
    if element.state then
      -- Switching to fluid mode: check if items in chest
      local inv = depot.get_item_inventory and depot:get_item_inventory()
        or (depot.entity and depot.entity.valid and depot.entity.get_output_inventory and depot.entity.get_output_inventory())
      if inv then
        for _, item in pairs(inv.get_contents()) do
          if item.count > 0 then has_contents = true break end
        end
      end
    else
      -- Switching to item mode: check if fluid in any fluidbox
      for i = 1, 2 do
        local fb = depot.entity.fluidbox[i]
        if fb and fb.amount > 0 then has_contents = true break end
      end
    end

    if has_contents then
      -- Revert checkbox and show confirmation dialog
      element.state = not element.state
      local frame = player.gui.screen["fluid-mode-confirm"]
      if frame then frame.destroy() end
      frame = player.gui.screen.add{type = "frame", name = "fluid-mode-confirm", direction = "vertical"}
      frame.auto_center = true
      local title_flow = frame.add{type = "flow"}
      title_flow.add{type = "label", caption = {"fluid-mode-confirm-title"}, style = "frame_title"}
      local pusher = title_flow.add{type = "empty-widget", style = "draggable_space_header"}
      pusher.style.horizontally_stretchable = true
      pusher.drag_target = frame
      frame.add{type = "label", caption = {"fluid-mode-confirm-message"}}
      local button_flow = frame.add{type = "flow", direction = "horizontal"}
      button_flow.style.top_margin = 8
      button_flow.add{type = "empty-widget"}.style.horizontally_stretchable = true
      button_flow.add{type = "button", name = "fluid-mode-confirm-yes", caption = {"fluid-mode-confirm-yes"}, style = "confirm_button"}
      button_flow.add{type = "button", name = "fluid-mode-confirm-no", caption = {"fluid-mode-confirm-no"}}
      -- Store the target state and depot index (player.opened clears player_open_depot)
      frame.tags = {target_fluid_mode = not element.state, depot_index = depot.index}
      player.opened = frame
    else
      depot:set_fluid_mode(element.state)
      -- Re-open the correct entity after mode swap (item chest in item mode, entity in fluid mode)
      if not element.state and depot.item_chest and depot.item_chest.valid then
        player.opened = depot.item_chest
      elseif depot.entity and depot.entity.valid then
        player.opened = depot.entity
      end
    end
  end
end

local function on_confirmed(event)
  local element = event.element
  if not element or not element.valid then return end
  local depot = player_open_depot[event.player_index]
  if not depot then return end
  local pair = field_to_slider[element.name]
  if pair then
    element.text = tostring(pair.config.get(depot))
  elseif element.name == "storage-limit-field" then
    local value = depot.storage_limit
    element.text = value and tostring(value) or ""
  elseif element.name == "supply-threshold-field" then
    local value = depot.supply_threshold
    element.text = value and tostring(value) or ""
  elseif element.name == "channel-field" then
    element.text = tostring(depot.base_channel or shared.default_channel)
  end
end

local function on_gui_click(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  if not event.element or not event.element.valid then return end

  if event.element.name == "standalone-depot-close" then
    player.opened = nil
    return
  end

  if event.element.name == "drone-open-chest" then
    local depot = player_open_depot[event.player_index]
    if depot and depot.drone_chest and depot.drone_chest.valid then
      player.opened = depot.drone_chest
    end
    return
  end

  if event.element.name == "drone-back-to-depot" then
    local depot = player_open_depot[event.player_index]
    if depot then
      local target = (depot.item_chest and depot.item_chest.valid) and depot.item_chest or depot.entity
      if target and target.valid then
        player.opened = target
      end
    end
    return
  end

  if event.element.name == "transfer-all-to-depot" or event.element.name == "transfer-stack-to-depot" then
    local depot = player_open_depot[event.player_index]
    if not (depot and depot.item and depot.entity and depot.entity.valid) then return end
    local player_inv = player.get_main_inventory()
    if not player_inv then return end
    local item = depot.item
    local quality = depot.item_quality
    local item_filter = (quality and quality ~= "normal") and {name = item, quality = quality} or item
    local available = player_inv.get_item_count(item_filter)
    if available <= 0 then return end
    local count = available
    if event.element.name == "transfer-stack-to-depot" then
      local stack_size = prototypes.item[item] and prototypes.item[item].stack_size or 1
      count = math.min(stack_size, available)
    end
    local output_inv = depot.entity.get_output_inventory()
    if not output_inv then return end
    -- Preserve spoil percent from first matching stack
    local stack = player_inv.find_item_stack(item)
    local spoil_percent = stack and stack.spoil_percent or 0
    local remove_filter = {name = item, count = count}
    if quality and quality ~= "normal" then remove_filter.quality = quality end
    local removed = player_inv.remove(remove_filter)
    if removed > 0 then
      local insert_stack = {name = item, count = removed}
      if quality and quality ~= "normal" then insert_stack.quality = quality end
      if spoil_percent > 0 then insert_stack.spoil_percent = spoil_percent end
      output_inv.insert(insert_stack)
    end
    return
  end

  if event.element.name == "fluid-mode-confirm-yes" then
    local frame = player.gui.screen["fluid-mode-confirm"]
    if not frame then return end
    local tags = frame.tags or {}
    local target_fluid_mode = tags.target_fluid_mode
    local depot_index = tags.depot_index
    frame.destroy()
    local depot = depot_index and storage.transport_depots and storage.transport_depots.depots[depot_index]
    if not depot or not depot.set_fluid_mode then return end
    -- Wipe old mode contents
    if target_fluid_mode then
      -- Switching to fluid: clear item inventory
      local inv = depot.get_item_inventory and depot:get_item_inventory()
        or (depot.entity and depot.entity.valid and depot.entity.get_output_inventory and depot.entity.get_output_inventory())
      if inv then inv.clear() end
    else
      -- Switching to item: clear all fluid
      depot.entity.clear_fluid_inside()
    end
    depot:set_fluid_mode(target_fluid_mode)
    -- Re-open the correct entity after mode swap (item chest in item mode, entity in fluid mode)
    if not target_fluid_mode and depot.item_chest and depot.item_chest.valid then
      player.opened = depot.item_chest
    elseif depot.entity and depot.entity.valid then
      player.opened = depot.entity
    end
    return
  end

  if event.element.name == "fluid-mode-confirm-no" then
    local frame = player.gui.screen["fluid-mode-confirm"]
    local depot_index = frame and frame.tags and frame.tags.depot_index
    if frame then frame.destroy() end
    -- Re-open the depot (item chest in item mode, entity in fluid mode)
    local depot = depot_index and storage.transport_depots and storage.transport_depots.depots[depot_index]
    if depot then
      if not depot.fluid_mode and depot.item_chest and depot.item_chest.valid then
        player.opened = depot.item_chest
      elseif depot.entity and depot.entity.valid then
        player.opened = depot.entity
      end
    end
    return
  end

end

local function on_player_created(event)
  local player = game.get_player(event.player_index)
  if player then
    create_asm_panel(player)
    create_asm_recipe_panel(player)
    create_furnace_panel(player)
    create_container_panel(player)
  end
end

local function update_buffer_toggles_in_frame(inner, depot)
  if not depot.is_buffer_depot then return end
  local is_fluid = depot.mode and depot.mode ~= 1
  -- Multi-pipe: hide in item mode
  local mp_line = inner["multi-pipe-line"]
  local mp_check = inner["multi-pipe-checkbox"]
  if mp_line then mp_line.visible = is_fluid or false end
  if mp_check then mp_check.visible = is_fluid or false end
  -- Bot toggle: hide in fluid mode
  local bots_line = inner["bots-line"]
  local bot_check = inner["allow-bots-checkbox"]
  if bots_line then bots_line.visible = not is_fluid end
  if bot_check then bot_check.visible = not is_fluid end
end

-- Update drone count label, fuel bar, and transfer buttons in a panel inner frame
local function refresh_panel_inner(inner, depot, player)
  if not inner then return end
  local drone_flow = inner["drone-flow"]
  if drone_flow and drone_flow.visible then
    local label = drone_flow["drone-count-label"]
    if label then
      local in_stock = get_total_drone_count(depot)
      local active = depot:get_active_drone_count()
      label.caption = {"drone-in-stock-active", active, in_stock}
    end
  end
  update_fuel_bar_in_frame(inner, depot)
  update_buffer_toggles_in_frame(inner, depot)
  -- Update quality dropdown visibility
  local quality_flow = inner["quality-flow"]
  if quality_flow then
    local is_fluid = depot.mode and depot.mode ~= 1
    local show_quality = shared.quality_enabled and depot.set_item_quality and depot.item and not is_fluid
    quality_flow.visible = show_quality or false
    if show_quality then
      local qd = quality_flow["quality-dropdown"]
      if qd then
        local qi = ({normal = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5})[depot.item_quality or "normal"] or 1
        if qd.selected_index ~= qi then qd.selected_index = qi end
      end
    end
  end
  -- Toggle transfer buttons based on player inventory
  local transfer_flow = inner["transfer-flow"]
  if transfer_flow and player then
    local show = false
    local is_fluid = depot.mode and depot.mode ~= 1
    if depot.item and not is_fluid then
      local player_inv = player.get_main_inventory()
      if player_inv then
        local quality = depot.item_quality
        local filter = (quality and quality ~= "normal") and {name = depot.item, quality = quality} or depot.item
        show = player_inv.get_item_count(filter) > 0
      end
    end
    transfer_flow.visible = show
  end
end

-- Periodic panel refresh (drone counts etc.)
local function on_tick(event)
  if event.tick % 30 ~= 0 then return end
  if not next(player_open_depot) then return end

  for player_index, depot in pairs(player_open_depot) do
    if not (depot.entity and depot.entity.valid) then
      player_open_depot[player_index] = nil
    elseif depot.get_drone_item_count then
      depot._drone_count_cache = nil
      local player = game.get_player(player_index)
      if player then
        for _, panel_name in pairs({frame_container, frame_asm, frame_asm_recipe, frame_furnace}) do
          local frame = player.gui.relative[panel_name]
          if frame and frame.visible ~= false then
            refresh_panel_inner(frame["panel-inner"], depot, player)
          end
        end
        local standalone = player.gui.screen[standalone_frame_name]
        if standalone then
          refresh_panel_inner(standalone["panel-inner"], depot, player)
        end
        local chest_panel = player.gui.relative[chest_frame_name]
        if chest_panel then
          refresh_panel_inner(chest_panel["panel-inner"] or chest_panel.children[1], depot, player)
        end
      end
    end
  end
end

-- Copy-paste handler: sync depot settings
local function on_settings_pasted(event)
  local source = event.source
  local dest = event.destination
  if not (source and source.valid and dest and dest.valid) then return end

  local src_depot = get_depot_for_entity(source)
  local dst_depot = get_depot_for_entity(dest)
  if not (src_depot and dst_depot) then return end

  if src_depot.set_storage_filter and dst_depot.set_storage_filter then
    dst_depot:set_storage_filter(src_depot.storage_filter_item)
    dst_depot.saved_bar = src_depot.saved_bar
  end
  if src_depot.allow_bots ~= nil and dst_depot.set_allow_bots then
    if src_depot.allow_bots ~= (dst_depot.allow_bots or false) then
      dst_depot:set_allow_bots(src_depot.allow_bots or false)
    end
  end
  if shared.quality_enabled and src_depot.item_quality and dst_depot.set_item_quality then
    dst_depot:set_item_quality(src_depot.item_quality)
  end
end

local quality_index_to_name = {"normal", "uncommon", "rare", "epic", "legendary"}

local function on_selection_changed(event)
  local element = event.element
  if not element or not element.valid then return end
  if element.name ~= "quality-dropdown" then return end
  if not shared.quality_enabled then return end
  local depot = player_open_depot[event.player_index]
  if not depot or not depot.set_item_quality then return end
  local quality = quality_index_to_name[element.selected_index] or "normal"
  depot:set_item_quality(quality)
end

-- Module exports

local lib = {}

lib.events = {
  [defines.events.on_gui_opened] = on_gui_opened,
  [defines.events.on_gui_closed] = on_gui_closed,
  [defines.events.on_gui_value_changed] = on_slider_changed,
  [defines.events.on_gui_elem_changed] = on_elem_changed,
  [defines.events.on_gui_text_changed] = on_text_changed,
  [defines.events.on_gui_confirmed] = on_confirmed,
  [defines.events.on_gui_checked_state_changed] = on_checkbox_changed,
  [defines.events.on_gui_selection_state_changed] = on_selection_changed,
  [defines.events.on_gui_click] = on_gui_click,
  [defines.events.on_player_created] = on_player_created,
  [defines.events.on_entity_settings_pasted] = on_settings_pasted,
  [defines.events.on_tick] = on_tick
}

lib.on_init = function()
  for _, player in pairs(game.players) do
    create_asm_panel(player)
    create_asm_recipe_panel(player)
    create_furnace_panel(player)
    create_container_panel(player)
  end
end

lib.on_configuration_changed = function()
  for _, player in pairs(game.players) do
    recreate_panels(player)
  end
end

return lib
