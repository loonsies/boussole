addon.name = 'boussole'
addon.version = '1.04'
addon.author = 'looney'
addon.desc = 'Replacement for in-game map with additional features.'
addon.link = 'https://github.com/loonsies/boussole'

require 'common'

local chat = require('chat')
local settings = require('settings')
local commands = require('src.commands')
local config = require('src.config')
local ui = require('src.ui')
local map = require('src.map')
local texture = require('src.texture')
local warp_points = require('src.warp_points')
local tracker = require('src.tracker')
local map_data_editor = require('src.map_data_editor')
local custom_points = require('src.overlays.custom_points')
local minimap = require('src.minimap')

boussole = {
    config = {},
    visible = { false },
    last_floor_id = nil,
    last_floor_check_time = 0,
    manualMapReload = { false },
    zoneSearch = { '' },
    manualZoneId = { 0 },
    manualFloorId = { 0 },
    last_sub_zone_id = 0,
    dropdownOpened = false,
    panelHovered = false,
    redirectState = {
        sourceZone = { 0 },
        sourceFloor = { 0 },
        targetZone = { 0 },
        targetFloor = { 0 },
        offsetX = { 0 },
        offsetY = { 0 },
        editingKey = nil
    },
    trackerSearch = { '' },
    trackerSearchResults = {},
    trackerSelection = -1,
    trackerSelections = {},
    trackedSelection = -1,
    minimapResetZoom = false,
    zoning = false,
    preZoneVisible = false,
    preZoneMinimapVisible = false,
    mapDataEditor = {
        visible = { false },
        selectedZoneId = 0,
        selectedFloorId = nil,
        edit = {},
        lastCopiedAt = 0,
        addFloor = {
            id = { 0 },
            subZoneName = { '' },
            copyFromSelected = { true },
            error = ''
        },
        deleteFloor = {
            error = ''
        },
        drawBorders3D = { true },
        drawBorders2D = { true }
    }
}

ashita.events.register('load', 'load_cb', function ()
    map.find_map_table()
    map.init_floor_function()
    boussole.config = config.load()

    -- Load per-character custom points, then migrate settings-based data into JSON
    custom_points.load_custom_points()
    custom_points.migrate_from_config(boussole.config)

    -- Initialize warp point data
    warp_points.init()

    -- Load tracker profile data
    tracker.load_tracker_data()

    settings.register('settings', 'settings_update_cb', function (newConfig)
        boussole.config = newConfig
    end)

    ashita.tasks.once(1, function ()
        local mapData, err = map.load_current_map_dat()
        if mapData then
            texture.load_and_set(ui, mapData, chat, addon.name)

            -- Store initial floor ID and set manual selections to current zone/floor
            local x, y, z = map.get_player_position()
            if x ~= nil and y ~= nil and z ~= nil then
                local floor_id = map.get_floor_id(x, y, z)
                if floor_id then
                    boussole.last_floor_id = floor_id
                    boussole.manualFloorId[1] = floor_id
                end
            end

            -- Set manual zone selection to current zone / subzone from memory
            local currentZone, currentSubZone = tracker.get_current_zone_and_subzone()
            if not currentZone then
                currentZone = map.get_player_zone()
            end

            if currentZone then
                boussole.manualZoneId[1] = currentZone
            end

            boussole.last_sub_zone_id = currentSubZone or 0

            -- Load zone entities for tracker
            if boussole.config.enableTracker[1] and currentZone then
                tracker.load_zone_entities(currentZone, currentSubZone)

                if boussole.config.lastLoadedTrackerProfile and boussole.config.lastLoadedTrackerProfile ~= '' then
                    tracker.load_profile(boussole.config.lastLoadedTrackerProfile)
                    boussole.trackedSearchResults = nil
                end
            end
        else
            map.clear_map_cache()
            texture.load_and_set(ui, nil, chat, addon.name)
        end
    end)
end)

ashita.events.register('unload', 'unload_cb', function ()
    ui.save_view_state()
    tracker.save_tracker_data()
    settings.save()
end)

