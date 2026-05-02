-- Writer: constant-combinator (shows wire signals on hover)
local writer = util.copy(data.raw["constant-combinator"]["constant-combinator"])
writer.name = "transport-depot-writer"
writer.localised_name = "Transport depot writer"
writer.sprites = require(util.path("data/entities/transport_depot_circuits/depot-writer-sprite"))
writer.icon = util.path("data/entities/transport_depot_circuits/depot-writer-icon.png")
writer.icon_size = 72
writer.collision_box = {{-0.4, -0.4},{0.4, 0.4}}
writer.selection_box = {{-0.5, -0.5}, {0.5, 0.5}}
writer.minable.result = "transport-depot-writer"
writer.next_upgrade = nil
writer.radius_visualisation_specification =
{
  offset = {0, 1},
  distance = 0.5,
  sprite =
  {
    filename = "__core__/graphics/arrows/gui-arrow-circle.png",
    height = 50,
    width = 50
  }
}

-- Legacy pump prototype for migration from older saves
local legacy_writer = util.copy(data.raw.pump.pump)
legacy_writer.name = "transport-depot-writer-legacy"
legacy_writer.localised_name = "Transport depot writer"
legacy_writer.hidden = true
legacy_writer.hidden_in_factoriopedia = true
legacy_writer.energy_source = {type = "void", energy_usage = "0w"}
legacy_writer.glass_pictures = nil
legacy_writer.fluid_animations = nil
legacy_writer.pumping_speed = 0
legacy_writer.load_connector_animations = nil
legacy_writer.unload_connetor_animations = nil
legacy_writer.fluid_wagon_connector_frame_count = 0
legacy_writer.collision_box = {{-0.4, -0.4},{0.4, 0.4}}
legacy_writer.selection_box = {{-0.5, -0.5}, {0.5, 0.5}}
legacy_writer.next_upgrade = nil
legacy_writer.fluid_box =
{
  volume = 1,
  production_type = "none",
  pipe_connections =
  {
    {
      position = {0, 0},
      flow_direction = "output",
      direction = defines.direction.south,
      connection_category = "transport-depot-writer-internal"
    }
  }
}

local writer_item =
{
  type = "item",
  name = "transport-depot-writer",
  icon = writer.icon,
  icon_size = writer.icon_size,
  stack_size = 20,
  subgroup = "transport-drones",
  order = "z-b",
  place_result = "transport-depot-writer"
}


local writer_recipe =
{
  type = "recipe",
  name = "transport-depot-writer",
  localised_name = {"transport-depot-writer"},
  icon = writer.icon,
  icon_size = writer.icon_size,
  enabled = false,
  ingredients =
  {
    {type = "item", name = "copper-cable", amount = 5},
    {type = "item", name = "electronic-circuit", amount = 5},
    {type = "item", name = "advanced-circuit", amount = 2},
  },
  energy_required = 5,
  results = {{type = "item", name = "transport-depot-writer", amount = 1}}
}

data:extend
{
  writer,
  writer_item,
  writer_recipe,
  legacy_writer
}

local reader = util.copy(data.raw["constant-combinator"]["constant-combinator"])
reader.name = "transport-depot-reader"
reader.localised_name = "Transport depot reader"
reader.sprites = require(util.path("data/entities/transport_depot_circuits/depot-reader-sprite"))
reader.icon = util.path("data/entities/transport_depot_circuits/depot-reader-icon.png")
reader.icon_size = 72
reader.minable.result = "transport-depot-reader"
reader.radius_visualisation_specification =
{
  offset = {0, 1},
  distance = 0.5,
  sprite =
  {
    filename = "__core__/graphics/arrows/gui-arrow-circle.png",
    height = 50,
    width = 50
  }
}

local reader_item =
{
  type = "item",
  name = "transport-depot-reader",
  icon = reader.icon,
  icon_size = reader.icon_size,
  stack_size = 20,
  subgroup = "transport-drones",
  order = "z-c",
  place_result = "transport-depot-reader"
}

local reader_recipe =
{
  type = "recipe",
  name = "transport-depot-reader",
  localised_name = {"transport-depot-reader"},
  icon = reader.icon,
  icon_size = reader.icon_size,
  enabled = false,
  ingredients =
  {
    {type = "item", name = "copper-cable", amount = 5},
    {type = "item", name = "electronic-circuit", amount = 5},
    {type = "item", name = "advanced-circuit", amount = 2},
  },
  energy_required = 5,
  results = {{type = "item", name = "transport-depot-reader", amount = 1}}
}

data:extend
{
  reader,
  reader_item,
  reader_recipe
}

local filtered_reader = util.copy(data.raw["constant-combinator"]["constant-combinator"])
filtered_reader.name = "road-network-reader-filtered"
filtered_reader.localised_name = "Road network reader (excluding depot)"
filtered_reader.sprites = require(util.path("data/entities/transport_depot_circuits/depot-reader-sprite"))
filtered_reader.icon = util.path("data/entities/transport_depot_circuits/depot-reader-icon.png")
filtered_reader.icon_size = 72
filtered_reader.minable.result = "road-network-reader-filtered"
filtered_reader.radius_visualisation_specification =
{
  offset = {0, 1},
  distance = 0.5,
  sprite =
  {
    filename = "__core__/graphics/arrows/gui-arrow-circle.png",
    height = 50,
    width = 50
  }
}

local filtered_reader_item =
{
  type = "item",
  name = "road-network-reader-filtered",
  icon = filtered_reader.icon,
  icon_size = filtered_reader.icon_size,
  stack_size = 20,
  subgroup = "transport-drones",
  order = "z-d",
  place_result = "road-network-reader-filtered",
  hidden = true
}

local filtered_reader_recipe =
{
  type = "recipe",
  name = "road-network-reader-filtered",
  localised_name = {"road-network-reader-filtered"},
  icon = filtered_reader.icon,
  icon_size = filtered_reader.icon_size,
  enabled = false,
  hidden = true,
  ingredients =
  {
    {type = "item", name = "copper-cable", amount = 5},
    {type = "item", name = "electronic-circuit", amount = 5},
    {type = "item", name = "advanced-circuit", amount = 3},
  },
  energy_required = 5,
  results = {{type = "item", name = "road-network-reader-filtered", amount = 1}}
}

data:extend
{
  filtered_reader,
  filtered_reader_item,
  filtered_reader_recipe
}