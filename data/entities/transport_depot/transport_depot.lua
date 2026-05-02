local collision_box = {{-1.25, -1.25},{1.25, 1.25}}
local selection_box = {{-1.5, -1.5}, {1.5, 1.5}}

local category =
{
  type = "item-subgroup",
  name = "transport-drones",
  group = "logistics",
  order = "ez"
}

data:extend{category}

local depot = util.copy(data.raw["assembling-machine"]["assembling-machine-3"])
depot.graphics_set = {animation = nil, working_visualisations = nil}

local caution_sprite =
{
  type = "sprite",
  name = "caution-sprite",
  filename = util.path("data/entities/transport_depot/depot-caution.png"),
  width = 101,
  height = 72,
  frame_count = 1,
  scale = 0.33,
  direction_count = 1,
  draw_as_shadow = false,
  flags = {"terrain"}
}

local function make_depot_animation(filename, width, height, scale, shift)
  local sprite = {
    filename = util.path("data/entities/transport_depot/" .. filename),
    width = width or 474,
    height = height or 335,
    frame_count = 1,
    scale = scale or 0.45,
    shift = shift or {0, 0.4}
  }
  return {
    north = { layers = {sprite} },
    south = { layers = {sprite} },
    east = { layers = {sprite} },
    west = { layers = {sprite} },
  }
end

local function make_depot_chests(opts)
  local result = {}
  for quality_level, chest_name in pairs(opts.name_table) do
    local chest = {
      type = opts.chest_type or "container",
      name = chest_name,
      localised_name = {opts.locale_name},
      localised_description = {opts.locale_desc},
      icon = util.path("data/entities/transport_depot/" .. opts.icon_file),
      icon_size = 216,
      dying_explosion = depot.dying_explosion,
      damaged_trigger_effect = depot.damaged_trigger_effect,
      corpse = depot.corpse,
      flags = {"placeable-neutral", "player-creation", "not-blueprintable"},
      icon_draw_specification = {shift = {0, -0.3}},
      max_health = 150,
      collision_box = collision_box,
      collision_mask = {layers = {}},
      selection_priority = 100,
      fast_replaceable_group = "container",
      selection_box = selection_box,
      inventory_size = opts.inventory_table[quality_level],
      open_sound = { filename = "__base__/sound/metallic-chest-open.ogg", volume=0.5 },
      close_sound = { filename = "__base__/sound/metallic-chest-close.ogg", volume = 0.5 },
      picture = util.empty_sprite(),
      order = "nil",
      minable = {result = opts.item_name, mining_time = 1},
      placeable_by = {item = opts.item_name, count = 1},
      circuit_wire_max_distance = 10,
    }
    if opts.logistic_mode then chest.logistic_mode = opts.logistic_mode end
    if opts.max_logistic_slots then chest.max_logistic_slots = opts.max_logistic_slots end
    if opts.inventory_type then chest.inventory_type = opts.inventory_type end
    table.insert(result, chest)
  end
  return result
end

depot.name = "request-depot"
depot.localised_name = {"request-depot"}
depot.icon = util.path("data/entities/transport_depot/request-depot-icon.png")
depot.icon_size = 216
depot.collision_box = collision_box
depot.selection_box = selection_box
depot.max_health = 150
depot.fast_replaceable_group = nil
depot.radius_visualisation_specification =
{
  sprite = caution_sprite,
  distance = 0.5,
  offset = {0, -2}
}
depot.fluid_boxes =
{
  {
    production_type = "input",
    volume = 5000,
    pipe_connections = {{ flow_direction="input", position = {0, -1}, direction = defines.direction.north }},
  },
  {
    production_type = "output",
    volume = settings.startup["request-depot-fluid-capacity"].value,
    pipe_connections = {{ flow_direction="output", position = {0, 1}, direction = defines.direction.south }},
    pipe_covers = pipecoverspictures(),
    pipe_picture = assembler3pipepictures(),
    secondary_draw_orders = { north = -1, east = -1, west = -1}
  }
}
depot.fluid_boxes_off_when_no_fluid_recipe = false
depot.crafting_categories = {"transport-drone-request"}
depot.crafting_speed = (1)
depot.ingredient_count = nil
depot.allowed_effects = nil
depot.module_slots = 0
depot.minable = {result = "request-depot", mining_time = 1}
depot.flags = {"placeable-neutral", "player-creation"}
depot.next_upgrade = nil
depot.energy_usage = "1W"
depot.gui_title_key = "transport-depot-choose-item"
depot.energy_source =
{
  type = "void",
  usage_priority = "secondary-input",
  emissions_per_second = {pollution = 0.1}
}
depot.placeable_by = {item = "request-depot", count = 1}

