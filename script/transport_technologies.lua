local script_data =
{
  transport_speed = {},
  transport_capacity = {},
}

local max = math.max

local technology_effects =
{
  [shared.transport_speed_technology] = function(technology)
    local force_index = technology.force.index
    local current = script_data.transport_speed[force_index] or 0
    script_data.transport_speed[force_index] = max(current, technology.level * 0.15)
  end,
  [shared.transport_capacity_technology] = function(technology)
    local force_index = technology.force.index
    local current = script_data.transport_capacity[force_index] or 0
    script_data.transport_capacity[force_index] = max(current, technology.level)
  end,
}


local on_research_finished = function(event)
  local technology = event.research
  local name = technology.name

  for effect_name, effect in pairs (technology_effects) do
    if name:find(effect_name, 0, true) then
      effect(technology)
      break
    end
  end

end

local lib = {}

lib.get_transport_speed_bonus = function(force_index)
  return script_data.transport_speed[force_index] or 0
end

lib.get_transport_capacity_bonus = function(force_index)
  return script_data.transport_capacity[force_index] or 0
end

local refresh_all_technologies = function()
  for _, force in pairs(game.forces) do
    local force_index = force.index
    script_data.transport_speed[force_index] = 0
    script_data.transport_capacity[force_index] = 0
    for name, tech in pairs(force.technologies) do
      if tech.researched then
        for effect_name, effect in pairs(technology_effects) do
          if name:find(effect_name, 0, true) then
            effect(tech)
            break
          end
        end
      end
    end
  end
end

lib.on_load = function()
  script_data = storage.transport_technologies or script_data
end

lib.on_init = function()
  storage.transport_technologies = storage.transport_technologies or script_data
  refresh_all_technologies()
end

lib.on_configuration_changed = function()
  storage.transport_technologies = storage.transport_technologies or script_data
  script_data = storage.transport_technologies
  refresh_all_technologies()
end

lib.events =
{
  [defines.events.on_research_finished] = on_research_finished
}

return lib