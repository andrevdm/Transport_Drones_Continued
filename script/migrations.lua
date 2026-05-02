-- Centralized migration logic for on_configuration_changed.
-- Runs BEFORE depot_common and transport_drone reconnection handlers.
--
-- Each migration block is annotated with the version that introduced the
-- feature, meaning saves from a prior version will need it on first load.

local shared = shared

local lib = {}

lib.on_configuration_changed = function()

  -- ===== Writer migration: pump → constant-combinator (2.0.49) =====
  storage.writer_config = storage.writer_config or {}

  for _, surface in pairs(game.surfaces) do
    local legacy_writers = surface.find_entities_filtered{name = "transport-depot-writer-legacy"}
    for _, old_entity in pairs(legacy_writers) do
      -- Read pump behavior config before destruction
      local behavior = old_entity.get_control_behavior()
      local saved_config = nil
      if behavior then
        local cc = behavior.circuit_condition
        local first_signal = cc and cc.first_signal or nil
        local comparator = cc and cc.comparator or ">"
        local constant = cc and cc.constant or 0

        if behavior.circuit_enable_disable and comparator == "=" then
          -- Scan/limit mode (requester/buffer depots)
          saved_config = {
            use_as_limit = true,
            set_recipe = behavior.set_filter or false
          }
        elseif behavior.circuit_enable_disable and first_signal then
          -- Condition mode (non-requester depots)
          saved_config = {
            condition_signal = first_signal,
            condition_comparator = comparator,
            condition_constant = constant
          }
        end
      end

      -- Save wire connections (to other entities)
      local wire_targets = {}
      for _, wire_id in pairs({defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green}) do
        local connector = old_entity.get_wire_connector(wire_id)
        if connector then
          for _, connection in pairs(connector.connections) do
            table.insert(wire_targets, {
              wire_id = wire_id,
              target_entity = connection.target.owner,
              target_wire_id = connection.target.wire_connector_id
            })
          end
        end
      end

      -- Save entity properties
      local pos = old_entity.position
      local dir = old_entity.direction
      local force = old_entity.force

      -- Destroy old pump
      old_entity.destroy()

      -- Create new constant-combinator
      local new_entity = surface.create_entity{
        name = "transport-depot-writer",
        position = pos,
        direction = dir,
        force = force,
        raise_built = true
      }

      if new_entity then
        -- Reconnect wires
        for _, wt in pairs(wire_targets) do
          if wt.target_entity and wt.target_entity.valid then
            local src = new_entity.get_wire_connector(wt.wire_id)
            local dst = wt.target_entity.get_wire_connector(wt.target_wire_id)
            if src and dst then
              src.connect_to(dst)
            end
          end
        end

        -- Store config
        if saved_config then
          storage.writer_config[new_entity.unit_number] = saved_config
        end
      end
    end
  end

  -- ===== Filtered reader migration: road-network-reader-filtered → transport-depot-reader mode=3 (2.0.50) =====
  storage.reader_config = storage.reader_config or {}

  local depot_data = storage.transport_depots
  if not depot_data then return end

  if not depot_data.local_reader_migrated then
    depot_data.local_reader_migrated = true

    -- Track which entities we converted so the surface scan doesn't double-count
    local converted = {}

    for _, depot in pairs(depot_data.depots) do
      if depot.local_reader and depot.local_reader.valid then
        local old = depot.local_reader
        converted[old.unit_number] = true

        local pos = old.position
        local dir = old.direction
        local force = old.force
        local surface = old.surface

        -- Save wire connections
        local wire_targets = {}
        for _, wire_id in pairs({defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green}) do
          local connector = old.get_wire_connector(wire_id)
          if connector then
            for _, connection in pairs(connector.connections) do
              table.insert(wire_targets, {
                wire_id = wire_id,
                target_entity = connection.target.owner,
                target_wire_id = connection.target.wire_connector_id
              })
            end
          end
        end

        old.destroy()
        depot.local_reader = nil

        if not (depot.circuit_reader and depot.circuit_reader.valid) then
          -- Convert: create transport-depot-reader with mode=3
          local new_entity = surface.create_entity{
            name = "transport-depot-reader",
            position = pos,
            direction = dir,
            force = force,
            raise_built = true
          }
          if new_entity then
            for _, wt in pairs(wire_targets) do
              if wt.target_entity and wt.target_entity.valid then
                local src = new_entity.get_wire_connector(wt.wire_id)
                local dst = wt.target_entity.get_wire_connector(wt.target_wire_id)
                if src and dst then
                  src.connect_to(dst)
                end
              end
            end
            storage.reader_config[new_entity.unit_number] = {mode = 3}
          end
        else
          -- Depot already has a circuit_reader or doesn't support readers: spill item
          surface.spill_item_stack{position = pos, stack = {name = "transport-depot-reader", count = 1}, force = force}
        end
      else
        depot.local_reader = nil
      end
    end

    -- Clean up any unattached road-network-reader-filtered entities
    for _, surface in pairs(game.surfaces) do
      local leftovers = surface.find_entities_filtered{name = "road-network-reader-filtered"}
      for _, entity in pairs(leftovers) do
        if not converted[entity.unit_number] then
          local pos = entity.position
          local force = entity.force
          entity.destroy()
          surface.spill_item_stack{position = pos, stack = {name = "transport-depot-reader", count = 1}, force = force}
        end
      end
    end
  end

  -- ===== Depot migrations =====

  for k, depot in pairs(depot_data.depots) do
    if depot.entity.valid then

      -- 2.0.50: all depots now support circuit readers
      depot.no_reader = nil

      -- Safeguard: ensure core fields exist (any version)
      if depot.old_contents == nil then
        depot.old_contents = {}
      end
      if depot.to_be_taken == nil and depot.item then
        depot.to_be_taken = {}
      end

      -- 2.0.12: priority system
      if depot.priority == nil then
        depot.priority = shared.default_priority
        depot.base_priority = shared.default_priority
      end

      -- 2.0.28: channel segregation
      if depot.channel == nil then
        depot.channel = shared.default_channel
        depot.base_channel = shared.default_channel
      end

      -- 2.0.13: bot toggle for supply depots
      if depot.allow_bots == nil and depot.assembler then
        depot.allow_bots = false
      end

      -- 2.0.7: drone chest decoupled from recipe quality
      if depot.get_drone_inventory and (not depot.drone_chest or not depot.drone_chest.valid) then
        local ql_new = depot.entity.quality and depot.entity.quality.level or 0
        local chest_name = shared.drone_chest_name[ql_new] or "depot-drone-chest"
        local chest = depot.entity.surface.create_entity{
          name = chest_name,
          position = depot.entity.position,
          force = depot.entity.force
        }
        chest.destructible = false
        local chest_inv = chest.get_inventory(defines.inventory.chest)
        for i = 1, #chest_inv do
          chest_inv.set_filter(i, {name = "transport-drone", quality = "normal", comparator = ">="})
        end
        depot.drone_chest = chest
        depot.drone_inventory = nil

        -- Move drones from old assembler input to new chest
        local old_inv = depot.entity.get_inventory(defines.inventory.assembling_machine_input)
        if old_inv then
          for _, item in pairs(old_inv.get_contents()) do
            if item.name == "transport-drone" then
              chest_inv.insert({name = item.name, count = item.count, quality = item.quality})
              old_inv.remove({name = item.name, count = item.count, quality = item.quality})
            end
          end
        end

        -- Reset recipe quality to normal (undo ensure_recipe_quality)
        if depot.entity.type == "assembling-machine" or depot.entity.type == "furnace" then
          local recipe, recipe_quality = depot.entity.get_recipe()
          if recipe and recipe_quality.name ~= "normal" then
            depot.entity.set_recipe(recipe.name, "normal")
          end
        end
      end

      -- 2.0.9: swap supply-depot-chest to quality-specific prototype
      if depot.assembler and depot.assembler.valid then
        local ql = depot.assembler.quality and depot.assembler.quality.level or 0
        local expected_supply_name
        if depot.allow_bots then
          expected_supply_name = shared.supply_chest_name_logistic[ql] or "supply-depot-chest-logistic"
        else
          expected_supply_name = shared.supply_chest_name[ql] or "supply-depot-chest"
        end
        if depot.entity.name ~= expected_supply_name and shared.supply_chest_name[0] then
          local is_supply = false
          for _, sname in pairs(shared.supply_chest_name) do
            if depot.entity.name == sname then is_supply = true; break end
          end
          if not is_supply then
            for _, sname in pairs(shared.supply_chest_name_logistic) do
              if depot.entity.name == sname then is_supply = true; break end
            end
          end
          if not is_supply and depot.entity.name == "supply-depot-chest" then is_supply = true end
          if is_supply then
            local old_entity = depot.entity
            local old_inv = old_entity.get_output_inventory()
            local items = {}
            for _, item in pairs(old_inv.get_contents()) do
              table.insert(items, {name = item.name, count = item.count, quality = item.quality})
            end
            local pos = old_entity.position
            local force = old_entity.force
            local surface = old_entity.surface
            local old_bar = old_inv.get_bar()
            old_entity.destroy()
            local new_entity = surface.create_entity{
              name = expected_supply_name,
              position = pos,
              force = force
            }
            local new_inv = new_entity.get_output_inventory()
            for _, item in pairs(items) do
              local inserted = new_inv.insert(item)
              if inserted < item.count then
                surface.spill_item_stack{position = pos, stack = {name = item.name, count = item.count - inserted, quality = item.quality}, force = force}
              end
            end
            if old_bar and old_bar <= #new_inv + 1 then
              new_inv.set_bar(old_bar)
            end
            depot.entity = new_entity
            depot_data.depots[k] = nil
            depot.index = tostring(new_entity.unit_number)
            depot_data.depots[depot.index] = depot
            script.register_on_object_destroyed(new_entity)
          end
        end
      end

      -- 2.0.8: swap drone chest to quality-specific prototype
      if depot.drone_chest and depot.drone_chest.valid then
        local ql = 0
        if depot.assembler and depot.assembler.valid then
          ql = depot.assembler.quality and depot.assembler.quality.level or 0
        elseif depot.entity.valid then
          ql = depot.entity.quality and depot.entity.quality.level or 0
        end
        local expected_name = shared.drone_chest_name[ql] or "depot-drone-chest"
        if depot.drone_chest.name ~= expected_name then
          local old_chest = depot.drone_chest
          local old_inv = old_chest.get_inventory(defines.inventory.chest)
          local items = {}
          for _, item in pairs(old_inv.get_contents()) do
            table.insert(items, {name = item.name, count = item.count, quality = item.quality})
          end
          local pos = old_chest.position
          local force = old_chest.force
          local surface = old_chest.surface
          old_chest.destroy()
          local new_chest = surface.create_entity{
            name = expected_name,
            position = pos,
            force = force
          }
          new_chest.destructible = false
          local new_inv = new_chest.get_inventory(defines.inventory.chest)
          for i = 1, #new_inv do
            new_inv.set_filter(i, {name = "transport-drone", quality = "normal", comparator = ">="})
          end
          for _, item in pairs(items) do
            new_inv.insert(item)
          end
          depot.drone_chest = new_chest
          depot.drone_inventory = nil
        end
      end

      -- 2.0.37: custom signals removed, use vanilla signal-P/C/T
      if depot.priority_signal and depot.priority_signal.name == "signal-depot-priority" then
        depot.priority_signal = {type = "virtual", name = "signal-P"}
      end

      -- 2.0.45: supply depot assembler must be minable for Ctrl+X (cut) to work
      if depot.assembler and depot.assembler.valid and not depot.assembler.minable_flag then
        depot.assembler.minable_flag = true
      end

      -- 2.0.31: mining depot visible road connection marker
      if depot.corpse and depot.corpse.valid and depot.corpse.name == "invisible-transport-caution-corpse" then
        local pos = depot.corpse.position
        local surface = depot.corpse.surface
        depot.corpse.destroy()
        local corpse = surface.create_entity{name = "transport-caution-corpse", position = pos}
        corpse.corpse_expires = false
        depot.corpse = corpse
      end

    end
  end

  -- Clean up orphaned caution corpses (e.g. depot removed by disabling another mod)
  local known_corpses = {}
  for k, depot in pairs(depot_data.depots) do
    if depot.corpse and depot.corpse.valid then
      known_corpses[depot.corpse] = true
    end
  end
  for _, surface in pairs(game.surfaces) do
    local corpses = surface.find_entities_filtered{name = {"transport-caution-corpse", "invisible-transport-caution-corpse"}}
    for _, corpse in pairs(corpses) do
      if not known_corpses[corpse] then
        corpse.destroy()
      end
    end
  end

  -- 2.0.12: one-time migration of old default priority 100 → 50
  if not depot_data.priority_default_migrated then
    depot_data.priority_default_migrated = true
    for k, depot in pairs(depot_data.depots) do
      if depot.entity.valid and depot.base_priority == 100 then
        depot.base_priority = shared.default_priority
        depot.priority = shared.default_priority
      end
    end
  end

  -- 2.0.11: one-time refresh of technology effects (speed research rebalance)
  if not depot_data.refresh_techs then
    depot_data.refresh_techs = true
    for k, force in pairs(game.forces) do
      force.reset_technology_effects()
    end
  end

  -- 2.0.15+: auto-research new techs for existing saves
  if not depot_data.tech_tree_migrated_2 then
    depot_data.tech_tree_migrated_2 = true
    for _, force in pairs(game.forces) do
      if force.technologies["transport-system"].researched then
        force.technologies["transport-fluids"].researched = true
        force.technologies["transport-buffering"].researched = true
        force.technologies["transport-logistics"].researched = true
      end
      if force.technologies["transport-buffering"].researched and force.technologies["transport-active-supply"] then
        force.technologies["transport-active-supply"].researched = true
      end
    end
  end

  -- 2.0.51: storage depot logistic -> plain container swap
  -- JSON migration renamed storage-depot-chest -> storage-depot-chest-logistic.
  -- Now swap them to plain containers and initialize new fields.
  if not depot_data.storage_depot_logistic_migrated then
    depot_data.storage_depot_logistic_migrated = true

    local logistic_to_plain = {}
    for ql, name in pairs(shared.storage_chest_name_logistic) do
      logistic_to_plain[name] = shared.storage_chest_name[ql]
    end

    -- Collect depots to migrate first (can't modify table during pairs iteration)
    local to_migrate = {}
    for k, depot in pairs(depot_data.depots) do
      if depot.entity.valid and logistic_to_plain[depot.entity.name] then
        table.insert(to_migrate, {key = k, depot = depot, plain_name = logistic_to_plain[depot.entity.name]})
      end
    end

    for _, entry in ipairs(to_migrate) do
      local depot = entry.depot
      local old_entity = depot.entity
      -- Read storage_filter before destroying logistic container
      local sf = old_entity.storage_filter
      local filter_name = sf and sf.name or nil

      -- Save inventory
      local old_inv = old_entity.get_output_inventory()
      local items = {}
      for _, item in pairs(old_inv.get_contents()) do
        table.insert(items, {name = item.name, count = item.count, quality = item.quality})
      end
      local bar = old_inv.supports_bar() and old_inv.get_bar()

      -- Save wire connections
      local wire_targets = {}
      for conn_id, connector in pairs(old_entity.get_wire_connectors()) do
        wire_targets[conn_id] = {}
        for _, conn in pairs(connector.connections) do
          table.insert(wire_targets[conn_id], conn.target)
        end
      end

      local pos = old_entity.position
      local force = old_entity.force
      local surface = old_entity.surface
      old_entity.destroy()

      local new_entity = surface.create_entity{name = entry.plain_name, position = pos, force = force}

      -- Restore inventory
      local new_inv = new_entity.get_output_inventory()
      for _, item in pairs(items) do
        local inserted = new_inv.insert(item)
        if inserted < item.count then
          surface.spill_item_stack{position = pos, stack = {name = item.name, count = item.count - inserted, quality = item.quality}, force = force}
        end
      end
      if bar and bar <= #new_inv + 1 then new_inv.set_bar(bar) end

      -- Restore wire connections
      for conn_id, targets in pairs(wire_targets) do
        local new_connectors = new_entity.get_wire_connectors()
        local new_conn = new_connectors[conn_id]
        if new_conn then
          for _, target in pairs(targets) do
            new_conn.connect_to(target)
          end
        end
      end

      -- Update depot references
      depot.entity = new_entity
      depot_data.depots[entry.key] = nil
      depot.index = tostring(new_entity.unit_number)
      depot_data.depots[depot.index] = depot
      script.register_on_object_destroyed(new_entity)

      -- Set slot filters from old storage_filter
      depot.storage_filter_item = filter_name
      if filter_name then
        for i = 1, #new_inv do
          new_inv.set_filter(i, {name = filter_name, quality = "normal", comparator = ">="})
        end
      end

      -- Initialize new fields
      depot.fluid_mode = false
      depot.allow_bots = false
    end

    -- Ensure new fields exist for all storage depots (including those already plain)
    for _, depot in pairs(depot_data.depots) do
      if depot.entity.valid then
        if depot.fluid_mode == nil then depot.fluid_mode = false end
      end
    end
  end

  -- ===== Drone migrations =====
  local drone_data = storage.transport_drone
  if not drone_data then return end

  -- Safeguard: ensure riding_players table exists (any version)
  drone_data.riding_players = drone_data.riding_players or {}

  for k, drone in pairs(drone_data.drones) do
    if drone.entity.valid then
      -- 2.0.6: quality support for transport drones
      if not drone.quality then
        drone.quality = drone.entity.quality and drone.entity.quality.name or "normal"
      end
      -- Quality item requests: default requested_quality
      if drone.requested_item and not drone.requested_quality then
        drone.requested_quality = "normal"
      end
    end
  end

  -- Quality item requests: default item_quality for request/buffer depots
  for _, depot in pairs(depot_data.depots) do
    if depot.entity.valid and depot.item and depot.item_quality == nil then
      depot.item_quality = "normal"
    end
  end

  -- Rebuild to_be_taken from active drones (every config change).
  -- Fixes stale reservations left by drones cleaned up without clear_drone_data().
  for _, depot in pairs(depot_data.depots) do
    if depot.entity.valid and depot.to_be_taken then
      depot.to_be_taken = {}
    end
  end
  for _, drone in pairs(drone_data.drones) do
    if drone.entity and drone.entity.valid
       and drone.supply_depot and drone.supply_depot.entity and drone.supply_depot.entity.valid
       and drone.requested_item and drone.requested_count then
      local supply = drone.supply_depot
      if supply.to_be_taken then
        local key = shared.supply_key(drone.requested_item, drone.requested_quality or "normal")
        supply.to_be_taken[key] = (supply.to_be_taken[key] or 0) + drone.requested_count
      end
    end
  end

end

return lib