depot.graphics_set.animation = make_depot_animation("request-depot-base.png")

local supply_depot = util.copy(depot)
supply_depot.name = "supply-depot"
supply_depot.localised_name = {"supply-depot"}
supply_depot.icon = util.path("data/entities/transport_depot/supply-depot-icon.png")
supply_depot.minable = {result = "supply-depot", mining_time = 1}
supply_depot.placeable_by = {item = "supply-depot", count = 1}

supply_depot.fluid_boxes =
{
  {
    production_type = "input",
    volume = 5000,
    pipe_connections = {{ flow_direction="input", position = {0, -1}, direction = defines.direction.north }},
  }
}
supply_depot.fluid_boxes_off_when_no_fluid_recipe = false


supply_depot.graphics_set.animation = make_depot_animation("supply-depot-base.png")

local caution_corpse =
{
  type = "corpse",
  name = "transport-caution-corpse",
  flags = {"placeable-off-grid"},
  animation = caution_sprite,
  expires = false,
  remove_on_entity_placement = false,
  remove_on_tile_placement = false
}

local supply_depot_chests = make_depot_chests({
  name_table = shared.supply_chest_name, locale_name = "supply-depot",
  locale_desc = "entity-description.supply-depot-chest",
  icon_file = "supply-depot-icon.png", inventory_table = shared.quality_supply_inventory,
  item_name = "supply-depot",
})

local supply_depot_chests_logistic = make_depot_chests({
  chest_type = "logistic-container", name_table = shared.supply_chest_name_logistic,
  locale_name = "supply-depot", locale_desc = "entity-description.supply-depot-chest",
  icon_file = "supply-depot-icon.png", inventory_table = shared.quality_supply_inventory,
  item_name = "supply-depot", logistic_mode = "passive-provider",
})

local category =
{
  type = "recipe-category",
  name = "transport-drone-request"
}

local items =
{
  {
    type = "item",
    name = "supply-depot",
    localised_name = {"supply-depot"},
    icon = util.path("data/entities/transport_depot/supply-depot-icon.png"),
    icon_size = 216,
    flags = {},
    subgroup = "transport-drones",
    order = "e-a-b",
    stack_size = 10,
    place_result = "supply-depot"
  },
  {
    type = "recipe",
    name = "supply-depot",
    localised_name = {"supply-depot"},
    icon = util.path("data/entities/transport_depot/supply-depot-icon.png"),
    icon_size = 216,

    enabled = false,
    ingredients =
    {
      {type = "item", name = "iron-plate", amount = 50},
      {type = "item", name = "iron-gear-wheel", amount = 10},
      {type = "item", name = "iron-stick", amount = 20},
    },
    energy_required = 5,
    results = {{type = "item", name = "supply-depot", amount = 1}}
  },
  {
    type = "item",
    name = "request-depot",
    localised_name = {"request-depot"},
    icon = depot.icon,
    icon_size = depot.icon_size,
    flags = {},
    subgroup = "transport-drones",
    order = "e-a-e",
    stack_size = 10,
    place_result = "request-depot"
  },
  {
    type = "recipe",
    name = "request-depot",
    localised_name = {"request-depot"},
    icon = depot.icon,
    icon_size = depot.icon_size,

    enabled = false,
    ingredients =
    {
      {type = "item", name = "iron-plate", amount = 50},
      {type = "item", name = "iron-gear-wheel", amount = 10},
      {type = "item", name = "iron-stick", amount = 20},
    },
    energy_required = 5,
    results = {{type = "item", name = "request-depot", amount = 1}}
  }
}

data:extend(items)

