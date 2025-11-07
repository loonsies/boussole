local panel = {}
local map = require('src.map')
local regions = require('data.regions')
local zones = require('data.zones')
local export = require('src.export')
local imgui = require('imgui')
local settings = require('settings')
local chat = require('chat')

function panel.draw(windowPosX, windowPosY, contentMinX, contentMinY, contentMaxX, contentMaxY)
    local x, y, z = map.get_player_position()
    local currentZone = map.get_player_zone()
    local currentFloor = 0

    if x ~= nil and y ~= nil and z ~= nil then
        currentFloor = map.get_floor_id(x, y, z) or 0
    end

    local currentZoneName = nil
    local resMgr = AshitaCore:GetResourceManager()

    if resMgr then
        currentZoneName = resMgr:GetString('zones.names', currentZone)
    end

    if not currentZoneName then
        for _, r in ipairs(regions) do
            if r.id == currentZone then
                currentZoneName = r.en
                break
            end
        end
    end

    local zoneIds = { currentZone }
    local zoneNames = {}

    if currentZoneName and currentZoneName ~= '' then
        zoneNames = { currentZoneName .. ' (Current)' }
    else
        zoneNames = { currentZoneName }
    end

    local addedZones = {}
    if currentZone then
        addedZones[currentZone] = true
    end

    for _, zone_data in pairs(zones) do
        local zid = zone_data.id
        if zid and zid ~= 0 and not addedZones[zid] then
            local name = zone_data.en
            if name and name ~= '' and name ~= 'unknown' then
                table.insert(zoneIds, zid)
                table.insert(zoneNames, name)
                addedZones[zid] = true
            end
        end
    end

    local filteredZoneIds = {}
    local filteredZoneNames = {}
    local searchText = boussole.zoneSearch[1]:lower()

    if searchText ~= '' then
        for i, name in ipairs(zoneNames) do
            if name:lower():find(searchText, 1, true) then
                table.insert(filteredZoneIds, zoneIds[i])
                table.insert(filteredZoneNames, name)
            end
        end
    else
        filteredZoneIds = zoneIds
        filteredZoneNames = zoneNames
    end

    local selectedZoneName = nil
    for i, zid in ipairs(zoneIds) do
        if boussole.manualZoneId[1] == zid then
            selectedZoneName = zoneNames[i]
            break
        end
    end

    if not selectedZoneName or selectedZoneName == '' then
        selectedZoneName = 'Select Zone'
    end

    local toggleButtonWidth = 20
    local buttonSpacing = 5
    local isPanelVisible = boussole.config.settingsPanelVisible[1]

    -- Calculate positions
    local panelX = windowPosX + contentMaxX - (isPanelVisible and boussole.config.panelWidth[1] or 0)
    local panelY = windowPosY + contentMinY
    local panelHeight = contentMaxY - contentMinY

    local toggleButtonX = isPanelVisible and (panelX - toggleButtonWidth - buttonSpacing) or (windowPosX + contentMaxX - toggleButtonWidth - buttonSpacing)
    local toggleButtonY = panelY + (panelHeight / 2) - 30

    local drawList = imgui.GetWindowDrawList()

    -- Draw toggle button background
    local buttonColor = 0x88444444
    local buttonHoverColor = 0xBB666666
    local buttonTextColor = 0xFFFFFFFF

    -- Check if mouse is over toggle button or panel
    local mousePosX, mousePosY = imgui.GetMousePos()
    local isHoveringButton = mousePosX >= toggleButtonX and mousePosX <= (toggleButtonX + toggleButtonWidth) and
        mousePosY >= toggleButtonY and mousePosY <= (toggleButtonY + 60)

    local isHoveringPanel = isPanelVisible and
        mousePosX >= panelX and mousePosX <= (panelX + boussole.config.panelWidth[1]) and
        mousePosY >= panelY and mousePosY <= (panelY + panelHeight)

    boussole.panelHovered = isHoveringButton or isHoveringPanel

    -- Draw visual button background
    drawList:AddRectFilled(
        { toggleButtonX, toggleButtonY },
        { toggleButtonX + toggleButtonWidth, toggleButtonY + 60 },
        isHoveringButton and buttonHoverColor or buttonColor,
        3.0
    )

    -- Draw toggle button text
    local buttonText = isPanelVisible and '>' or '<'
    local textSizeX, textSizeY = imgui.CalcTextSize(buttonText)
    local textX = toggleButtonX + (toggleButtonWidth - textSizeX) / 2
    local textY = toggleButtonY + (60 - textSizeY) / 2

    drawList:AddText({ textX, textY }, buttonTextColor, buttonText)

    imgui.SetCursorPos({ toggleButtonX - windowPosX, toggleButtonY - windowPosY })
    if imgui.BeginChild('##PanelToggle', { toggleButtonWidth, 60 }, false, bit.bor(ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoBackground)) then
        if imgui.InvisibleButton('##ToggleBtn', { toggleButtonWidth, 60 }) then
            boussole.config.settingsPanelVisible[1] = not isPanelVisible
            settings.save()
        end
    end
    imgui.EndChild()

    -- Draw panel if visible
    if isPanelVisible then
        -- Draw panel background
        drawList:AddRectFilled(
            { panelX, panelY },
            { panelX + boussole.config.panelWidth[1], panelY + panelHeight },
            0xE0222222,
            0.0
        )

        -- Draw panel border
        drawList:AddRect(
            { panelX, panelY },
            { panelX + boussole.config.panelWidth[1], panelY + panelHeight },
            0xFF444444,
            0.0,
            0,
            1.0
        )

        -- Create an invisible window for the panel widgets
        imgui.SetCursorPos({ panelX - windowPosX, panelY - windowPosY })

        if imgui.BeginChild('##Panel', { boussole.config.panelWidth[1], panelHeight }, false, bit.bor(ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_AlwaysUseWindowPadding)) then
            local isBrowsingDifferentMap = (boussole.manualZoneId[1] ~= currentZone) or
                (boussole.manualFloorId[1] ~= currentFloor)

            if isBrowsingDifferentMap then
                imgui.Text('Browse maps')
                imgui.SameLine()
                imgui.SetCursorPosX(imgui.GetCursorPosX() + 5)

                local _, textH = imgui.CalcTextSize('Browse maps')
                imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 0, 0 })
                if imgui.Button('Current', { -1, textH }) then
                    -- Return to current map
                    boussole.manualZoneId[1] = currentZone
                    boussole.manualFloorId[1] = currentFloor
                    boussole.manualMapReload[1] = true
                end
                imgui.PopStyleVar()
            else
                imgui.Text('Browse maps')
            end
            imgui.Spacing()

            imgui.SetNextItemWidth(-1)
            imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 4, 4 })
            local zoneComboOpened = imgui.BeginCombo('##ZoneSelect', selectedZoneName, ImGuiComboFlags_HeightLarge)
            if zoneComboOpened then
                imgui.InputText('##ZoneSearch', boussole.zoneSearch, 256)
                imgui.Separator()

                if imgui.BeginChild('##ZoneList', { 0, 200 }, false, ImGuiWindowFlags_NoBackground) then
                    for i, name in ipairs(filteredZoneNames) do
                        if imgui.Selectable(name, boussole.manualZoneId[1] == filteredZoneIds[i]) then
                            local newZoneId = filteredZoneIds[i]
                            boussole.manualZoneId[1] = newZoneId

                            local firstFloor = 0
                            if newZoneId == currentZone then
                                firstFloor = currentFloor
                            else
                                firstFloor = map.get_first_floor_for_zone(newZoneId)
                            end

                            boussole.manualFloorId[1] = firstFloor
                            boussole.manualMapReload[1] = true
                        end
                    end
                    imgui.EndChild()
                end
                imgui.EndCombo()
            end
            imgui.PopStyleVar()

            local selZoneId = boussole.manualZoneId[1]
            local floorIds = {}
            local floorNames = {}

            if selZoneId == currentZone then
                table.insert(floorIds, currentFloor)
                table.insert(floorNames, string.format('%d (Current)', currentFloor))
            end

            local zonesFloors = map.get_floors_for_zone(selZoneId)
            for _, fid in ipairs(zonesFloors) do
                if fid ~= currentFloor or selZoneId ~= currentZone then
                    table.insert(floorIds, fid)
                    table.insert(floorNames, tostring(fid))
                end
            end

            local selectedFloorIdx = 0
            for i, fid in ipairs(floorIds) do
                if boussole.manualFloorId[1] == fid then
                    selectedFloorIdx = i
                    break
                end
            end

            local floorDisplayName = floorNames[selectedFloorIdx] or 'No floors available'
            imgui.SetNextItemWidth(-1)
            local floorComboOpened = imgui.BeginCombo('##FloorSelect', floorDisplayName)
            if floorComboOpened then
                for i, name in ipairs(floorNames) do
                    if imgui.Selectable(name, selectedFloorIdx == i) then
                        boussole.manualFloorId[1] = floorIds[i]
                        boussole.manualMapReload[1] = true
                    end
                end
                imgui.EndCombo()
            end

            -- Set dropdown state based on whether any dropdown is open
            boussole.dropdownOpened = zoneComboOpened or floorComboOpened

            imgui.Separator()
            imgui.Text('Display options')
            imgui.Spacing()

            if imgui.Checkbox('Homepoints', boussole.config.showHomepoints) then
                settings.save()
            end
            imgui.Spacing()

            if imgui.Checkbox('Survival Guides', boussole.config.showSurvivalGuides) then
                settings.save()
            end
            imgui.Spacing()

            if imgui.Checkbox('Player (me)', boussole.config.showPlayer) then
                settings.save()
            end
            if imgui.Checkbox('Party members', boussole.config.showParty) then
                settings.save()
            end
            if imgui.Checkbox('Alliance members', boussole.config.showAlliance) then
                settings.save()
            end
            imgui.Spacing()

            imgui.Separator()
            imgui.Text('UI Appearance')
            imgui.Spacing()

            imgui.PushItemWidth(100)
            if imgui.InputInt('Panel Width', boussole.config.panelWidth, 10, 50) then
                if boussole.config.panelWidth[1] < 100 then
                    boussole.config.panelWidth[1] = 100
                elseif boussole.config.panelWidth[1] > 400 then
                    boussole.config.panelWidth[1] = 400
                end
                settings.save()
            end
            imgui.PopItemWidth()
            imgui.Spacing()

            imgui.Text('Icon Sizes')
            imgui.PushItemWidth(100)
            if imgui.InputInt('Homepoint##IconSize', boussole.config.iconSizeHomepoint, 1, 5) then
                if boussole.config.iconSizeHomepoint[1] < 2 then
                    boussole.config.iconSizeHomepoint[1] = 2
                elseif boussole.config.iconSizeHomepoint[1] > 20 then
                    boussole.config.iconSizeHomepoint[1] = 20
                end
                settings.save()
            end
            if imgui.InputInt('Survival Guide##IconSize', boussole.config.iconSizeSurvivalGuide, 1, 5) then
                if boussole.config.iconSizeSurvivalGuide[1] < 2 then
                    boussole.config.iconSizeSurvivalGuide[1] = 2
                elseif boussole.config.iconSizeSurvivalGuide[1] > 20 then
                    boussole.config.iconSizeSurvivalGuide[1] = 20
                end
                settings.save()
            end
            if imgui.InputInt('Player##IconSize', boussole.config.iconSizePlayer, 1, 5) then
                if boussole.config.iconSizePlayer[1] < 4 then
                    boussole.config.iconSizePlayer[1] = 4
                elseif boussole.config.iconSizePlayer[1] > 40 then
                    boussole.config.iconSizePlayer[1] = 40
                end
                settings.save()
            end
            if imgui.InputInt('Party##IconSize', boussole.config.iconSizeParty, 1, 5) then
                if boussole.config.iconSizeParty[1] < 4 then
                    boussole.config.iconSizeParty[1] = 4
                elseif boussole.config.iconSizeParty[1] > 40 then
                    boussole.config.iconSizeParty[1] = 40
                end
                settings.save()
            end
            if imgui.InputInt('Alliance##IconSize', boussole.config.iconSizeAlliance, 1, 5) then
                if boussole.config.iconSizeAlliance[1] < 4 then
                    boussole.config.iconSizeAlliance[1] = 4
                elseif boussole.config.iconSizeAlliance[1] > 40 then
                    boussole.config.iconSizeAlliance[1] = 40
                end
                settings.save()
            end
            imgui.PopItemWidth()
            imgui.Spacing()

            -- Colors
            imgui.Text('Colors')
            if imgui.ColorEdit4('Homepoint##Color', boussole.config.colorHomepoint, ImGuiColorEditFlags_NoInputs) then
                settings.save()
            end
            if imgui.ColorEdit4('Survival Guide##Color', boussole.config.colorSurvivalGuide, ImGuiColorEditFlags_NoInputs) then
                settings.save()
            end
            if imgui.ColorEdit4('Player (me)##Color', boussole.config.colorPlayer, ImGuiColorEditFlags_NoInputs) then
                settings.save()
            end
            if imgui.ColorEdit4('Party##Color', boussole.config.colorParty, ImGuiColorEditFlags_NoInputs) then
                settings.save()
            end
            if imgui.ColorEdit4('Alliance##Color', boussole.config.colorAlliance, ImGuiColorEditFlags_NoInputs) then
                settings.save()
            end
            if imgui.ColorEdit4('Info Panel Bg##Color', boussole.config.colorInfoPanelBg, ImGuiColorEditFlags_NoInputs) then
                settings.save()
            end
            imgui.Spacing()

            imgui.Text('Info Panel')
            imgui.PushItemWidth(100)
            if imgui.InputInt('Font Size##InfoPanel', boussole.config.infoPanelFontSize, 1, 2) then
                if boussole.config.infoPanelFontSize[1] < 8 then
                    boussole.config.infoPanelFontSize[1] = 8
                elseif boussole.config.infoPanelFontSize[1] > 24 then
                    boussole.config.infoPanelFontSize[1] = 24
                end
                settings.save()
            end
            imgui.PopItemWidth()
            imgui.Spacing()

            imgui.Separator()
            imgui.Text('Map redirects')
            imgui.Spacing()

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
            local availWidth = imgui.GetContentRegionAvail()
            local labelWidth = 70
            local inputWidth = availWidth - labelWidth

            imgui.Text('Source')
            imgui.SetNextItemWidth(inputWidth)
            if imgui.InputInt('Zone##src', boussole.redirectState.sourceZone, 1, 10, ImGuiInputTextFlags_CharsDecimal) then
                boussole.redirectState.sourceZone[1] = math.max(0, boussole.redirectState.sourceZone[1])
            end
            imgui.SetNextItemWidth(inputWidth)
            if imgui.InputInt('Floor##src', boussole.redirectState.sourceFloor, 1, 10, ImGuiInputTextFlags_CharsDecimal) then
                boussole.redirectState.sourceFloor[1] = math.max(0, boussole.redirectState.sourceFloor[1])
            end
            imgui.Separator()
            imgui.Text('Target')
            imgui.SetNextItemWidth(inputWidth)
            if imgui.InputInt('Zone##tgt', boussole.redirectState.targetZone, 1, 10, ImGuiInputTextFlags_CharsDecimal) then
                boussole.redirectState.targetZone[1] = math.max(0, boussole.redirectState.targetZone[1])
            end
            imgui.SetNextItemWidth(inputWidth)
            if imgui.InputInt('Floor##tgt', boussole.redirectState.targetFloor, 1, 10, ImGuiInputTextFlags_CharsDecimal) then
                boussole.redirectState.targetFloor[1] = math.max(0, boussole.redirectState.targetFloor[1])
            end
            imgui.Separator()
            imgui.Text('Offset')
            imgui.SetNextItemWidth(inputWidth)
            imgui.InputInt('X##off', boussole.redirectState.offsetX)
            imgui.SetNextItemWidth(inputWidth)
            imgui.InputInt('Y##off', boussole.redirectState.offsetY)

            local buttonLabel = isEditing and 'Save Changes' or 'Add Redirect'
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
                if imgui.Button('Use Current', { -1, 0 }) then
                    boussole.redirectState.sourceZone[1] = selZoneId
                    boussole.redirectState.sourceFloor[1] = boussole.manualFloorId[1]
                end
            end
            imgui.Spacing()

            -- List of redirects at the bottom
            if imgui.BeginChild('##RedirectList', { -1, 120 }, true) then
                local toRemove = nil
                local toEdit = nil

                for key, redirect in pairs(boussole.config.mapRedirects) do
                    local srcZone, srcFloor = key:match('(%d+)_(%d+)')
                    srcZone = tonumber(srcZone)
                    srcFloor = tonumber(srcFloor)

                    if srcZone and srcFloor then
                        local isCurrentMap = (srcZone == selZoneId and srcFloor == boussole.manualFloorId[1])
                        local isEditingThis = (boussole.redirectState.editingKey == key)
                        local label = string.format('%s%d|%d -> %d|%d [%d,%d]',
                            isCurrentMap and '* ' or '',
                            srcZone, srcFloor,
                            redirect.targetZone, redirect.targetFloor,
                            redirect.offsetX, redirect.offsetY)

                        imgui.PushID(key)

                        if imgui.Selectable(label, isEditingThis) then
                            toEdit = { key, srcZone, srcFloor, redirect }
                        end

                        if imgui.BeginPopupContextItem() then
                            imgui.Text(string.format('Redirect: %d|%d', srcZone, srcFloor))
                            imgui.Separator()
                            if imgui.MenuItem('Edit') then
                                toEdit = { key, srcZone, srcFloor, redirect }
                            end
                            if imgui.MenuItem('Delete') then
                                toRemove = { srcZone, srcFloor }
                            end
                            imgui.EndPopup()
                        end

                        imgui.PopID()
                    end
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

                imgui.EndChild()
            end
            imgui.Spacing()

            imgui.Separator()
            imgui.Spacing()
            imgui.Text('Map options')
            imgui.Spacing()

            if imgui.Checkbox('Use custom maps', boussole.config.useCustomMaps) then
                settings.save()
            end
            imgui.Spacing()

            local ui = require('src.ui')
            if imgui.Button('Export map as BMP', { -1, 0 }) then
                local success, result = export.save_map(ui.texture_id, map.current_map_data)
                if success then
                    print(chat.header(addon.name):append(chat.success(string.format('Map exported to: %s', result))))
                else
                    print(chat.header(addon.name):append(chat.error(string.format('Export failed: %s', result))))
                end
            end
            imgui.Spacing()
        end
        imgui.EndChild()
    end
end

return panel
