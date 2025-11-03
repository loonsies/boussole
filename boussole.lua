addon.name = 'boussole'
addon.version = '0.01'
addon.author = 'looney'
addon.desc = 'Replacement for in-game map with additional features.'
addon.link = 'https://github.com/loonsies/boussole'

require 'common'

local chat = require('chat')
local settings = require('settings')
local commands = require('src/commands')
local config = require('src/config')
local ui = require('src/ui')
--local packets = require('src/packets')
local map = require('src/map')
local warp_points = require('src/warp_points')

boussole = {
    config = {},
    visible = { false },
    last_floor_id = nil,
    last_floor_check_time = 0,
}

ashita.events.register('load', 'load_cb', function ()
    map.find_map_table()
    map.init_floor_function()
    boussole.config = config.load()

    -- Initialize warp point data
    warp_points.init()

    ui.restore_view_state()

    settings.register('settings', 'settings_update_cb', function (newConfig)
        boussole.config = newConfig
        ui.restore_view_state()
    end)

    ashita.tasks.once(1, function ()
        local mapData, err = map.load_current_map_dat()
        if mapData then
            ui.load_map_texture()
            -- Store initial floor ID
            local x, y, z = map.get_player_position()
            if x then
                local floor_id = map.get_floor_id(x, y, z)
                if floor_id then
                    boussole.last_floor_id = floor_id
                end
            end
        else
            print(chat.header(addon.name):append(chat.warning(string.format('No map available for this floor: %s', tostring(err)))))
            map.clear_map_cache()
            ui.load_nomap_texture()
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
        if x then
            local current_floor_id = map.get_floor_id(x, y, z)
            if current_floor_id and boussole.last_floor_id and current_floor_id ~= boussole.last_floor_id then
                -- Floor changed, reload map
                boussole.last_floor_id = current_floor_id
                local mapData, err = map.load_current_map_dat()
                if mapData then
                    ui.load_map_texture()
                else
                    print(chat.header(addon.name):append(chat.warning(string.format('No map available for this floor: %s', tostring(err)))))
                    map.clear_map_cache()
                    ui.load_nomap_texture()
                end
            elseif current_floor_id then
                boussole.last_floor_id = current_floor_id
            end
        end
    end

    ui.update()
end)

ashita.events.register('mouse', 'mouse_cb', function (e)
    -- Only block mouse events if our window is visible, focused, and mouse is over it
    if boussole.visible[1] and ui.window_focused and ui.is_over_map_area() then
        if e.message == 513 then
            e.blocked = true
            return
        end
    end
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
                ui.load_map_texture()
                -- Update floor ID after zone change
                local x, y, z = map.get_player_position()
                if x then
                    local floor_id = map.get_floor_id(x, y, z)
                    if floor_id then
                        boussole.last_floor_id = floor_id
                    end
                end
            else
                print(chat.header(addon.name):append(chat.warning(string.format('No map available for this floor: %s', tostring(err)))))
                map.clear_map_cache()
                ui.load_nomap_texture()
                boussole.last_floor_id = nil
            end
        end)
    end
end)