local fuel_depot = util.copy(depot)
fuel_depot.name = "fuel-depot"
fuel_depot.localised_name = {"fuel-depot"}
fuel_depot.icon = util.path("data/entities/transport_depot/fuel-depot-icon.png")
fuel_depot.icon_size = 264
fuel_depot.collision_box = {{-2.25, -2.25},{2.25, 2.25}}
fuel_depot.selection_box = {{-2.25, -2.25},{2.25, 2.25}}
fuel_depot.fluid_boxes =
{
  {
    production_type = "output",
    volume = 1000,
    pipe_connections = {{ flow_direction="input-output", position = {0, -2}, direction = defines.direction.north }},
  },
  {
    production_type = "input",
    volume = 1000,
    pipe_connections = {{ flow_direction="input-output", position = {0, 2}, direction = defines.direction.south }},
    pipe_covers = pipecoverspictures(),
    pipe_picture = assembler3pipepictures(),
    secondary_draw_orders = { north = -1, east = -1, west = -1}
  }
}
fuel_depot.fluid_boxes_off_when_no_fluid_recipe = false

fuel_depot.graphics_set.animation = make_depot_animation("fuel-depot-base.png", 334, 266, (32 * 5) / 266, {0.66, -0.1})

local fuel_depot_items =
{
  {
    type = "item",
    name = "fuel-depot",
    localised_name = {"fuel-depot"},
    icon = fuel_depot.icon,
    icon_size = fuel_depot.icon_size,
    flags = {},
    subgroup = "transport-drones",
    order = "e-c",
    stack_size = 10,
    place_result = "fuel-depot"
  },
  {
    type = "recipe",
    name = "fuel-depot",
    localised_name = {"fuel-depot"},
    icon = fuel_depot.icon,
    icon_size = fuel_depot.icon_size,

    enabled = false,
    ingredients =
    {
      {type = "item", name = "steel-plate", amount = 10},
      {type = "item", name = "iron-plate", amount = 20},
      {type = "item", name = "iron-gear-wheel", amount = 5},
      {type = "item", name = "pipe", amount = 10},
    },
    energy_required = 10,
    results = {{type = "item", name = "fuel-depot", amount = 1}}
  }
}

local fuel_recipe_category =
{
  type = "recipe-category",
  name = "fuel-depot"
}

data:extend{fuel_recipe_category}

local fuel_signal =
{
  type = "virtual-signal",
  name = "fuel-signal",
  icon = util.path("data/entities/transport_depot/fuel-recipe-icon.png"),
  icon_size = 64,
  subgroup = "virtual-signal",
  order = "oh-yea-baby"
}

fuel_depot.fixed_recipe = "fuel-depots"
fuel_depot.crafting_categories = {"fuel-depot"}
fuel_depot.minable.result = "fuel-depot"
fuel_depot.placeable_by = {item = "fuel-depot", count = 1},

data:extend(fuel_depot_items)
data:extend{fuel_signal}

local invisble_corpse =
{
  type = "corpse",
  name = "invisible-transport-caution-corpse",
  flags = {"placeable-off-grid"},
  animation = util.empty_sprite(),
  expires = false,
  remove_on_entity_placement = false,
  remove_on_tile_placement = false
}

local fluid_request_category =
{
  type = "recipe-category",
  name = "transport-fluid-request"
}

local fluid_supply_depot = util.copy(fuel_depot)
fluid_supply_depot.localised_name = {"fluid-depot"}
fluid_supply_depot.icon = util.path("data/entities/transport_depot/fluid-depot-icon.png")
fluid_supply_depot.icon_size = 216
fluid_supply_depot.collision_box = collision_box
fluid_supply_depot.selection_box = selection_box
fluid_supply_depot.name = "fluid-depot"
fluid_supply_depot.type = "furnace"
fluid_supply_depot.crafting_categories = {"transport-fluid-request"}
fluid_supply_depot.source_inventory_size = 0
fluid_supply_depot.result_inventory_size = 0
fluid_supply_depot.fixed_recipe = nil
fluid_supply_depot.placeable_by = {item = "fluid-depot", count = 1}
fluid_supply_depot.minable.result = "fluid-depot"


fluid_supply_depot.fluid_boxes =
{
  {
    production_type = "output",
    volume = 1000,
    pipe_connections = {{ flow_direction="input-output", position = {0, -1}, direction = defines.direction.north }},
  },
  {
    production_type = "input",
    volume = settings.startup["fluid-depot-capacity"].value,
    pipe_connections = {{ flow_direction="input-output", position = {0, 1}, direction = defines.direction.south }},
    pipe_covers = pipecoverspictures(),
    pipe_picture = assembler3pipepictures(),
    secondary_draw_orders = { north = -1, east = -1, west = -1}
  }
}
fluid_supply_depot.fluid_boxes_off_when_no_fluid_recipe = false

