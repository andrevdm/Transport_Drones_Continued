-- Custom GUI styles for Transport Drones

local default_style = data.raw["gui-style"]["default"]
local path = "__Transport_Drones_Continued__/data/gui/"

default_style["td_red_slot_button"] =
{
  type = "button_style",
  parent = "slot_button",
  default_graphical_set =
  {
    base = {border = 4, filename = path .. "red-slot.png", size = 80},
  },
  hovered_graphical_set =
  {
    base = {border = 4, filename = path .. "red-slot-hovered.png", size = 80},
  },
  clicked_graphical_set =
  {
    base = {border = 4, filename = path .. "red-slot-clicked.png", size = 80},
  },
}

default_style["green_slot_button"] =
{
  type = "button_style",
  parent = "slot_button",
  default_graphical_set =
  {
    base = {border = 4, filename = path .. "green-slot.png", size = 80},
  },
  hovered_graphical_set =
  {
    base = {border = 4, filename = path .. "green-slot-hovered.png", size = 80},
  },
  clicked_graphical_set =
  {
    base = {border = 4, filename = path .. "green-slot-clicked.png", size = 80},
  },
}
