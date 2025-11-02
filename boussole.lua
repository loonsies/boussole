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
            ui.load_map_texture()
        else
            print(chat.header(addon.name):append(chat.error(string.format('Failed to load map data: %s', tostring(err)))))
        end
    end)
end)

ashita.events.register('unload', 'unload_cb', function ()
    settings.save()
end)

ashita.events.register('d3d_present', 'd3d_present_cb', function ()
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
            return
        end

        -- Zone change detected - load new map data
        ashita.tasks.once(1, function ()
            local mapData, err = map.load_current_map_dat()
            if mapData then
                ui.load_map_texture()
            else
                print(chat.header(addon.name):append(chat.error(string.format('Failed to load map data: %s', tostring(err)))))
            end
        end)
    end
end)