fluid_supply_depot.graphics_set.animation = make_depot_animation("fluid-depot-base.png", 231, 146, (32 * 3) / 146, {0.5, 0})

data:extend
{
  fluid_supply_depot,
  fluid_request_category
}

local fluid_depot_items =
{
  {
    type = "item",
    name = "fluid-depot",
    localised_name = {"fluid-depot"},
    icon = fluid_supply_depot.icon,
    icon_size = fluid_supply_depot.icon_size,
    flags = {},
    subgroup = "transport-drones",
    order = "e-c",
    stack_size = 10,
    place_result = "fluid-depot"
  },
  {
    type = "recipe",
    name = "fluid-depot",
    localised_name = {"fluid-depot"},
    icon = fluid_supply_depot.icon,
    icon_size = fluid_supply_depot.icon_size,

    enabled = false,
    ingredients =
    {
      {type = "item", name = "iron-plate", amount = 30},
      {type = "item", name = "iron-gear-wheel", amount = 5},
      {type = "item", name = "pipe", amount = 20},
    },
    energy_required = 5,
    results = {{type = "item", name = "fluid-depot", amount = 1}}
  }
}

data:extend(fluid_depot_items)

data:extend
{
  depot,
  supply_depot,
  caution_corpse,
  invisble_corpse,
  category,
  fuel_depot
}

data:extend(supply_depot_chests)
data:extend(supply_depot_chests_logistic)

local buffer_depot = util.copy(depot)
buffer_depot.name = "buffer-depot"
buffer_depot.localised_name = {"buffer-depot"}
buffer_depot.minable.result = "buffer-depot"
buffer_depot.placeable_by = {item = "buffer-depot", count = 1}
buffer_depot.icon = util.path("data/entities/transport_depot/buffer-depot-icon.png")


buffer_depot.graphics_set.animation = make_depot_animation("buffer-depot-base.png")

local buffer_depot_items =
{
  {
    type = "item",
    name = "buffer-depot",
    localised_name = {"buffer-depot"},
    icon = buffer_depot.icon,
    icon_size = buffer_depot.icon_size,
    flags = {},
    subgroup = "transport-drones",
    order = "e-a-d",
    stack_size = 10,
    place_result = "buffer-depot"
  },
  {
    type = "recipe",
    name = "buffer-depot",
    localised_name = {"buffer-depot"},
    icon = buffer_depot.icon,
    icon_size = buffer_depot.icon_size,

    enabled = false,
    ingredients =
    {
      {type = "item", name = "steel-plate", amount = 15},
      {type = "item", name = "iron-plate", amount = 20},
      {type = "item", name = "iron-gear-wheel", amount = 10},
      {type = "item", name = "electronic-circuit", amount = 10},
    },
    energy_required = 10,
    results = {{type = "item", name = "buffer-depot", amount = 1}}
  }
}

data:extend{buffer_depot}
data:extend(buffer_depot_items)

local active_depot = util.copy(depot)
active_depot.name = "active-depot"
active_depot.localised_name = {"active-depot"}
active_depot.icon = util.path("data/entities/transport_depot/active-depot-icon.png")
active_depot.icon_size = 216
active_depot.minable = {result = "active-depot", mining_time = 1}
active_depot.placeable_by = {item = "active-depot", count = 1}
active_depot.gui_title_key = nil
active_depot.fixed_recipe = "fuel-depots"
active_depot.crafting_categories = {"fuel-depot"}
active_depot.show_recipe_icon = false
active_depot.show_recipe_icon_on_map = false

active_depot.fluid_boxes =
{
  {
    production_type = "input",
    volume = 5000,
    pipe_connections = {{ flow_direction="input", position = {0, -1}, direction = defines.direction.north }},
  },
  {
    production_type = "output",
    volume = 1000,
    pipe_connections = {},
  }
}
active_depot.fluid_boxes_off_when_no_fluid_recipe = false

active_depot.graphics_set.animation = make_depot_animation("active-depot-base.png")

