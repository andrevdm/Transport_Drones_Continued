-- Resolves the fuel fluid setting with fallback logic (data stage only).
-- Cached by require() so the fallback resolution runs at most once.
local fuel = settings.startup["fuel-fluid"].value
if not data.raw.fluid[fuel] then
  log("Bad name for fuel fluid. reverting to something else...")

  fuel = "petroleum-gas"
  if not data.raw.fluid[fuel] then
    fuel = nil
    for k, fluid in pairs (data.raw.fluid) do
      if fluid.fuel_value then
        fuel = fluid.name
        break
      end
    end
  end

  if not fuel then
    local index, fluid = next(data.raw.fluid)
    if fluid then
      fuel = fluid.name
    end
  end
end

return fuel
