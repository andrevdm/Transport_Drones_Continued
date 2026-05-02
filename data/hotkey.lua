local hotkeys =
{
  {
    type = "custom-input",
    name = "follow-drone",
    localised_name = {"follow-drone"},
    linked_game_control = "toggle-driving",
    key_sequence = "ENTER",
    enabled_while_in_cutscene = true
  },
  {
    type = "custom-input",
    name = "toggle-road-network-gui",
    localised_name = {"toggle-road-network-gui"},
    key_sequence = "CONTROL + T",
    enabled_while_in_cutscene = true
  },
}

data:extend(hotkeys)