local active_depot_items =
{
  {
    type = "item",
    name = "active-depot",
    localised_name = {"active-depot"},
    icon = active_depot.icon,
    icon_size = active_depot.icon_size,
    flags = {},
    subgroup = "transport-drones",
    order = "e-a-a",
    stack_size = 10,
    place_result = "active-depot"
  },
  {
    type = "recipe",
    name = "active-depot",
    localised_name = {"active-depot"},
    icon = active_depot.icon,
    icon_size = active_depot.icon_size,
    enabled = false,
    ingredients =
    {
      {type = "item", name = "steel-plate", amount = 15},
      {type = "item", name = "iron-plate", amount = 30},
      {type = "item", name = "iron-gear-wheel", amount = 10},
      {type = "item", name = "electronic-circuit", amount = 10},
    },
    energy_required = 10,
    results = {{type = "item", name = "active-depot", amount = 1}}
  }
}

data:extend{active_depot}
data:extend(active_depot_items)

-- Fluid mode variant: furnace type with fluid recipe picker (like fluid-depot)
local active_depot_fluid = util.copy(active_depot)
active_depot_fluid.name = shared.active_depot_fluid_name
active_depot_fluid.localised_name = {"active-depot"}
active_depot_fluid.type = "furnace"
active_depot_fluid.placeable_by = {item = "active-depot", count = 1}
active_depot_fluid.minable = {result = "active-depot", mining_time = 1}
active_depot_fluid.crafting_categories = {"transport-fluid-request"}
active_depot_fluid.fixed_recipe = nil
active_depot_fluid.source_inventory_size = 0
active_depot_fluid.result_inventory_size = 0
active_depot_fluid.fluid_boxes =
{
  {
    production_type = "output",
    volume = 1,
    pipe_connections = {},
  },
  {
    production_type = "input",
    volume = 25000,
    pipe_connections = {{ flow_direction="input", position = {0, 1}, direction = defines.direction.south }},
    pipe_covers = pipecoverspictures(),
    pipe_picture = assembler3pipepictures(),
    secondary_draw_orders = { north = -1, east = -1, west = -1}
  }
}
active_depot_fluid.fluid_boxes_off_when_no_fluid_recipe = false
active_depot_fluid.show_recipe_icon = true

data:extend{active_depot_fluid}

local active_depot_chests = make_depot_chests({
  name_table = shared.active_chest_name, locale_name = "active-depot",
  locale_desc = "entity-description.active-depot-chest",
  icon_file = "active-depot-icon.png", inventory_table = shared.quality_supply_inventory,
  item_name = "active-depot",
})

data:extend(active_depot_chests)

local storage_depot = util.copy(depot)
storage_depot.name = "storage-depot"
storage_depot.localised_name = {"storage-depot"}
storage_depot.icon = util.path("data/entities/transport_depot/storage-depot-icon.png")
storage_depot.icon_size = 216
storage_depot.minable = {result = "storage-depot", mining_time = 1}
storage_depot.placeable_by = {item = "storage-depot", count = 1}
storage_depot.gui_title_key = nil
storage_depot.crafting_categories = {"fuel-depot"}
storage_depot.show_recipe_icon = false
storage_depot.show_recipe_icon_on_map = false
storage_depot.flags = {"placeable-neutral", "player-creation"}
storage_depot.fluid_boxes =
{
  {
    production_type = "output",
    volume = 1,
    pipe_connections = {},
  }
}
storage_depot.fluid_boxes_off_when_no_fluid_recipe = false

storage_depot.graphics_set.animation = make_depot_animation("storage-depot-base.png")

local storage_depot_items =
{
  {
    type = "item",
    name = "storage-depot",
    localised_name = {"storage-depot"},
    icon = storage_depot.icon,
    icon_size = storage_depot.icon_size,
    flags = {},
    subgroup = "transport-drones",
    order = "e-a-c",
    stack_size = 10,
    place_result = "storage-depot"
  },
  {
    type = "recipe",
    name = "storage-depot",
    localised_name = {"storage-depot"},
    icon = storage_depot.icon,
    icon_size = storage_depot.icon_size,
    enabled = false,
    ingredients =
    {
      {type = "item", name = "steel-plate", amount = 10},
      {type = "item", name = "iron-plate", amount = 20},
      {type = "item", name = "iron-gear-wheel", amount = 10},
      {type = "item", name = "electronic-circuit", amount = 5},
    },
    energy_required = 10,
    results = {{type = "item", name = "storage-depot", amount = 1}}
  }
}

