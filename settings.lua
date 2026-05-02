local settings =
{
  {
    type = "int-setting",
    name = "transport-depot-update-interval",
    localised_name = "Transport depot update interval",
    setting_type = "runtime-global",
    default_value = 30,
    minimum_value = 1,
    maximum_value = 80085
  },

  {
    type = "string-setting",
    name = "fuel-fluid",
    localised_name = "Transport drone fuel",
    setting_type = "startup",
    default_value = "petroleum-gas"
  },

  {
    type = "double-setting",
    name = "fuel-amount-per-drone",
    localised_name = "Transport drone fuel per drone",
    setting_type = "startup",
    default_value = 50,
    minimum_value = 0,
    maximum_value = 10000
  },

  {
    type = "double-setting",
    name = "drone-fluid-capacity",
    localised_name = "Transport drone fluid capacity",
    setting_type = "startup",
    default_value = 500,
    minimum_value = 1,
    maximum_value = 10000
  },

  {
    type = "int-setting",
    name = "fluid-depot-capacity",
    setting_type = "startup",
    default_value = 25000,
    minimum_value = 1000,
    maximum_value = 1000000
  },

  {
    type = "int-setting",
    name = "request-depot-fluid-capacity",
    setting_type = "startup",
    default_value = 25000,
    minimum_value = 1000,
    maximum_value = 1000000
  },

  {
    type = "double-setting",
    name = "fuel-consumption-per-meter",
    localised_name = "Fuel consumption per meter",
    setting_type = "startup",
    default_value = 0.025,
    minimum_value = 0
  },

  {
    type = "double-setting",
    name = "drone-pollution-per-second",
    localised_name = "Pollution per second",
    setting_type = "startup",
    default_value = 0.005,
    minimum_value = 0
  },

  {
    type = "int-setting",
    name = "transport-drone-pathfinder-max-steps",
    setting_type = "runtime-global",
    default_value = 10000,
    minimum_value = 100,
    maximum_value = 100000
  },

  {
    type = "int-setting",
    name = "transport-drone-pathfinder-max-work",
    setting_type = "runtime-global",
    default_value = 80000,
    minimum_value = 1000,
    maximum_value = 1000000
  },

  {
    type = "bool-setting",
    name = "transport-drone-pathfinder-use-cache",
    setting_type = "runtime-global",
    default_value = true
  },

  {
    type = "int-setting",
    name = "transport-drone-sound-volume",
    localised_name = "Transport drone sound volume",
    localised_description = "Volume of the transport drone engine sound (0 = silent, 100 = default)",
    setting_type = "startup",
    default_value = 80,
    minimum_value = 0,
    maximum_value = 100
  },

  {
    type = "string-setting",
    name = "transport-drones-road-tile-whitelist",
    setting_type = "startup",
    default_value = "^Arci%-,^dect%-concrete%-grid$,@py-tiles"
  },

  {
    type = "bool-setting",
    name = "transport-drones-diagonal-check",
    setting_type = "startup",
    default_value = true
  },

  {
    type = "int-setting",
    name = "transport-drone-load-balance-threshold",
    setting_type = "runtime-global",
    default_value = 20,
    minimum_value = 0,
    maximum_value = 200
  },

  {
    type = "int-setting",
    name = "transport-drone-priority-weight",
    setting_type = "runtime-global",
    default_value = 0,
    minimum_value = 0,
    maximum_value = 1000
  },

  {
    type = "int-setting",
    name = "transport-drone-max-dispatches-per-tick",
    setting_type = "runtime-global",
    default_value = 100,
    minimum_value = 1,
    maximum_value = 10000
  },

  {
    type = "int-setting",
    name = "transport-drone-redispatch-interval",
    setting_type = "runtime-global",
    default_value = 10,
    minimum_value = 1,
    maximum_value = 120
  },

  {
    type = "bool-setting",
    name = "transport-drones-space-platform-roads",
    setting_type = "startup",
    default_value = true
  },

  {
    type = "bool-setting",
    name = "enable-drone-dispatcher",
    setting_type = "startup",
    default_value = true
  },

  {
    type = "bool-setting",
    name = "enable-active-depot",
    setting_type = "startup",
    default_value = true
  },

  {
    type = "bool-setting",
    name = "enable-storage-depot",
    setting_type = "startup",
    default_value = true
  },

  {
    type = "bool-setting",
    name = "enable-multi-pipe",
    setting_type = "startup",
    default_value = true
  },

  {
    type = "int-setting",
    name = "active-depot-overfill-percent",
    setting_type = "runtime-global",
    default_value = 25,
    minimum_value = 0,
    maximum_value = 200
  },

  {
    type = "int-setting",
    name = "transport-drone-stack-size",
    setting_type = "startup",
    default_value = 10,
    minimum_value = 1,
    maximum_value = 1000
  },

  {
    type = "int-setting",
    name = "dispatcher-depot-capacity",
    setting_type = "startup",
    default_value = 50000,
    minimum_value = 1000,
    maximum_value = 1000000
  }
}

data:extend(settings)
