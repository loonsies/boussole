addon.name = 'boussole'
addon.version = '0.01'
addon.author = 'looney'
addon.desc = 'Replacement for in-game map with additional features.'
addon.link = 'https://github.com/loonsies/boussole'

require 'common'

local chat = require('chat')
local settings = require('settings')
local commands = require('src.commands')
local config = require('src.config')
local ui = require('src.ui')
--local packets = require('src.packets')
local map = require('src.map')
local texture = require('src.texture')
local warp_points = require('src.warp_points')

boussole = {
    config = {},
    visible = { false },
    last_floor_id = nil,
    last_floor_check_time = 0,
    manualMapReload = { false },
    zoneSearch = { '' },
    manualZoneId = { 0 },
    manualFloorId = { 0 },
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
    }
}

ashita.events.register('load', 'load_cb', function ()
    map.find_map_table()
    map.init_floor_function()
    boussole.config = config.load()

    -- Initialize warp point data
    warp_points.init()

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

            -- Set manual zone selection to current zone
            local currentZone = map.get_player_zone()
            if currentZone then
                boussole.manualZoneId[1] = currentZone
            end
        else
            print(chat.header(addon.name):append(chat.warning(string.format('No map available for this floor: %s', tostring(err)))))
            map.clear_map_cache()
            texture.load_and_set(ui, nil, chat, addon.name)
        end
    end)
end)

ashita.events.register('unload', 'unload_cb', function ()
    ui.save_view_state()
    settings.save()
end)

ashita.events.register('d3d_present', 'd3d_present_cb', function ()
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
                    print(chat.header(addon.name):append(chat.warning(string.format('No map available for this floor: %s', tostring(err)))))
                    map.clear_map_cache()
                    texture.load_and_set(ui, nil, chat, addon.name)
                end
            elseif current_floor_id then
                boussole.last_floor_id = current_floor_id
            end
        end
    end

    ui.update()
end)

ashita.events.register('command', 'command_cb', function (cmd, nType)
    local args = cmd.command:args()
    if #args ~= 0 then
        commands.handleCommand(args)
    end
end)

ashita.events.register('packet_in', 'packet_in_cb', function (e)
    if (e.id == 0x000A) then
        if (struct.unpack('b', e.data_modified, 0x80 + 0x01) == 1) then
            map.clear_map_cache()
            boussole.last_floor_id = nil
            return
        end

        -- Zone change detected - load new map data
        ashita.tasks.once(1, function ()
            local mapData, err = map.load_current_map_dat()
            if mapData then
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
                local currentZone = map.get_player_zone()
                if currentZone then
                    boussole.manualZoneId[1] = currentZone
                    if boussole.last_floor_id then
                        boussole.manualFloorId[1] = boussole.last_floor_id
                    end
                end
            else
                print(chat.header(addon.name):append(chat.warning(string.format('No map available for this floor: %s', tostring(err)))))
                map.clear_map_cache()
                texture.load_and_set(ui, nil, chat, addon.name)
                boussole.last_floor_id = nil
            end
        end)
    end
end)
