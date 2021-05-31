local mod_gui = require("mod-gui")

-- player_index -> {home -> {unit_number -> positon}, gui -> {frame, list, visible}}
global.players = {}
-- path_request_id -> {request, spidertron}
global.path_requests = {}
-- unit_number -> entity
global.spidertrons = {}

do
  local function create_player_data(player_index)
    global.players[player_index] = {
      gui = { visible = true },
      home = {}
    }
  end

  local function populate_initial_spidertrons()
    for _, surface in pairs(game.surfaces) do
      for _, spidertron in pairs(surface.find_entities_filtered({type = "spider-vehicle"})) do
        if spidertron.valid then
          global.spidertrons[spidertron.unit_number] = spidertron
        end
      end
    end
  end

  script.on_init(function()
    populate_initial_spidertrons()
    for index, _ in pairs(game.players) do
      create_player_data(index)
      update_gui(index)
    end
  end)

  script.on_event(defines.events.on_player_created, function(event)
    create_player_data(event.player_index)
    update_gui(event.player_index)
  end)

  script.on_event(defines.events.on_player_changed_surface, function(event)
    update_gui(event.player_index)
  end)

  script.on_event(defines.events.on_player_removed, function(event)
    global.players[event.player_index] = nil
  end)

  local function update_all_guis()
    for player_index, _ in pairs(game.players) do
      update_gui(player_index)
    end
  end

  -- spidertron built
  do
    local function spidertron_built(spidertron_entity)
      global.spidertrons[spidertron_entity.unit_number] = spidertron_entity
      -- TODO update only specific force/surface for performance
      update_all_guis()
    end
    script.on_event(defines.events.on_built_entity, function(event) spidertron_built(event.created_entity) end, {{filter = "type", type = "spider-vehicle"}})
    script.on_event(defines.events.script_raised_built, function(event) spidertron_built(event.entity) end, {{filter = "type", type = "spider-vehicle"}})
  end

  -- spidertron destroyed
  do
    local function spidertron_destroyed(event)
      global.spidertrons[event.entity.unit_number] = nil
      -- TODO update only specific force/surface for performance
      update_all_guis()
    end
    script.on_event(defines.events.on_entity_died, spidertron_destroyed, {{filter = "type", type = "spider-vehicle"}})
    script.on_event(defines.events.on_player_mined_entity, spidertron_destroyed, {{filter = "type", type = "spider-vehicle"}})
    script.on_event(defines.events.script_raised_destroy, spidertron_destroyed, {{filter = "type", type = "spider-vehicle"}})
  end

  script.on_event(defines.events.on_entity_renamed, function(event)
    -- TODO update only specific force/surface for performance
    update_all_guis()
  end)
end

