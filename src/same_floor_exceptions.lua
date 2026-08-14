local imgui = require('imgui')
local ffi = require('ffi')
local settings = require('settings')
local zones = require('data.zones')

local same_floor_exceptions = {
    show_window = { false }
}

local exceptionSearchText = { '' }
local exceptionSelectedZone = { 0 }
local sortedZoneList = nil

local function get_zone_name(zid)
    for _, z in pairs(zones) do
        if z.id == zid then return z.en end
    end
    return 'Unknown'
end

function same_floor_exceptions.draw_window()
    if not same_floor_exceptions.show_window[1] then return end

    if not sortedZoneList then
        sortedZoneList = {}
        for _, z in pairs(zones) do
            if z.id and z.id ~= 0 and z.en and z.en ~= '' and z.en ~= 'unknown' then
                table.insert(sortedZoneList, { id = z.id, name = z.en })
            end
        end
        table.sort(sortedZoneList, function (a, b) return a.name < b.name end)
    end

    if imgui.Begin(ICON_FA_SHIELD_HALVED .. ' Same floor exceptions', same_floor_exceptions.show_window, ImGuiWindowFlags_AlwaysAutoResize) then
        -- Combo
        local comboPreview = 'Select zone...'
        for _, z in ipairs(sortedZoneList) do
            if z.id == exceptionSelectedZone[1] then
                comboPreview = z.name
                break
            end
        end

        if imgui.BeginCombo('##ExceptionZone', comboPreview) then
            imgui.SetNextItemWidth(-1)
            imgui.InputText('##SearchException', exceptionSearchText, 256)
            local filter = string.lower(exceptionSearchText[1])
            imgui.Separator()

            for _, z in ipairs(sortedZoneList) do
                if filter == '' or string.find(string.lower(z.name), filter, 1, true) then
                    if imgui.Selectable(z.name, exceptionSelectedZone[1] == z.id) then
                        exceptionSelectedZone[1] = z.id
                    end
                end
            end
            imgui.EndCombo()
        end

        imgui.SameLine()
        if imgui.Button('Add') then
            if exceptionSelectedZone[1] ~= 0 then
                boussole.config.sameFloorExceptions[exceptionSelectedZone[1]] = { npc = true, mob = true }
                settings.save()
            end
        end

        imgui.Separator()

        -- Table
        if imgui.BeginTable('exceptionsTable', 4, bit.bor(ImGuiTableFlags_Borders, ImGuiTableFlags_RowBg)) then
            imgui.TableSetupColumn('Zone name', ImGuiTableColumnFlags_WidthStretch)
            imgui.TableSetupColumn('NPC')
            imgui.TableSetupColumn('Mob')
            imgui.TableSetupColumn('Action')
            imgui.TableHeadersRow()

            local toRemove = nil

            if boussole.config.sameFloorExceptions then
                for zoneId, flags in pairs(boussole.config.sameFloorExceptions) do
                    imgui.TableNextRow()

                    -- Zone name
                    imgui.TableNextColumn()
                    imgui.Text(get_zone_name(zoneId))

                    -- NPC
                    imgui.TableNextColumn()
                    local npcState = { flags.npc }
                    if imgui.Checkbox('##npc' .. tostring(zoneId), npcState) then
                        flags.npc = npcState[1]
                        settings.save()
                    end

                    -- Mob
                    imgui.TableNextColumn()
                    local mobState = { flags.mob }
                    if imgui.Checkbox('##mob' .. tostring(zoneId), mobState) then
                        flags.mob = mobState[1]
                        settings.save()
                    end

                    -- Action
                    imgui.TableNextColumn()
                    if imgui.Button(ICON_FA_TRASH_CAN .. '##del' .. tostring(zoneId)) then
                        toRemove = zoneId
                    end
                end
            end

            if toRemove then
                boussole.config.sameFloorExceptions[toRemove] = nil
                settings.save()
            end

            imgui.EndTable()
        end
    end
    imgui.End()
end

return same_floor_exceptions
