local shared = require("shared")
local name = shared.transport_system_technology

local transport_system =
{
  name = name,
  localised_name = {name},
  type = "technology",
  icon = util.path("data/technologies/transport-system.png"),
  icon_size = 256,
  upgrade = false,
  effects =
  {
    {
      type = "unlock-recipe",
      recipe = "transport-drone"
    },
    {
      type = "unlock-recipe",
      recipe = "request-depot"
    },
    {
      type = "unlock-recipe",
      recipe = "supply-depot"
    },
    {
      type = "unlock-recipe",
      recipe = "fuel-depot"
    },
    {
      type = "unlock-recipe",
      recipe = "road"
    },
  },
  prerequisites = {"engine"},
  unit =
  {
    count = 200,
    ingredients =
    {
      {"automation-science-pack", 1},
      {"logistic-science-pack", 1},
    },
    time = 30
  },
  order = name,
}

if settings.startup["enable-drone-dispatcher"].value then
  table.insert(transport_system.effects, {type = "unlock-recipe", recipe = "drone-dispatcher"})
end

data:extend{transport_system}


local transport_fluids =
{
  name = "transport-fluids",
  localised_name = {"transport-fluids"},
  type = "technology",
  icon = util.path("data/technologies/transport-system.png"),
  icon_size = 256,
  upgrade = false,
  effects =
  {
    {
      type = "unlock-recipe",
      recipe = "fluid-depot"
    }
  },
  prerequisites = {name, "fluid-handling"},
  unit =
  {
    count = 300,
    ingredients =
    {
      {"automation-science-pack", 1},
      {"logistic-science-pack", 1},
      {"chemical-science-pack", 1},
    },
    time = 30
  },
  order = name.."a",
}

data:extend{transport_fluids}

if settings.startup["enable-multi-pipe"].value then
  local transport_multi_pipe =
  {
    name = "transport-multi-pipe",
    localised_name = {"transport-multi-pipe"},
    type = "technology",
    icon = util.path("data/technologies/transport-system.png"),
    icon_size = 256,
    upgrade = false,
    effects =
    {
      {
        type = "nothing",
        effect_description = {"transport-multi-pipe-effect"}
      }
    },
    prerequisites = {"transport-fluids"},
    unit =
    {
      count = 300,
      ingredients =
      {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"chemical-science-pack", 1},
      },
      time = 30
    },
    order = name.."ab",
  }
  data:extend{transport_multi_pipe}
end


local transport_buffering =
{
  name = "transport-buffering",
  localised_name = {"transport-buffering"},
  type = "technology",
  icon = util.path("data/technologies/transport-system.png"),
  icon_size = 256,
  upgrade = false,
  effects =
  {
    {
      type = "unlock-recipe",
      recipe = "buffer-depot"
    }
  },
  prerequisites = {name},
  unit =
  {
    count = 400,
    ingredients =
    {
      {"automation-science-pack", 1},
      {"logistic-science-pack", 1},
      {"chemical-science-pack", 1},
    },
    time = 30
  },
  order = name.."b",
}

data:extend{transport_buffering}


local transport_logistics =
{
  name = "transport-logistics",
  localised_name = {"transport-logistics"},
  type = "technology",
  icon = util.path("data/technologies/transport-system.png"),
  icon_size = 256,
  upgrade = false,
  effects =
  {
    {
      type = "nothing",
      effect_description = {"transport-logistics-effect"}
    }
  },
  prerequisites = {name, "logistic-robotics"},
  unit =
  {
    count = 300,
    ingredients =
    {
      {"automation-science-pack", 1},
      {"logistic-science-pack", 1},
    },
    time = 30
  },
  order = name.."c",
}

data:extend{transport_logistics}


local transport_circuits =
{
  name = "transport-depot-circuits",
  localised_name = {"transport-depot-circuits"},
  type = "technology",
  icon = util.path("data/technologies/transport-circuits-icon.png"),
  icon_size = 144,
  upgrade = false,
  effects =
  {
    {
      type = "unlock-recipe",
      recipe = "transport-depot-writer"
    },
    {
      type = "unlock-recipe",
      recipe = "transport-depot-reader"
    },
    {
      type = "unlock-recipe",
      recipe = "road-network-reader"
    },
  },
  prerequisites = {"circuit-network", name},
  unit =
  {
    count = 500,
    ingredients =
    {
      {"automation-science-pack", 1},
      {"logistic-science-pack", 1},
    },
    time = 30
  },
  order = "transport-depot-circuits",
}

data:extend{transport_circuits}


local better_road =
{
  name = "fast-road",
  localised_name = {"fast-road"},
  type = "technology",
  icon = util.path("data/technologies/fast-road-icon.png"),
  icon_size = 128,
  upgrade = false,
  effects =
  {
    {
      type = "unlock-recipe",
      recipe = "fast-road"
    }
  },
  prerequisites = {name},
  unit =
  {
    count = 500,
    ingredients =
    {
      {"automation-science-pack", 1},
      {"logistic-science-pack", 1},
      {"chemical-science-pack", 1},
    },
    time = 30
  },
  order = name.."z",
}

data:extend{better_road}


local transport_active_supply =
{
  name = "transport-active-supply",
  localised_name = {"transport-active-supply"},
  type = "technology",
  icon = util.path("data/technologies/transport-system.png"),
  icon_size = 256,
  upgrade = false,
  effects = {},
  prerequisites = {"transport-buffering"},
  unit =
  {
    count = 500,
    ingredients =
    {
      {"automation-science-pack", 1},
      {"logistic-science-pack", 1},
      {"chemical-science-pack", 1},
    },
    time = 30
  },
  order = name.."d",
}

if settings.startup["enable-active-depot"].value then
  table.insert(transport_active_supply.effects, {type = "unlock-recipe", recipe = "active-depot"})
end
if settings.startup["enable-storage-depot"].value then
  table.insert(transport_active_supply.effects, {type = "unlock-recipe", recipe = "storage-depot"})
end

data:extend{transport_active_supply}