do
  local function get_or_create_gui(player_index)
    local player_data = global.players[player_index]
    if not player_data.gui.frame or not player_data.gui.frame.valid then
      local frame_flow = mod_gui.get_frame_flow(game.players[player_index])
      local scc_frame = frame_flow.add({type = "frame", caption = {"frame.title"}})
      local scc_spidertron_list = scc_frame.add({type = "flow", direction = "vertical"})
      player_data.gui.frame = scc_frame
      player_data.gui.list = scc_spidertron_list
    end
    return player_data.gui
  end

  local function valid_spidertrons_for_force_and_surface(t, force, surface)
    local function iter(table, key)
      local next_key, spidertron = next(table, key)
      if spidertron == nil then
        return nil
      else
        if spidertron.valid and spidertron.force == force and spidertron.surface == surface then
          return next_key, spidertron
        else
          return iter(table, next_key)
        end
      end
    end
    return iter, t, nil
  end

  function update_gui(player_index)
    local gui = get_or_create_gui(player_index)
    local player = game.players[player_index]

    player.set_shortcut_toggled("scc-toggle-frame", gui.visible)

    gui.list.clear()

    for _, spidertron in valid_spidertrons_for_force_and_surface(global.spidertrons, player.force, player.surface) do
      local spidertron_flow = gui.list.add({type = "flow", direction = "horizontal"})
      spidertron_flow.style.vertical_align = "center"
      spidertron_flow.add({type = "label", caption = spidertron.entity_label or spidertron.prototype.localised_name})
      local filler = spidertron_flow.add({
        type = "empty-widget",
        ignored_by_interaction = true
      })
      filler.style.horizontally_stretchable = true
      local remote_button = spidertron_flow.add({
        type = "sprite-button",
        sprite = "item/spidertron-remote",
        tags = {["scc-action"] = "remote", ["scc-unit-number"] = spidertron.unit_number},
        tooltip = {"tooltip.remote"}
      })
      remote_button.style.height = 28
      remote_button.style.width = 28
      local come_here_button = spidertron_flow.add({
        type = "sprite-button",
        sprite = "entity/character",
        tags = {["scc-action"] = "call", ["scc-unit-number"] = spidertron.unit_number},
        tooltip = {"tooltip.call-to-player"}
      })
      come_here_button.style.height = 28
      come_here_button.style.width = 28

      local home_button = spidertron_flow.add({
        type = "sprite-button",
        sprite = "entity/assembling-machine-3",
        tags = {["scc-action"] = "home", ["scc-unit-number"] = spidertron.unit_number},
        tooltip = {"tooltip.call-to-home"}
      })
      home_button.style.height = 28
      home_button.style.width = 28
    end

    -- Show frame if there's something to show
    gui.frame.visible = gui.visible and (#gui.list.children > 0)
  end
end

do
  local function get_valid_spidertron(wanted_unit_number)
    for _, spidertron in pairs(global.spidertrons) do
      if spidertron.valid and spidertron.unit_number == wanted_unit_number then
        return spidertron
      end
    end
  end

  local function go_to_position(spidertron_entity, target_position)
    local request = {
      bounding_box = {{-0.05, -0.05}, {0.05, 0.05}}, -- size of a spidertron leg
      collision_mask = {"water-tile", "colliding-with-tiles-only"},
      start = spidertron_entity.position,
      goal = target_position,
      force = spidertron_entity.force,
      pathfinder_flags = {
        prefer_straight_paths = true
      }
    }
    local path_request_id = spidertron_entity.surface.request_path(request)
    global.path_requests[path_request_id] = { spidertron = spidertron_entity, request = request }
  end

  script.on_event(defines.events.on_gui_click, function(event)
    local action = event.element.tags["scc-action"]
    if not action then
      return
    end

    local player = game.players[event.player_index]
    if not player or not player.valid then
      return
    end

    local spidertron = get_valid_spidertron(event.element.tags["scc-unit-number"])
    if not spidertron then
      return
    end

    if action == "remote" then
      local cursor = player.cursor_stack
      if not (cursor and cursor.valid) then
        player.create_local_flying_text({
          text = {"error.not-available-in-spectator-mode"},
          create_at_cursor = true
        })
      elseif cursor.valid_for_read then -- hand is not empty
        player.create_local_flying_text({
          text = {"error.clear-cursor"},
          create_at_cursor = true
        })
      else
        cursor.set_stack({name="scc-spidertron-remote"})
        cursor.connected_entity = spidertron
      end
    elseif action == "call" then
      go_to_position(spidertron, player.position)
    elseif action == "home" then
      if event.shift then
        local cursor = player.cursor_stack
        if not (cursor and cursor.valid) then
          player.create_local_flying_text({
            text = {"error.not-available-in-spectator-mode"},
            create_at_cursor = true
          })
        elseif cursor.valid_for_read then -- hand is not empty
          player.create_local_flying_text({
            text = {"error.clear-cursor"},
            create_at_cursor = true
          })
        else
          global.players[event.player_index].setting_home_for = spidertron
          cursor.set_stack({name="scc-set-home-tool"})
        end
      else
        local home_position = global.players[event.player_index].home[spidertron.unit_number]
        if home_position then
          go_to_position(spidertron, home_position)
        else
          player.create_local_flying_text({
            text = {"error.no-home-set", spidertron.entity_label or spidertron.prototype.localised_name},
            create_at_cursor = true
          })
        end
      end
    end
  end)
end

do
  local function deduplicate_path(start, path)
    local previous_position = start
    local deduped_path = {}
    for _, waypoint in pairs(path) do
      local position = waypoint.position
      local dx = math.abs(position.x - previous_position.x)
      local dy = math.abs(position.y - previous_position.y)
      if not (dx == 0 or dy == 0 or dx == dy) then
        table.insert(deduped_path, previous_position)
        previous_position = position
      end
    end
    table.insert(deduped_path, path[#path].position)
    return deduped_path
  end

  script.on_event(defines.events.on_script_path_request_finished, function(event)
    local path_request = global.path_requests[event.id]

    if not path_request then
      return
    else
      global.path_requests[event.id] = nil
    end

    if not event.path and event.try_again_later then
      local new_request_id = path_request.spidertron.surface.request_path(path_request.request)
      global.path_requests[new_request_id] = path_request
    else
      local spidertron = path_request.spidertron
      if event.path then
        spidertron.autopilot_destination = nil

        local deduped_path = deduplicate_path(spidertron.position, event.path)
        for _, position in pairs(deduped_path) do
          spidertron.add_autopilot_destination(position)
        end
      else
        game.print({"error.no-path-found", spidertron.entity_label or spidertron.prototype.localised_name})
      end
    end
  end)
end

do
  script.on_event(defines.events.on_player_selected_area, function(event)
    local spidertron = global.players[event.player_index].setting_home_for
    if spidertron then
      local center =
        { x = (event.area.left_top.x + event.area.right_bottom.x) / 2
        , y = (event.area.left_top.y + event.area.right_bottom.y) / 2
        }
      global.players[event.player_index].home[spidertron.unit_number] = center
      global.players[event.player_index].setting_home_for = nil
      local player = game.players[event.player_index]
      player.cursor_stack.clear()
      local spidertron_name = spidertron.entity_label or spidertron.prototype.localised_name
      player.create_local_flying_text({
        text = {"feedback.new-home-set", spidertron_name},
        create_at_cursor = true
      })
    end
  end)
end

do
  local function toggle_frame(event)
    local player_data = global.players[event.player_index]
    player_data.gui.visible = not player_data.gui.visible
    local player = game.players[event.player_index]
    update_gui(event.player_index)
  end

  script.on_event("scc-toggle-frame", toggle_frame)
  script.on_event(defines.events.on_lua_shortcut, function(event)
    if event.prototype_name == "scc-toggle-frame" then
      toggle_frame(event)
    end
  end)
end