data:extend{storage_depot}
data:extend(storage_depot_items)

local storage_depot_chests = make_depot_chests({
  name_table = shared.storage_chest_name, locale_name = "storage-depot",
  locale_desc = "entity-description.storage-depot-chest",
  icon_file = "storage-depot-icon.png", inventory_table = shared.quality_supply_inventory,
  item_name = "storage-depot", inventory_type = "with_filters_and_bar",
})

local storage_depot_chests_logistic = make_depot_chests({
  chest_type = "logistic-container", name_table = shared.storage_chest_name_logistic,
  locale_name = "storage-depot", locale_desc = "entity-description.storage-depot-chest",
  icon_file = "storage-depot-icon.png", inventory_table = shared.quality_supply_inventory,
  item_name = "storage-depot", logistic_mode = "storage", max_logistic_slots = 1,
})

data:extend(storage_depot_chests)
data:extend(storage_depot_chests_logistic)

-- Fluid mode variant: furnace type with fluid recipe picker (like fluid-depot)
local storage_depot_fluid = util.copy(storage_depot)
storage_depot_fluid.name = shared.storage_depot_fluid_name
storage_depot_fluid.localised_name = {"storage-depot"}
storage_depot_fluid.type = "furnace"
storage_depot_fluid.crafting_categories = {"transport-fluid-request"}
storage_depot_fluid.fixed_recipe = nil
storage_depot_fluid.source_inventory_size = 0
storage_depot_fluid.result_inventory_size = 0
storage_depot_fluid.flags = {"placeable-neutral", "player-creation"}
storage_depot_fluid.placeable_by = {item = "storage-depot", count = 1}
storage_depot_fluid.fluid_boxes =
{
  {
    production_type = "input",
    volume = settings.startup["fluid-depot-capacity"].value,
    pipe_connections = {{ flow_direction="output", position = {0, 1}, direction = defines.direction.south }},
    pipe_covers = pipecoverspictures(),
    pipe_picture = assembler3pipepictures(),
    secondary_draw_orders = { north = -1, east = -1, west = -1}
  },
  {
    production_type = "output",
    volume = 1,
    pipe_connections = {},
  }
}
storage_depot_fluid.fluid_boxes_off_when_no_fluid_recipe = false
storage_depot_fluid.show_recipe_icon = true
storage_depot_fluid.show_recipe_icon_on_map = true

data:extend{storage_depot_fluid}

local dispatcher_depot = util.copy(depot)
dispatcher_depot.name = "drone-dispatcher"
dispatcher_depot.localised_name = {"drone-dispatcher"}
dispatcher_depot.icon = util.path("data/entities/transport_depot/drone-dispatcher-icon.png")
dispatcher_depot.icon_size = 216
dispatcher_depot.minable = {result = "drone-dispatcher", mining_time = 1}
dispatcher_depot.placeable_by = {item = "drone-dispatcher", count = 1}
dispatcher_depot.gui_title_key = nil
dispatcher_depot.crafting_categories = {"fuel-depot"}
dispatcher_depot.show_recipe_icon = false
dispatcher_depot.show_recipe_icon_on_map = false
dispatcher_depot.flags = {"placeable-neutral", "player-creation", "not-selectable-in-game"}
dispatcher_depot.fluid_boxes =
{
  {
    production_type = "input",
    volume = settings.startup["dispatcher-depot-capacity"].value,
    pipe_connections = {{ flow_direction="input", position = {0, -1}, direction = defines.direction.north }},
  }
}
dispatcher_depot.fluid_boxes_off_when_no_fluid_recipe = false

dispatcher_depot.graphics_set.animation = make_depot_animation("drone-dispatcher-base.png")