ashita.events.register('d3d_present', 'd3d_present_cb', function ()
    -- Process tracker packet queue
    if boussole.config.enableTracker[1] then
        tracker.process_packet_queue()
        tracker.process_timeouts()
    end

    -- Check for floor changes every 1 second
    local current_time = os.clock()
    if current_time - boussole.last_floor_check_time >= 1.0 then
        boussole.last_floor_check_time = current_time

        local x, y, z = map.get_player_position()
        if x ~= nil and y ~= nil and z ~= nil then
            local current_floor_id = map.get_floor_id(x, y, z)
            if current_floor_id and boussole.last_floor_id and current_floor_id ~= boussole.last_floor_id then
                -- Floor changed, reload map
                boussole.last_floor_id = current_floor_id
                local mapData, err = map.load_current_map_dat()
                if mapData then
                    texture.load_and_set(ui, mapData, chat, addon.name)
                else
                    map.clear_map_cache()
                    texture.load_and_set(ui, nil, chat, addon.name)
                end
            elseif current_floor_id then
                boussole.last_floor_id = current_floor_id
            end
        end
    end

    ui.update()
    minimap.update()
end)

ashita.events.register('d3d_beginscene', 'd3d_beginscene_cb', function ()
    map_data_editor.draw_world_bounds()
end)

ashita.events.register('command', 'command_cb', function (cmd, nType)
    local args = cmd.command:args()
    if #args ~= 0 then
        commands.handleCommand(args)
    end
end)

ashita.events.register('packet_in', 'packet_in_cb', function (e)
    if (e.id == 0x000A) then
        if boussole.zoning then
            boussole.visible[1]               = boussole.preZoneVisible
            boussole.config.minimapVisible[1] = boussole.preZoneMinimapVisible
            boussole.zoning                   = false
        end

        if (struct.unpack('b', e.data_modified, 0x80 + 0x01) == 1) then
            map.clear_map_cache()
            boussole.last_floor_id = nil
            return
        end

        -- Zone change detected - load new map data
        -- Parse zone and subzone from the zone change packet (matches ScentHound offsets)
        local newZone = struct.unpack('H', e.data, 0x30 + 1)
        local newSubZone = struct.unpack('H', e.data, 0x9E + 1)
        boussole.last_sub_zone_id = newSubZone or 0

        ashita.tasks.once(1, function ()
            local mapData, err = map.load_current_map_dat()
            if mapData then
                tracker.handle_zone_change()
                texture.load_and_set(ui, mapData, chat, addon.name)

                -- Update floor ID after zone change
                local x, y, z = map.get_player_position()
                if x ~= nil and y ~= nil and z ~= nil then
                    local floor_id = map.get_floor_id(x, y, z)
                    if floor_id then
                        boussole.last_floor_id = floor_id
                    end
                end

                -- Update manual zone and floor selections to current after zone change
                if newZone then
                    boussole.manualZoneId[1] = newZone
                    if boussole.last_floor_id then
                        boussole.manualFloorId[1] = boussole.last_floor_id
                    end
                end

                -- Load zone entities for tracker using proper subzone
                if boussole.config.enableTracker[1] and newZone then
                    tracker.load_zone_entities(newZone, newSubZone)
                    boussole.trackerSearchResults = {}
                    boussole.trackerSearch = { '' }

                    -- Reload the last selected profile if one was loaded
                    if boussole.config.lastLoadedTrackerProfile and boussole.config.lastLoadedTrackerProfile ~= '' then
                        tracker.load_profile(boussole.config.lastLoadedTrackerProfile)
                    end
                end
            else
                map.clear_map_cache()
                texture.load_and_set(ui, nil, chat, addon.name)
                boussole.last_floor_id = nil
            end
        end)
    end

    if e.id == 0x000B then
        boussole.preZoneVisible           = boussole.visible[1]
        boussole.preZoneMinimapVisible    = boussole.config.minimapVisible[1]
        boussole.visible[1]               = false
        boussole.config.minimapVisible[1] = false
        boussole.zoning                   = true
    end

    -- Handle entity update packets for tracker
    if boussole.config.enableTracker[1] then
        if e.id == 0x00E then
            tracker.handle_entity_update(e)

            -- Cache position data if present
            if bit.band(struct.unpack('B', e.data, 0x0A + 1), 0x01) == 0x01 then
                local index = struct.unpack('H', e.data, 0x08 + 1)
                local x = struct.unpack('f', e.data, 0x0C + 1)
                local y = struct.unpack('f', e.data, 0x14 + 1)
                local z = struct.unpack('f', e.data, 0x10 + 1)
                tracker.cache_position(index, x, y, z)
            end
        end

        -- Handle position packet (0xF5)
        if e.id == 0xF5 then
            local index = struct.unpack('H', e.data, 0x12 + 1)
            local x = struct.unpack('f', e.data, 0x04 + 1)
            local y = struct.unpack('f', e.data, 0x0C + 1)
            local z = struct.unpack('f', e.data, 0x08 + 1)
            tracker.cache_position(index, x, y, z)
        end
    end
end)
