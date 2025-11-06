local panel = {}
local map = require('src.map')
local regions = require('data.regions')
local zones = require('data.zones')

local imgui = require('imgui')
local settings = require('settings')

-- Panel state
panel.width = 200

-- Draw the settings panel on the right side
function panel.draw(config, windowPosX, windowPosY, contentMinX, contentMinY, contentMaxX, contentMaxY)
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

    local panelWidth = panel.width
    local toggleButtonWidth = 20
    local buttonSpacing = 5
    local isPanelVisible = config.settingsPanelVisible[1]

    -- Calculate positions
    local panelX = windowPosX + contentMaxX - (isPanelVisible and panelWidth or 0)
    local panelY = windowPosY + contentMinY
    local panelHeight = contentMaxY - contentMinY

    local toggleButtonX = isPanelVisible and (panelX - toggleButtonWidth - buttonSpacing) or (windowPosX + contentMaxX - toggleButtonWidth)
    local toggleButtonY = panelY + (panelHeight / 2) - 30

    local drawList = imgui.GetWindowDrawList()

    -- Draw toggle button background
    local buttonColor = 0x88444444
    local buttonHoverColor = 0xBB666666
    local buttonTextColor = 0xFFFFFFFF

    -- Check if mouse is over toggle button
    local mousePosX, mousePosY = imgui.GetMousePos()
    local isHoveringButton = mousePosX >= toggleButtonX and mousePosX <= (toggleButtonX + toggleButtonWidth) and
        mousePosY >= toggleButtonY and mousePosY <= (toggleButtonY + 60)

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
            config.settingsPanelVisible[1] = not isPanelVisible
            settings.save()
        end
    end
    imgui.EndChild()

    -- Draw panel if visible
    if isPanelVisible then
        -- Draw panel background
        drawList:AddRectFilled(
            { panelX, panelY },
            { panelX + panelWidth, panelY + panelHeight },
            0xE0222222,
            0.0
        )

        -- Draw panel border
        drawList:AddRect(
            { panelX, panelY },
            { panelX + panelWidth, panelY + panelHeight },
            0xFF444444,
            0.0,
            0,
            1.0
        )

        -- Create an invisible window for the panel widgets
        imgui.SetCursorPos({ panelX - windowPosX, panelY - windowPosY })

        if imgui.BeginChild('##Panel', { panelWidth, panelHeight }, false, bit.bor(ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_AlwaysUseWindowPadding)) then
            imgui.Text('Browse maps')
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

            if imgui.Checkbox('Survival Guides', config.showSurvivalGuides) then
                settings.save()
            end
            imgui.Spacing()

            if imgui.Checkbox('Player (me)', config.showPlayer) then
                settings.save()
            end
            imgui.Spacing()

            imgui.Separator()
            imgui.Spacing()
            imgui.Text('Map options')
            imgui.Spacing()

            if imgui.Checkbox('Use custom maps', config.useCustomMaps) then
                settings.save()
            end
            imgui.Spacing()
        end
        imgui.EndChild()
    end
end

return panel
