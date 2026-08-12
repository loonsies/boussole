local imgui = require('imgui')
local ffi = require('ffi')
local settings = require('settings')
local map = require('src.map')
local zones = require('data.zones')

local map_redirects = {
    show_window = { false }
}

local sourceSearchText = { '' }
local targetSearchText = { '' }
local sortedZoneList = nil

local function get_zone_name(zid)
    for _, z in pairs(zones) do
        if z.id == zid then return z.en end
    end
    return 'Unknown'
end

function map_redirects.draw_window()
    if not map_redirects.show_window[1] then return end

    if not sortedZoneList then
        sortedZoneList = {}
        for _, z in pairs(zones) do
            if z.id and z.id ~= 0 and z.en and z.en ~= '' and z.en ~= 'unknown' then
                table.insert(sortedZoneList, { id = z.id, name = z.en })
            end
        end
        table.sort(sortedZoneList, function (a, b) return a.name < b.name end)
    end

    imgui.SetNextWindowSize({ 350, 450 }, ImGuiCond_FirstUseEver)
    if imgui.Begin(ICON_FA_ROUTE .. ' Map redirects editor', map_redirects.show_window) then
        local selZoneId = boussole.manualZoneId[1]

        -- Initialize redirect state if needed
        if not boussole.redirectState then
            boussole.redirectState = {
                sourceZone = { selZoneId or 0 },
                sourceFloor = { boussole.manualFloorId[1] or 0 },
                targetZone = { 0 },
                targetFloor = { 0 },
                offsetX = { 0 },
                offsetY = { 0 },
                editingKey = nil
            }
        end

        -- Determine if we're in editing mode
        local isEditing = boussole.redirectState.editingKey ~= nil

        -- Helpers
        local function draw_zone_combo(label, searchState, selectedZoneState)
            local comboPreview = 'Select zone...'
            for _, z in ipairs(sortedZoneList) do
                if z.id == selectedZoneState[1] then
                    comboPreview = z.name
                    break
                end
            end

            local filter = string.lower(ffi.string(searchState[1]))
            imgui.SetNextItemWidth(-50)
            if imgui.BeginCombo(label, comboPreview) then
                imgui.SetNextItemWidth(-1)
                imgui.InputText('##Search' .. label, searchState, 256)
                filter = string.lower(ffi.string(searchState[1]))
                imgui.Separator()

                if imgui.BeginChild('##List' .. label, { 0, 150 }) then
                    for _, z in ipairs(sortedZoneList) do
                        if filter == '' or string.find(string.lower(z.name), filter, 1, true) then
                            if imgui.Selectable(z.name, selectedZoneState[1] == z.id) then
                                selectedZoneState[1] = z.id
                            end
                        end
                    end
                end
                imgui.EndChild()
                imgui.EndCombo()
            end
        end

        local function draw_floor_combo(label, zoneId, selectedFloorState)
            local floors = map.get_floors_for_zone(zoneId)
            local comboPreview = tostring(selectedFloorState[1])
            if floors then
                for _, fid in ipairs(floors) do
                    if fid == selectedFloorState[1] then
                        comboPreview = map.get_floor_name(zoneId, fid)
                        break
                    end
                end
            end

            imgui.SetNextItemWidth(-50)
            if imgui.BeginCombo(label, comboPreview) then
                if floors then
                    for _, fid in ipairs(floors) do
                        local fName = map.get_floor_name(zoneId, fid)
                        if imgui.Selectable(fName, selectedFloorState[1] == fid) then
                            selectedFloorState[1] = fid
                        end
                    end
                else
                    if imgui.Selectable('0', selectedFloorState[1] == 0) then
                        selectedFloorState[1] = 0
                    end
                end
                imgui.EndCombo()
            end
        end

        imgui.Text('Source')
        draw_zone_combo('Zone##srcZone', sourceSearchText, boussole.redirectState.sourceZone)
        draw_floor_combo('Floor##srcFloor', boussole.redirectState.sourceZone[1], boussole.redirectState.sourceFloor)

        imgui.Separator()
        imgui.Text('Target')
        draw_zone_combo('Zone##tgtZone', targetSearchText, boussole.redirectState.targetZone)
        draw_floor_combo('Floor##tgtFloor', boussole.redirectState.targetZone[1], boussole.redirectState.targetFloor)

        imgui.Separator()
        imgui.Text('Offset')
        imgui.SetNextItemWidth(-50)
        imgui.InputInt('X##off', boussole.redirectState.offsetX)
        imgui.SetNextItemWidth(-50)
        imgui.InputInt('Y##off', boussole.redirectState.offsetY)

        local buttonLabel = isEditing and ICON_FA_FLOPPY_DISK .. ' Save changes' or ICON_FA_CIRCLE_PLUS .. ' Add redirect'
        if imgui.Button(buttonLabel, { -1, 0 }) then
            -- If editing, remove the old redirect first
            if isEditing then
                local oldKey = boussole.redirectState.editingKey
                if oldKey then
                    local oldSrcZone, oldSrcFloor = oldKey:match('(%d+)_(%d+)')
                    if oldSrcZone and oldSrcFloor then
                        map.remove_redirect(tonumber(oldSrcZone), tonumber(oldSrcFloor))
                    end
                end
            end

            -- Add the new/updated redirect
            map.add_redirect(
                boussole.redirectState.sourceZone[1],
                boussole.redirectState.sourceFloor[1],
                boussole.redirectState.targetZone[1],
                boussole.redirectState.targetFloor[1],
                boussole.redirectState.offsetX[1],
                boussole.redirectState.offsetY[1]
            )
            settings.save()

            -- Reload if we added/modified a redirect for the current map
            if boussole.redirectState.sourceZone[1] == selZoneId and
                boussole.redirectState.sourceFloor[1] == boussole.manualFloorId[1] then
                boussole.manualMapReload[1] = true
            end

            -- Clear editing state
            boussole.redirectState.editingKey = nil
        end

        if isEditing then
            imgui.SameLine()
            if imgui.Button('Cancel', { -1, 0 }) then
                boussole.redirectState.editingKey = nil
                boussole.redirectState.sourceZone[1] = selZoneId or 0
                boussole.redirectState.sourceFloor[1] = boussole.manualFloorId[1] or 0
                boussole.redirectState.targetZone[1] = 0
                boussole.redirectState.targetFloor[1] = 0
                boussole.redirectState.offsetX[1] = 0
                boussole.redirectState.offsetY[1] = 0
            end
        else
            if imgui.Button(ICON_FA_ARROWS_ROTATE .. ' Use current', { -1, 0 }) then
                boussole.redirectState.sourceZone[1] = selZoneId
                boussole.redirectState.sourceFloor[1] = boussole.manualFloorId[1]
            end
        end
        imgui.Spacing()

        -- List of redirects at the bottom
        local _, remainingHeight = imgui.GetContentRegionAvail()
        if imgui.BeginTable('RedirectsTable', 6, bit.bor(ImGuiTableFlags_Borders, ImGuiTableFlags_RowBg, ImGuiTableFlags_ScrollY), { 0, remainingHeight }) then
            imgui.TableSetupScrollFreeze(0, 1) -- Freeze top row
            imgui.TableSetupColumn('Source Zone', ImGuiTableColumnFlags_WidthStretch)
            imgui.TableSetupColumn('Source Floor', ImGuiTableColumnFlags_WidthFixed, 120)
            imgui.TableSetupColumn('Target Zone', ImGuiTableColumnFlags_WidthStretch)
            imgui.TableSetupColumn('Target Floor', ImGuiTableColumnFlags_WidthFixed, 120)
            imgui.TableSetupColumn('Offset', ImGuiTableColumnFlags_WidthFixed, 75)
            imgui.TableSetupColumn('Action', ImGuiTableColumnFlags_WidthFixed, 60)
            imgui.TableHeadersRow()

            local toRemove = nil
            local toEdit = nil

            local sortedRedirects = {}
            for key, redirect in pairs(boussole.config.mapRedirects) do
                local srcZone, srcFloor = key:match('(%d+)_(%d+)')
                srcZone = tonumber(srcZone)
                srcFloor = tonumber(srcFloor)

                if srcZone and srcFloor then
                    table.insert(sortedRedirects, {
                        key = key,
                        redirect = redirect,
                        srcZone = srcZone,
                        srcFloor = srcFloor,
                        srcName = get_zone_name(srcZone)
                    })
                end
            end

            table.sort(sortedRedirects, function (a, b)
                if a.srcName == b.srcName then
                    return a.srcFloor < b.srcFloor
                end
                return a.srcName < b.srcName
            end)

            for _, item in ipairs(sortedRedirects) do
                local key = item.key
                local redirect = item.redirect
                local srcZone = item.srcZone
                local srcFloor = item.srcFloor
                local isCurrentMap = (srcZone == selZoneId and srcFloor == boussole.manualFloorId[1])
                local isEditingThis = (boussole.redirectState.editingKey == key)

                imgui.TableNextRow()
                imgui.PushID(key)

                imgui.TableNextColumn()
                local srcZoneStr = get_zone_name(srcZone)
                if isEditingThis then
                    imgui.TextColored({ 1.0, 0.6, 0.2, 1.0 }, srcZoneStr .. ' (Editing)')
                elseif isCurrentMap then
                    imgui.TextColored({ 0.2, 1.0, 0.5, 1.0 }, srcZoneStr .. ' (Current)')
                else
                    imgui.Text(srcZoneStr)
                end

                imgui.TableNextColumn()
                imgui.Text(tostring(srcFloor))

                imgui.TableNextColumn()
                imgui.Text(get_zone_name(redirect.targetZone))

                imgui.TableNextColumn()
                imgui.Text(tostring(redirect.targetFloor))

                imgui.TableNextColumn()
                imgui.Text(string.format('%d, %d', redirect.offsetX, redirect.offsetY))

                imgui.TableNextColumn()
                if imgui.Button(ICON_FA_PEN_TO_SQUARE .. '##edit') then
                    toEdit = { key, srcZone, srcFloor, redirect }
                end
                imgui.SameLine()
                if imgui.Button(ICON_FA_TRASH_CAN .. '##del') then
                    toRemove = { srcZone, srcFloor }
                end

                imgui.PopID()
            end

            -- Handle edit selection
            if toEdit then
                boussole.redirectState.editingKey = toEdit[1]
                boussole.redirectState.sourceZone[1] = toEdit[2]
                boussole.redirectState.sourceFloor[1] = toEdit[3]
                boussole.redirectState.targetZone[1] = toEdit[4].targetZone
                boussole.redirectState.targetFloor[1] = toEdit[4].targetFloor
                boussole.redirectState.offsetX[1] = toEdit[4].offsetX
                boussole.redirectState.offsetY[1] = toEdit[4].offsetY
            end

            -- Handle removal
            if toRemove then
                -- Clear editing state if we're deleting the edited item
                if boussole.redirectState.editingKey == string.format('%d_%d', toRemove[1], toRemove[2]) then
                    boussole.redirectState.editingKey = nil
                end

                map.remove_redirect(toRemove[1], toRemove[2])
                settings.save()
                -- Reload if we removed the current map's redirect
                if toRemove[1] == selZoneId and toRemove[2] == boussole.manualFloorId[1] then
                    boussole.manualMapReload[1] = true
                end
            end

            imgui.EndTable()
        end
    end
    imgui.End()
end

return map_redirects
