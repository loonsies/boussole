local settings = require('settings')

local commands = {}

function commands.handleCommand(args)
    local command = string.lower(args[1])

    if command == '/boussole' then
        if #args == 1 then
            return commands.handleToggleUi()
        elseif #args == 2 then
            local arg = string.lower(args[2])

            if arg == 'show' then
                return commands.handleShowUi()
            elseif arg == 'hide' then
                return commands.handleHideUi()
            elseif arg == 'genfloors' then
                return commands.handleGenerateFloors()
            end
        end
    end

    return false
end

function commands.handleToggleUi()
    boussole.visible[1] = not boussole.visible[1]
    settings.save()
    return true
end

function commands.handleShowUi()
    boussole.visible[1] = true
    settings.save()
    return true
end

function commands.handleHideUi()
    boussole.visible[1] = false
    settings.save()
    return true
end

function commands.handleGenerateFloors()
    local path = AshitaCore:GetInstallPath() .. 'addons\\boussole\\data\\generate_zonesFloors.lua'
    dofile(path)
    return true
end

return commands
