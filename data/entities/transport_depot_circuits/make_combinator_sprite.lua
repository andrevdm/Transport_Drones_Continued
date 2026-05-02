-- Shared helper: generates 4-direction combinator sprite table.
-- All circuit entities (reader, writer, road-network-reader) use the same
-- spritesheet layout and shadow, differing only in the main sprite filename.
local function make_combinator_sprite(filename)
  local path = "__Transport_Drones_Continued__/data/entities/transport_depot_circuits/" .. filename
  local shadow = "__base__/graphics/entity/combinator/constant-combinator-shadow.png"

  local function make_direction(sprite_x, shadow_x)
    return {
      layers = {
        {
          filename = path,
          frame_count = 1,
          height = 102,
          priority = "high",
          scale = 0.5,
          shift = {0, 0.15625},
          width = 114,
          x = sprite_x,
          y = 0
        },
        {
          draw_as_shadow = true,
          filename = shadow,
          frame_count = 1,
          height = 66,
          priority = "high",
          scale = 0.5,
          shift = {0.265625, 0.171875},
          width = 98,
          x = shadow_x,
          y = 0
        }
      }
    }
  end

  return {
    north = make_direction(0, 0),
    east  = make_direction(114, 98),
    south = make_direction(228, 196),
    west  = make_direction(342, 294),
  }
end

return make_combinator_sprite
