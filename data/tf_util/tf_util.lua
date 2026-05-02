local util = require("util")

util.has_flag = function(prototype, flag)
  if not prototype.flags then return false end
  for k, v in pairs (prototype.flags) do
    if v == flag then
      return true
    end
  end
end

util.path = function(str)
  return "__Transport_Drones_Continued__/" .. str
end

util.empty_sprite = function()
  return
  {
    filename = util.path("data/tf_util/empty-sprite.png"),
    height = 1,
    width = 1,
    frame_count = 1,
    direction_count = 1
  }
end

util.damage_type = function(name)
  if not data.raw["damage-type"][name] then
    data:extend{{type = "damage-type", name = name, localised_name = {name}}}
  end
  return name
end

util.ammo_category = function(name)
  if not data.raw["ammo-category"][name] then
    data:extend{{type = "ammo-category", name = name, localised_name = {name}}}
  end
  return name
end

util.remove_from_list = function(list, name)
  local remove = table.remove
  for i = #list, 1, -1 do
    if list[i] == name then
      remove(list, i)
    end
  end
end

util.copy = util.table.deepcopy

util.item_types = function()
  return
  {
    "item",
    "rail-planner",
    "item-with-entity-data",
    "capsule",
    "mining-tool",
    "repair-tool",
    "blueprint",
    "module",
    "tool",
    "gun",
    "ammo",
    "armor",
    "item-with-label",
    "item-with-tags"
  }
end

return util