local dispatcher_depot_items =
{
  {
    type = "item",
    name = "drone-dispatcher",
    localised_name = {"drone-dispatcher"},
    icon = dispatcher_depot.icon,
    icon_size = dispatcher_depot.icon_size,
    flags = {},
    subgroup = "transport-drones",
    order = "e-a-f",
    stack_size = 10,
    place_result = "drone-dispatcher"
  },
  {
    type = "recipe",
    name = "drone-dispatcher",
    localised_name = {"drone-dispatcher"},
    icon = dispatcher_depot.icon,
    icon_size = dispatcher_depot.icon_size,
    enabled = false,
    ingredients =
    {
      {type = "item", name = "steel-plate", amount = 10},
      {type = "item", name = "iron-plate", amount = 20},
      {type = "item", name = "iron-gear-wheel", amount = 10},
      {type = "item", name = "electronic-circuit", amount = 5},
    },
    energy_required = 10,
    results = {{type = "item", name = "drone-dispatcher", amount = 1}}
  }
}

data:extend{dispatcher_depot}
data:extend(dispatcher_depot_items)

local dispatcher_depot_chests = make_depot_chests({
  name_table = shared.dispatcher_chest_name, locale_name = "drone-dispatcher",
  locale_desc = "entity-description.drone-dispatcher-chest",
  icon_file = "drone-dispatcher-icon.png", inventory_table = shared.quality_dispatcher_inventory,
  item_name = "drone-dispatcher", inventory_type = "with_filters_and_bar",
})

data:extend(dispatcher_depot_chests)

for quality_level, chest_name in pairs(shared.drone_chest_name) do
  data:extend{{
    type = "logistic-container",
    name = chest_name,
    localised_name = {"depot-drone-chest"},
    localised_description = {"entity-description.depot-drone-chest"},
    icon = "__base__/graphics/icons/wooden-chest.png",
    icon_size = 64,
    flags = {"placeable-neutral", "not-blueprintable", "not-deconstructable", "hide-alt-info"},
    max_health = 50,
    collision_mask = {layers = {}},
    selection_priority = 1,
    selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
    collision_box = {{-0.4, -0.4}, {0.4, 0.4}},
    inventory_size = shared.quality_drone_chest[quality_level],
    picture = util.empty_sprite(),
    inventory_type = "with_filters",
    logistic_mode = "requester",
    max_logistic_slots = 5,
    render_not_in_network_icon = false,
  }}
end

for quality_level, chest_name in pairs(shared.buffer_chest_name_logistic) do
  data:extend{{
    type = "logistic-container",
    name = chest_name,
    localised_name = {"buffer-depot"},
    localised_description = {"entity-description.buffer-depot-chest-logistic"},
    icon = "__base__/graphics/icons/wooden-chest.png",
    icon_size = 64,
    flags = {"placeable-neutral", "not-blueprintable", "not-deconstructable", "not-selectable-in-game", "hide-alt-info"},
    max_health = 50,
    collision_mask = {layers = {}},
    collision_box = {{-0.4, -0.4}, {0.4, 0.4}},
    inventory_size = 48,
    picture = util.empty_sprite(),
    logistic_mode = "buffer",
    render_not_in_network_icon = false,
  }}
end

local reader = util.copy(data.raw["constant-combinator"]["constant-combinator"])
reader.name = "road-network-reader"
reader.localised_name = "Road network reader"
reader.sprites = require(util.path("data/entities/transport_depot_circuits/road-network-reader-sprite"))
reader.icon = util.path("data/entities/transport_depot_circuits/road-network-reader-icon.png")
reader.icon_size = 72
reader.minable.result = "road-network-reader"
reader.radius_visualisation_specification =
{
  sprite = caution_sprite,
  distance = 0.5,
  offset = {0, 1}
}

local reader_item =
{
  type = "item",
  name = "road-network-reader",
  icon = reader.icon,
  icon_size = reader.icon_size,
  stack_size = 20,
  subgroup = "transport-drones",
  order = "z-a",
  place_result = "road-network-reader"
}

local reader_recipe =
{
  type = "recipe",
  name = "road-network-reader",
  localised_name = {"road-network-reader"},
  icon = reader.icon,
  icon_size = reader.icon_size,
  enabled = false,
  ingredients =
  {
    {type = "item", name = "copper-cable", amount = 5},
    {type = "item", name = "electronic-circuit", amount = 5},
    {type = "item", name = "advanced-circuit", amount = 3},
  },
  energy_required = 5,
  results = {{type = "item", name = "road-network-reader", amount = 1}}
}

data:extend
{
  reader,
  reader_item,
  reader_recipe
}