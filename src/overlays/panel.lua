local panel = {}
local map = require('src.map')
local regions = require('data.regions')
local zones = require('data.zones')
local export = require('src.export')
local imgui = require('imgui')
local settings = require('settings')
local chat = require('chat')
local utils = require('src.utils')
local tracker = require('src.tracker')
local controls = require('src.overlays.controls')
local texture = require('src.texture')
local d3d8 = require('d3d8')
local ffi = require('ffi')

local panel_cursor_texture = nil

local function get_cursor_screen_pos()
    local x, y = imgui.GetCursorScreenPos()
    if type(x) == 'table' then
        return x[1], x[2]
    end
    return x, y
end

local function load_panel_cursor_texture()
    if panel_cursor_texture then
        return true
    end

    local d3d8dev = d3d8.get_device()
    if not d3d8dev then
        return false
    end

    local cursor_path = string.format('%saddons\\boussole\\assets\\cursor.png', AshitaCore:GetInstallPath())
    local gcTexture = texture.load_texture_from_file(cursor_path, d3d8dev)
    if gcTexture then
        panel_cursor_texture = gcTexture
        return true
    end

    return false
end

local function draw_display_toggle(label, displaySetting, labelSetting, id, colorSetting, iconKind)
    controls.load_textures()
    load_panel_cursor_texture()

    local buttonSize = 24
    local spacing = 4
    local enabled = displaySetting[1]
    local labelEnabled = enabled and labelSetting[1]
    local iconColor = enabled and utils.rgb_to_abgr(colorSetting) or 0xFF777777
    local nameColor = labelEnabled and utils.rgb_to_abgr(colorSetting) or 0xFF777777
    local buttonColor = utils.rgb_to_abgr(boussole.config.colorControlsBtn)
    local hoverColor = utils.rgb_to_abgr({ 0.36, 0.36, 0.36, 0.75 })
    local activeColor = utils.rgb_to_abgr({ 0.42, 0.42, 0.42, 0.85 })
    local drawList = imgui.GetWindowDrawList()

    imgui.PushStyleColor(ImGuiCol_Button, buttonColor)
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, hoverColor)
    imgui.PushStyleColor(ImGuiCol_ButtonActive, activeColor)

    local iconPosX, iconPosY = get_cursor_screen_pos()
    if imgui.Button('##Icon' .. id, { buttonSize, buttonSize }) then
        displaySetting[1] = not displaySetting[1]
        settings.save()
    end

    local iconCenterX = iconPosX + buttonSize / 2
    local iconCenterY = iconPosY + buttonSize / 2
    if iconKind == 'cursor' and panel_cursor_texture then
        utils.draw_rotated_texture(drawList, tonumber(ffi.cast('uint32_t', panel_cursor_texture)), iconCenterX, iconCenterY, buttonSize * 0.65, math.pi / 4, iconColor)
    elseif iconKind == 'diamond' then
        utils.draw_diamond_marker(drawList, iconCenterX, iconCenterY, 7, iconColor, nil, 1.0)
    elseif iconKind == 'square' then
        utils.draw_square_marker(drawList, iconCenterX, iconCenterY, buttonSize * 0.34, iconColor, nil, 0)
    else
        utils.draw_circle_marker(drawList, iconCenterX, iconCenterY, buttonSize * 0.28, iconColor, nil, 0)
    end

    if imgui.IsItemHovered() then
        imgui.SetTooltip(enabled and 'Hide marker' or 'Show marker')
    end

    imgui.SameLine(0, spacing)

    local tagPosX, tagPosY = get_cursor_screen_pos()
    if imgui.Button('##Name' .. id, { buttonSize, buttonSize }) then
        if enabled then
            labelSetting[1] = not labelSetting[1]
            settings.save()
        end
    end

    if controls.tag_texture then
        local texPtr = tonumber(ffi.cast('uint32_t', controls.tag_texture))
        local iconSize = buttonSize * 0.68
        local offset = (buttonSize - iconSize) / 2
        drawList:AddImage(
            texPtr,
            { tagPosX + offset, tagPosY + offset },
            { tagPosX + offset + iconSize, tagPosY + offset + iconSize },
            { 0, 0 },
            { 1, 1 },
            nameColor
        )
    end

    if imgui.IsItemHovered() then
        imgui.SetTooltip(enabled and (labelSetting[1] and 'Hide name' or 'Show name') or 'Marker is hidden')
    end

    imgui.PopStyleColor(3)
    imgui.SameLine(0, 8)
    imgui.AlignTextToFramePadding()
    imgui.Text(label)
end

-- Helper function to format entity identifier based on selected type
local function format_identifier(entity)
    local identifierType = boussole.config.trackerIdentifierType or 'Index (Hex)'
    local index = entity.index or bit.band(entity.id, 0x7FF)

    if identifierType == 'Index (Decimal)' then
        return string.format('[%d]', index)
    elseif identifierType == 'Index (Hex)' then
        return string.format('[%X]', index)
    elseif identifierType == 'Id (Decimal)' then
        return string.format('[%d]', entity.id)
    elseif identifierType == 'Id (Hex)' then
        return string.format('[%X]', entity.id)
    end
    return string.format('[%X]', index) -- Default to Index (Hex)
end

local function draw_map_tab_tracker()
    if not boussole.config.enableTracker[1] then
        return
    end

    imgui.SeparatorText(ICON_FA_LOCATION_DOT .. ' Tracker')

    -- Profile management
    imgui.SetNextItemWidth(150)

    local profiles = tracker.get_profiles()
    local profileNames = { 'None' }
    for name, _ in pairs(profiles) do
        table.insert(profileNames, name)
    end
    table.sort(profileNames, function (a, b)
        if a == 'None' then return true end
        if b == 'None' then return false end
        return a < b
    end)

    local currentProfile = boussole.config.lastLoadedTrackerProfile or ''
    local selectedProfileIdx = 1
    for i, name in ipairs(profileNames) do
        if name == currentProfile then
            selectedProfileIdx = i
            break
        end
    end

    if imgui.BeginCombo('##TrackerProfile', profileNames[selectedProfileIdx] or 'None') then
        for i, name in ipairs(profileNames) do
            if imgui.Selectable(name, selectedProfileIdx == i) then
                if name == 'None' then
                    boussole.config.lastLoadedTrackerProfile = ''
                    tracker.clear_all()
                else
                    tracker.load_profile(name)
                    boussole.config.lastLoadedTrackerProfile = name
                end
                settings.save()

                boussole.trackedSearchResults = {}
            end
        end
        imgui.EndCombo()
    end

    imgui.SameLine()
    if imgui.Button(ICON_FA_FLOPPY_DISK, { 50, 0 }) then
        if currentProfile ~= '' then
            tracker.save_profile(currentProfile)
            tracker.save_tracker_data()
        else
            imgui.OpenPopup('Save profile')
        end
    end

    -- Save profile modal
    if imgui.BeginPopupModal('Save profile', nil, 0) then
        if not boussole.trackerNewProfileName then
            boussole.trackerNewProfileName = { '' }
        end
        imgui.Text('Enter profile name:')
        imgui.SetNextItemWidth(-1)
        imgui.InputText('##NewProfileName', boussole.trackerNewProfileName, 64)

        if imgui.Button('Save', { 80, 0 }) then
            local name = boussole.trackerNewProfileName[1]
            if name and name ~= '' then
                tracker.save_profile(name)
                boussole.config.lastLoadedTrackerProfile = name
                settings.save()
                tracker.save_tracker_data()
                imgui.CloseCurrentPopup()
            end
        end
        imgui.SameLine()
        if imgui.Button('Cancel', { 80, 0 }) then
            imgui.CloseCurrentPopup()
        end
        imgui.EndPopup()
    end

    imgui.SameLine()
    if imgui.Button(ICON_FA_TRASH, { 50, 0 }) then
        if currentProfile ~= '' then
            tracker.delete_profile(currentProfile)
            boussole.config.lastLoadedTrackerProfile = ''
            settings.save()
            tracker.save_tracker_data()
        end
    end

    imgui.Spacing()

    -- Tracker tabs
    if imgui.BeginTabBar('##TrackerTabs') then
        -- Zone List Tab
        if imgui.BeginTabItem('Zone list') then
            -- Initialize zone entities if not loaded
            local zoneEntities = tracker.get_zone_entities()
            local hasEntities = false
            for _ in pairs(zoneEntities) do
                hasEntities = true
                break
            end

            if not hasEntities then
                local detectedZone, detectedSubZone = tracker.get_current_zone_and_subzone()
                if detectedZone and detectedZone > 0 then
                    tracker.load_zone_entities(detectedZone, detectedSubZone)
                    zoneEntities = tracker.get_zone_entities()
                end
            end

            -- Initialize search results with all entities if empty and no search is active
            if not boussole.trackerSearchResults or (#boussole.trackerSearchResults == 0 and boussole.trackerSearch[1] == '') then
                boussole.trackerSearchResults = {}
                for id, entity in pairs(zoneEntities) do
                    table.insert(boussole.trackerSearchResults, entity)
                end
                table.sort(boussole.trackerSearchResults, function (a, b)
                    return a.name < b.name
                end)
            end

            imgui.Text(string.format('Search (%d)', #boussole.trackerSearchResults))
            imgui.SetNextItemWidth(-1)
            if imgui.InputText('##TrackerSearch', boussole.trackerSearch, 256) then
                -- Update search results
                boussole.trackerSearchResults = {}
                local searchText = boussole.trackerSearch[1]:lower()

                for id, entity in pairs(zoneEntities) do
                    if searchText == '' or entity.name:lower():find(searchText, 1, true) then
                        table.insert(boussole.trackerSearchResults, entity)
                    end
                end

                table.sort(boussole.trackerSearchResults, function (a, b)
                    return a.name < b.name
                end)
            end

            if imgui.Button(ICON_FA_CHECK_DOUBLE .. ' Add all', { -1, 0 }) then
                local added = 0
                local existing = 0
                for _, entity in ipairs(boussole.trackerSearchResults) do
                    local result = tracker.add_entity(entity.id, entity.name, entity.name)
                    if result == true then
                        added = added + 1
                    elseif result == 'exists' then
                        existing = existing + 1
                    end
                end
                if added > 0 or existing > 0 then
                    if existing > 0 then
                        print(chat.header(addon.name):append(chat.message(string.format('Added %d entities to tracking. %d already tracked.', added, existing))))
                    else
                        print(chat.header(addon.name):append(chat.message(string.format('Added %d entities to tracking.', added))))
                    end
                    boussole.trackedSearchResults = {}
                end
            end
            imgui.Spacing()

            -- Calculate remaining height for the list
            local _, remainingHeight = imgui.GetContentRegionAvail()
            local buttonsHeight = imgui.GetFrameHeightWithSpacing() * 2 + 10
            if imgui.BeginChild('##ZoneEntityList', { -1, remainingHeight - buttonsHeight }, ImGuiChildFlags_Borders) then
                if imgui.BeginTable('##ZoneEntityTable', 2, 0) then
                    imgui.TableSetupColumn('##Name', 0, 0.85)
                    imgui.TableSetupColumn('##Add', 0, 0.15)

                    for i, entity in ipairs(boussole.trackerSearchResults) do
                        imgui.TableNextRow()
                        imgui.TableSetColumnIndex(0)

                        local itemHeight = imgui.GetTextLineHeight()
                        local identifier = format_identifier(entity)
                        local displayText = string.format('%s %s', entity.name, identifier)
                        local isSelected = boussole.trackerSelections[entity.id] or false
                        if imgui.Selectable(displayText .. '##ZoneEnt' .. entity.id, isSelected, 0, { 0, itemHeight }) then
                            -- Toggle selection on click using entity ID
                            boussole.trackerSelections[entity.id] = not boussole.trackerSelections[entity.id]
                            boussole.trackerSelection = i
                        end

                        imgui.TableSetColumnIndex(1)
                        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 0, 0 })
                        if imgui.Button('+##Add' .. entity.id, { -1, itemHeight }) then
                            local result = tracker.add_entity(entity.id, entity.name, entity.name)
                            if result == true then
                                print(chat.header(addon.name):append(chat.message(string.format('Added %s to tracking.', entity.name))))
                                boussole.trackedSearchResults = {}
                            elseif result == 'exists' then
                                print(chat.header(addon.name):append(chat.message(string.format('%s is already being tracked.', entity.name))))
                            end
                        end
                        imgui.PopStyleVar()
                    end

                    imgui.EndTable()
                end
            end
            imgui.EndChild()

            imgui.Spacing()

            local selectionCount = 0
            for _, selected in pairs(boussole.trackerSelections) do
                if selected then selectionCount = selectionCount + 1 end
            end

            if imgui.Button(string.format(ICON_FA_SQUARE_CHECK .. ' Track selection (%d)', selectionCount), { -1, 0 }) then
                local added = 0
                local existing = 0
                local zoneEntities = tracker.get_zone_entities()
                for entityId, selected in pairs(boussole.trackerSelections) do
                    if selected and zoneEntities[entityId] then
                        local entity = zoneEntities[entityId]
                        local result = tracker.add_entity(entity.id, entity.name, entity.name)
                        if result == true then
                            added = added + 1
                        elseif result == 'exists' then
                            existing = existing + 1
                        end
                    end
                end
                if added > 0 or existing > 0 then
                    if existing > 0 then
                        print(chat.header(addon.name):append(chat.message(string.format('Added %d entities to tracking. %d already tracked.', added, existing))))
                    else
                        print(chat.header(addon.name):append(chat.message(string.format('Added %d entities to tracking.', added))))
                    end
                    boussole.trackedSearchResults = {}
                end
            end

            if imgui.Button(string.format(ICON_FA_SQUARE_XMARK .. ' Clear selection (%d)', selectionCount), { -1, 0 }) then
                boussole.trackerSelections = {}
                boussole.trackerSelection = -1
            end

            imgui.EndTabItem()
        end

        local trackedEntities = tracker.get_tracked_entities()
        local sortedTracked = {}
        local currentZone = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)

        for _, entity in pairs(trackedEntities) do
            if entity.zoneId == currentZone then
                table.insert(sortedTracked, entity)
            end
        end

        table.sort(sortedTracked, function (a, b)
            return a.name < b.name
        end)

        -- Active Tracking Tab
        if imgui.BeginTabItem('Tracked') then
            -- Initialize tracked search if needed
            if not boussole.trackedSearch then
                boussole.trackedSearch = { '' }
            end

            -- Search bar
            imgui.Text(string.format('Search (%d)', boussole.trackedSearchResults and #boussole.trackedSearchResults or 0))
            imgui.SetNextItemWidth(-1)
            if imgui.InputText('##TrackedSearch', boussole.trackedSearch, 256) then
                -- Update search results
                boussole.trackedSearchResults = {}
                local searchText = boussole.trackedSearch[1]:lower()

                for _, entity in ipairs(sortedTracked) do
                    local displayName = entity.alias ~= entity.name and
                        string.format('%s (%s)', entity.name, entity.alias) or entity.name
                    if searchText == '' or displayName:lower():find(searchText, 1, true) then
                        table.insert(boussole.trackedSearchResults, entity)
                    end
                end
            end

            -- Initialize search results with all entities if empty and no search is active
            if not boussole.trackedSearchResults or (#boussole.trackedSearchResults == 0 and boussole.trackedSearch[1] == '') then
                boussole.trackedSearchResults = {}
                for _, entity in ipairs(sortedTracked) do
                    table.insert(boussole.trackedSearchResults, entity)
                end
            end

            imgui.Spacing()

            -- Calculate height needed for controls below the list
            local controlsHeight = 0
            -- Two buttons (Single packet all, Clear all)
            controlsHeight = controlsHeight + imgui.GetFrameHeightWithSpacing() * 2
            -- Spacing after list
            controlsHeight = controlsHeight + 5
            -- Selected entity controls if any selected
            if boussole.trackedSelection > 0 and boussole.trackedSelection <= #boussole.trackedSearchResults then
                -- Separator, text header, spacing, alias input, color edit, 3 checkboxes, spacing, 2 buttons
                controlsHeight = controlsHeight + imgui.GetFrameHeightWithSpacing() * 10 + 40
            end

            local _, availHeight = imgui.GetContentRegionAvail()
            local listHeight = availHeight - controlsHeight

            if imgui.BeginChild('##TrackedEntityList', { -1, listHeight }, ImGuiChildFlags_Borders) then
                if imgui.BeginTable('##TrackedEntityTable', 2, 0) then
                    imgui.TableSetupColumn('##Name', 0, 0.85)
                    imgui.TableSetupColumn('##Remove', 0, 0.15)

                    for i, entity in ipairs(boussole.trackedSearchResults) do
                        imgui.TableNextRow()
                        imgui.TableSetColumnIndex(0)

                        local displayName = entity.alias ~= entity.name and
                            string.format('%s (%s)', entity.name, entity.alias) or entity.name
                        local identifier = format_identifier(entity)
                        displayName = string.format('%s %s', displayName, identifier)

                        local itemHeight = imgui.GetTextLineHeight()
                        if imgui.Selectable(displayName .. '##Tracked' .. entity.id, boussole.trackedSelection == i, 0, { 0, itemHeight }) then
                            boussole.trackedSelection = i
                        end

                        imgui.TableSetColumnIndex(1)
                        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 0, 0 })
                        if imgui.Button('-##Rem' .. entity.id, { -1, itemHeight }) then
                            tracker.remove_entity(entity.id)
                            if boussole.trackedSelection == i then
                                boussole.trackedSelection = -1
                            end
                            boussole.trackedSearchResults = {}
                        end
                        imgui.PopStyleVar()
                    end

                    imgui.EndTable()
                end
            end
            imgui.EndChild()

            imgui.Spacing()

            -- Packet controls
            local isSending = tracker.is_sending_packets()
            if not isSending then
                if imgui.Button(ICON_FA_LIST_CHECK .. ' Single packet all', { -1, 0 }) then
                    tracker.send_all_packets()
                end
            else
                imgui.TextColored({ 1.0, 0.5, 0.2, 1.0 }, 'Sending packets...')
            end

            if imgui.Button(ICON_FA_TRASH .. ' Clear all', { -1, 0 }) then
                tracker.clear_all()
                boussole.trackedSelection = -1
                -- Clear tracked search results to trigger refresh
                boussole.trackedSearchResults = {}
            end

            -- Selected entity controls
            if boussole.trackedSelection > 0 and boussole.trackedSelection <= #boussole.trackedSearchResults then
                local entity = boussole.trackedSearchResults[boussole.trackedSelection]

                imgui.Spacing()
                imgui.Separator()
                imgui.Text('Selected entity')
                imgui.Spacing()

                -- Alias
                if not boussole.trackerAliasBuffer then
                    boussole.trackerAliasBuffer = { entity.alias }
                else
                    boussole.trackerAliasBuffer[1] = entity.alias
                end

                if imgui.InputText('Alias##TrackerAlias', boussole.trackerAliasBuffer, 256) then
                    tracker.update_entity(entity.id, { alias = boussole.trackerAliasBuffer[1] })
                end

                -- Color
                local colors = { entity.color[1], entity.color[2], entity.color[3], entity.color[4] }
                if imgui.ColorEdit4('Color##TrackerColor', colors, 0) then
                    tracker.update_entity(entity.id, { color = colors })
                end

                -- Options
                local alarm = { entity.alarm }
                if imgui.Checkbox('Alarm##TrackerAlarm', alarm) then
                    tracker.update_entity(entity.id, { alarm = alarm[1] })
                end

                local draw = { entity.draw }
                if imgui.Checkbox('Show on map##TrackerDraw', draw) then
                    tracker.update_entity(entity.id, { draw = draw[1] })
                end

                local widescan = { entity.widescan }
                if imgui.Checkbox('Auto widescan##TrackerWidescan', widescan) then
                    tracker.update_entity(entity.id, { widescan = widescan[1] })
                end

                imgui.Spacing()

                -- Timeout setting
                local timeout = { entity.timeout or 0 }
                if imgui.InputInt('Timeout##TrackerTimeout', timeout, 10, 60) then
                    if timeout[1] < 0 then timeout[1] = 0 end
                    tracker.update_entity(entity.id, { timeout = timeout[1] })
                end
                imgui.ShowHelp('After this many seconds without position updates, remove entity from map. Set to 0 to never timeout.', true)

                imgui.Spacing()

                -- Packet controls for selected entity
                if imgui.Button('Single packet', { -1, 0 }) then
                    tracker.send_single_packet(entity.id)
                end

                if imgui.Button('Single widescan', { -1, 0 }) then
                    tracker.send_widescan(entity.id)
                end
            end

            imgui.EndTabItem()
        end

        imgui.EndTabBar()
    end
end

local function draw_map_tab(currentZone, currentFloor, selectedZoneName, filteredZoneIds, filteredZoneNames, selZoneId)
    local isBrowsingDifferentMap = (boussole.manualZoneId[1] ~= currentZone) or
        (boussole.manualFloorId[1] ~= currentFloor)

    if isBrowsingDifferentMap then
        imgui.SeparatorText(ICON_FA_MAP_LOCATION .. ' Browse maps')
        imgui.SameLine()
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 5)

        local _, textH = imgui.CalcTextSize(ICON_FA_MAP_LOCATION .. ' Browse maps')
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 0, 0 })
        if imgui.Button('Current', { -1, textH }) then
            -- Return to current map
            boussole.manualZoneId[1] = currentZone
            boussole.manualFloorId[1] = currentFloor
            boussole.manualMapReload[1] = true
        end
        imgui.PopStyleVar()
    else
        imgui.SeparatorText(ICON_FA_MAP_LOCATION .. ' Browse maps')
    end
    imgui.Spacing()

    imgui.SetNextItemWidth(-1)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 4, 4 })
    local zoneComboOpened = imgui.BeginCombo('##ZoneSelect', selectedZoneName, ImGuiComboFlags_HeightLarge)
    if zoneComboOpened then
        imgui.InputText('##ZoneSearch', boussole.zoneSearch, 256)
        imgui.Separator()

        if imgui.BeginChild('##ZoneList', { 0, 200 }, ImGuiChildFlags_None, ImGuiWindowFlags_NoBackground) then
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
        end
        imgui.EndChild()
        imgui.EndCombo()
    end
    imgui.PopStyleVar()

    local floorIds = {}
    local floorNames = {}

    if selZoneId == currentZone then
        table.insert(floorIds, currentFloor)
        local floorName = map.get_floor_name(selZoneId, currentFloor)
        table.insert(floorNames, string.format('%s (current)', floorName))
    end

    local zonesFloors = map.get_floors_for_zone(selZoneId)
    for _, fid in ipairs(zonesFloors) do
        if fid ~= currentFloor or selZoneId ~= currentZone then
            table.insert(floorIds, fid)
            local floorName = map.get_floor_name(selZoneId, fid)
            table.insert(floorNames, floorName)
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

    draw_map_tab_tracker()
end

local function draw_display_tab()
    -- Display Options
    imgui.SeparatorText(ICON_FA_FILTER .. ' Display options')

    draw_display_toggle('Homepoints', boussole.config.showHomepoints, boussole.config.showHomepointLabels, 'MapHomepoints', boussole.config.colorHomepoint, 'diamond')
    draw_display_toggle('Survival guides', boussole.config.showSurvivalGuides, boussole.config.showSurvivalGuideLabels, 'MapSurvivalGuides', boussole.config.colorSurvivalGuide, 'square')
    draw_display_toggle('Player (me)', boussole.config.showPlayer, boussole.config.showPlayerLabels, 'MapPlayer', boussole.config.colorPlayer, 'cursor')
    draw_display_toggle('Party members', boussole.config.showParty, boussole.config.showPartyLabels, 'MapParty', boussole.config.colorParty, 'cursor')
    draw_display_toggle('Alliance members', boussole.config.showAlliance, boussole.config.showAllianceLabels, 'MapAlliance', boussole.config.colorAlliance, 'cursor')
    draw_display_toggle('NPCs', boussole.config.showNpcEntities, boussole.config.showNpcEntityLabels, 'MapNpcs', boussole.config.colorNpcEntity, 'circle')
    draw_display_toggle('Mobs', boussole.config.showMobEntities, boussole.config.showMobEntityLabels, 'MapMobs', boussole.config.colorMobEntity, 'circle')
    if boussole.config.enableTracker[1] then
        draw_display_toggle('Tracked entities', boussole.config.showTrackedEntities, boussole.config.showTrackedEntityLabels, 'MapTracked', boussole.config.trackerDefaultColor, 'circle')
    end

    imgui.Spacing()
    imgui.PushItemWidth(100)
    if imgui.InputInt('NPC timeout##EntityTimeout', boussole.config.npcEntityTimeout, 5, 30) then
        boussole.config.npcEntityTimeout[1] = math.max(0, boussole.config.npcEntityTimeout[1])
        settings.save()
    end
    imgui.ShowHelp('After this many seconds without a packet, remove the NPC dot. Set to 0 to never timeout.', true)
    if imgui.InputInt('Mob timeout##EntityTimeout', boussole.config.mobEntityTimeout, 5, 30) then
        boussole.config.mobEntityTimeout[1] = math.max(0, boussole.config.mobEntityTimeout[1])
        settings.save()
    end
    imgui.ShowHelp('After this many seconds without a packet, remove the mob dot. Set to 0 to never timeout.', true)
    imgui.PopItemWidth()

    imgui.SeparatorText(ICON_FA_PALETTE .. ' UI appearance')

    imgui.PushItemWidth(100)
    if imgui.InputInt('Panel width', boussole.config.panelWidth, 10, 50) then
        boussole.config.panelWidth[1] = math.max(100, math.min(400, boussole.config.panelWidth[1]))
        settings.save()
    end
    imgui.PopItemWidth()
    imgui.Spacing()

    imgui.Separator()
    imgui.Text('Icon sizes')
    imgui.PushItemWidth(100)
    if imgui.InputInt('Homepoint##IconSize', boussole.config.iconSizeHomepoint, 1, 5) then
        boussole.config.iconSizeHomepoint[1] = math.max(2, math.min(20, boussole.config.iconSizeHomepoint[1]))
        settings.save()
    end
    if imgui.InputInt('Survival guide##IconSize', boussole.config.iconSizeSurvivalGuide, 1, 5) then
        boussole.config.iconSizeSurvivalGuide[1] = math.max(2, math.min(20, boussole.config.iconSizeSurvivalGuide[1]))
        settings.save()
    end
    if imgui.InputInt('Player##IconSize', boussole.config.iconSizePlayer, 1, 5) then
        boussole.config.iconSizePlayer[1] = math.max(4, math.min(40, boussole.config.iconSizePlayer[1]))
        settings.save()
    end
    if imgui.InputInt('Party##IconSize', boussole.config.iconSizeParty, 1, 5) then
        boussole.config.iconSizeParty[1] = math.max(4, math.min(40, boussole.config.iconSizeParty[1]))
        settings.save()
    end
    if imgui.InputInt('Alliance##IconSize', boussole.config.iconSizeAlliance, 1, 5) then
        boussole.config.iconSizeAlliance[1] = math.max(4, math.min(40, boussole.config.iconSizeAlliance[1]))
        settings.save()
    end
    if imgui.InputInt('NPC entity##IconSize', boussole.config.iconSizeNpcEntity, 1, 5) then
        boussole.config.iconSizeNpcEntity[1] = math.max(2, math.min(20, boussole.config.iconSizeNpcEntity[1]))
        settings.save()
    end
    if imgui.InputInt('Mob entity##IconSize', boussole.config.iconSizeMobEntity, 1, 5) then
        boussole.config.iconSizeMobEntity[1] = math.max(2, math.min(20, boussole.config.iconSizeMobEntity[1]))
        settings.save()
    end
    imgui.PopItemWidth()
    imgui.Spacing()

    -- Colors
    imgui.Separator()
    imgui.Text('Colors')
    if imgui.ColorEdit4('Homepoint##Color', boussole.config.colorHomepoint, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Survival guide##Color', boussole.config.colorSurvivalGuide, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Player (me)##Color', boussole.config.colorPlayer, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Party##Color', boussole.config.colorParty, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Alliance##Color', boussole.config.colorAlliance, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('NPC entity##MMColor', boussole.config.colorNpcEntity, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Mob entity##MMColor', boussole.config.colorMobEntity, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Info panel bg##Color', boussole.config.colorInfoPanelBg, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Panel bg##Color', boussole.config.colorPanelBg, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Toggle btn##Color', boussole.config.colorToggleBtn, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Controls btn##Color', boussole.config.colorControlsBtn, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Controls btn active##Color', boussole.config.colorControlsBtnActive, ImGuiColorEditFlags_NoInputs) then settings.save() end
    imgui.Spacing()

    -- Info panel
    imgui.Separator()
    imgui.Text('Info panel')
    imgui.PushItemWidth(100)
    if imgui.InputInt('Font size##InfoPanel', boussole.config.infoPanelFontSize, 1, 2) then
        boussole.config.infoPanelFontSize[1] = math.max(8, math.min(24, boussole.config.infoPanelFontSize[1]))
        settings.save()
    end
    imgui.PopItemWidth()
    imgui.Spacing()
end

local function draw_misc_tab(selZoneId)
    imgui.SeparatorText(ICON_FA_ROUTE .. ' Map redirects')

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
    if imgui.BeginChild('##RedirectList', { -1, 120 }, ImGuiChildFlags_Borders) then
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
    end
    imgui.EndChild()

    imgui.SeparatorText(ICON_FA_WRENCH .. ' Map options')

    if imgui.Button(ICON_FA_FILE_PEN .. ' Map data editor', { -1, 0 }) then
        if not boussole.mapDataEditor then
            boussole.mapDataEditor = {
                visible = { true },
                selectedZoneId = 0,
                selectedFloorId = nil,
                edit = {},
                lastCopiedAt = 0
            }
        else
            boussole.mapDataEditor.visible[1] = true
        end
    end
    imgui.Spacing()

    if imgui.Checkbox('Use custom maps', boussole.config.useCustomMaps) then
        settings.save()
    end
    imgui.Spacing()

    if imgui.Checkbox('Enable tracker feature', boussole.config.enableTracker) then
        settings.save()
    end
    imgui.ShowHelp('Enables the tracker feature, which allows sending packets manually to get entities positions. USE WITH CAUTION, it\'s literally cheating, so you put your account at risk.', true)

    -- Tracker settings (only show if tracker is enabled)
    if boussole.config.enableTracker[1] then
        imgui.SeparatorText(ICON_FA_LOCATION_DOT .. ' Tracker settings')

        -- Packet delay control
        imgui.Text('Packet delay (seconds):')
        imgui.SetNextItemWidth(-1)
        if imgui.SliderFloat('##TrackerPacketDelay', boussole.config.trackerPacketDelay, 0.4, 300.0, '%.1f') then
            settings.save()
        end

        -- Identifier type dropdown
        imgui.Text('Identifier type:')
        imgui.SetNextItemWidth(-1)
        local identifierTypes = { 'Index (Decimal)', 'Index (Hex)', 'Id (Decimal)', 'Id (Hex)' }
        if imgui.BeginCombo('##TrackerIdentifierType', boussole.config.trackerIdentifierType) then
            for _, idType in ipairs(identifierTypes) do
                if imgui.Selectable(idType, boussole.config.trackerIdentifierType == idType) then
                    boussole.config.trackerIdentifierType = idType
                    settings.save()
                end
            end
            imgui.EndCombo()
        end

        -- Default color picker
        imgui.Text('Default entity color:')
        imgui.SetNextItemWidth(-1)
        if imgui.ColorEdit4('##TrackerDefaultColor', boussole.config.trackerDefaultColor, 0) then
            settings.save()
        end
        imgui.Spacing()
    end

    imgui.SeparatorText(ICON_FA_FLOPPY_DISK .. ' Export')

    local ui = require('src.ui')
    if imgui.Button(ICON_FA_FILE_EXPORT .. ' Export map as BMP', { -1, 0 }) then
        local success, result = export.save_map(ui.texture_id, map.current_map_data)
        if success then
            print(chat.header(addon.name):append(chat.success(string.format('Map exported to: %s', result))))
        else
            print(chat.header(addon.name):append(chat.error(string.format('Export failed: %s', result))))
        end
    end

    local zone = map.current_map_data.entry.ZoneId
    local floor = map.current_map_data.entry.FloorId
    imgui.Text('Current zone: ' .. (zone or 'N/A'))
    imgui.Text('Current floor: ' .. (floor or 'N/A'))
    imgui.Spacing()
end

local function draw_minimap_tab()
    -- Minimap-specific settings
    imgui.SeparatorText(ICON_FA_MAP .. ' Minimap')

    if imgui.Checkbox('Visible', boussole.config.minimapVisible) then
        settings.save()
    end
    imgui.SameLine()
    if imgui.Checkbox('Locked', boussole.config.minimapLocked) then
        settings.save()
    end
    imgui.Spacing()

    imgui.PushItemWidth(100)
    if imgui.InputInt('Size (px)', boussole.config.minimapSize, 10, 50) then
        boussole.config.minimapSize[1] = math.max(80, math.min(600, boussole.config.minimapSize[1]))
        settings.save()
    end

    if imgui.InputFloat('Zoom step', boussole.config.minimapZoomStep, 0.01, 0.1, '%.2f') then
        boussole.config.minimapZoomStep[1] = math.max(0.01, math.min(1.0, boussole.config.minimapZoomStep[1]))
        settings.save()
    end

    if imgui.InputFloat('Corner radius', boussole.config.minimapCornerRadius, 1.0, 5.0, '%.0f') then
        boussole.config.minimapCornerRadius[1] = math.max(0.0, math.min(50.0, boussole.config.minimapCornerRadius[1]))
        settings.save()
    end

    if imgui.InputFloat('Recenter delay', boussole.config.minimapRecenterTimeout, 0.5, 1.0, '%.1f') then
        boussole.config.minimapRecenterTimeout[1] = math.max(0.0, math.min(60.0, boussole.config.minimapRecenterTimeout[1]))
        settings.save()
    end
    if imgui.IsItemHovered() then imgui.SetTooltip('Seconds after dragging before re-centering on player. 0 = disabled.') end
    imgui.PopItemWidth()

    if imgui.Checkbox('Recenter when player moves##MM', boussole.config.minimapRecenterOnMove) then
        settings.save()
    end
    if imgui.IsItemHovered() then imgui.SetTooltip('Automatically re-center the minimap when the player starts moving after a right-click drag.') end

    imgui.PushItemWidth(120)
    if imgui.SliderFloat('Map opacity', boussole.config.minimapOpacity, 0.0, 1.0, '%.2f') then
        settings.save()
    end
    if imgui.SliderFloat('Overlay opacity', boussole.config.minimapOverlayOpacity, 0.0, 1.0, '%.2f') then
        settings.save()
    end
    imgui.PopItemWidth()
    imgui.Spacing()

    if imgui.Checkbox('Show labels##MM', boussole.config.minimapShowLabels) then
        settings.save()
    end

    imgui.SeparatorText(ICON_FA_FILTER .. ' Display options')

    draw_display_toggle('Homepoints', boussole.config.minimapShowHomepoints, boussole.config.minimapShowHomepointLabels, 'MMHomepoints', boussole.config.minimapColorHomepoint, 'diamond')
    draw_display_toggle('Survival guides', boussole.config.minimapShowSurvivalGuides, boussole.config.minimapShowSurvivalGuideLabels, 'MMSurvivalGuides', boussole.config.minimapColorSurvivalGuide, 'square')
    draw_display_toggle('Player (me)', boussole.config.minimapShowPlayer, boussole.config.minimapShowPlayerLabels, 'MMPlayer', boussole.config.minimapColorPlayer, 'cursor')
    draw_display_toggle('Party members', boussole.config.minimapShowParty, boussole.config.minimapShowPartyLabels, 'MMParty', boussole.config.minimapColorParty, 'cursor')
    draw_display_toggle('Alliance members', boussole.config.minimapShowAlliance, boussole.config.minimapShowAllianceLabels, 'MMAlliance', boussole.config.minimapColorAlliance, 'cursor')
    draw_display_toggle('NPC entities', boussole.config.minimapShowNpcEntities, boussole.config.minimapShowNpcEntityLabels, 'MMNpcs', boussole.config.minimapColorNpcEntity, 'circle')
    draw_display_toggle('Mob entities', boussole.config.minimapShowMobEntities, boussole.config.minimapShowMobEntityLabels, 'MMMobs', boussole.config.minimapColorMobEntity, 'circle')
    if boussole.config.enableTracker[1] then
        draw_display_toggle('Tracked entities', boussole.config.minimapShowTrackedEntities, boussole.config.minimapShowTrackedEntityLabels, 'MMTracked', boussole.config.trackerDefaultColor, 'circle')
    end

    imgui.SeparatorText(ICON_FA_PALETTE .. ' UI appearance')

    imgui.Text('Icon sizes')
    imgui.PushItemWidth(100)
    if imgui.InputInt('Homepoint##MMIconSize', boussole.config.minimapIconSizeHomepoint, 1, 5) then
        boussole.config.minimapIconSizeHomepoint[1] = math.max(2, math.min(20, boussole.config.minimapIconSizeHomepoint[1]))
        settings.save()
    end
    if imgui.InputInt('Survival guide##MMIconSize', boussole.config.minimapIconSizeSurvivalGuide, 1, 5) then
        boussole.config.minimapIconSizeSurvivalGuide[1] = math.max(2, math.min(20, boussole.config.minimapIconSizeSurvivalGuide[1]))
        settings.save()
    end
    if imgui.InputInt('Player##MMIconSize', boussole.config.minimapIconSizePlayer, 1, 5) then
        boussole.config.minimapIconSizePlayer[1] = math.max(4, math.min(40, boussole.config.minimapIconSizePlayer[1]))
        settings.save()
    end
    if imgui.InputInt('Party##MMIconSize', boussole.config.minimapIconSizeParty, 1, 5) then
        boussole.config.minimapIconSizeParty[1] = math.max(4, math.min(40, boussole.config.minimapIconSizeParty[1]))
        settings.save()
    end
    if imgui.InputInt('Alliance##MMIconSize', boussole.config.minimapIconSizeAlliance, 1, 5) then
        boussole.config.minimapIconSizeAlliance[1] = math.max(4, math.min(40, boussole.config.minimapIconSizeAlliance[1]))
        settings.save()
    end
    if imgui.InputInt('NPC entity##MMIconSize', boussole.config.minimapIconSizeNpcEntity, 1, 5) then
        boussole.config.minimapIconSizeNpcEntity[1] = math.max(2, math.min(30, boussole.config.minimapIconSizeNpcEntity[1]))
        settings.save()
    end
    if imgui.InputInt('Mob entity##MMIconSize', boussole.config.minimapIconSizeMobEntity, 1, 5) then
        boussole.config.minimapIconSizeMobEntity[1] = math.max(2, math.min(30, boussole.config.minimapIconSizeMobEntity[1]))
        settings.save()
    end
    if boussole.config.enableTracker[1] then
        imgui.PushItemWidth(100)
        if imgui.InputInt('Tracked entity##MMIconSize', boussole.config.minimapIconSizeTrackedEntity, 1, 5) then
            boussole.config.minimapIconSizeTrackedEntity[1] = math.max(2, math.min(30, boussole.config.minimapIconSizeTrackedEntity[1]))
            settings.save()
        end
        imgui.PopItemWidth()
    end
    imgui.PopItemWidth()
    imgui.Spacing()

    imgui.Separator()
    imgui.Text('Colors')
    if imgui.ColorEdit4('Homepoint##MMColor', boussole.config.minimapColorHomepoint, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Survival guide##MMColor', boussole.config.minimapColorSurvivalGuide, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Player (me)##MMColor', boussole.config.minimapColorPlayer, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Party##MMColor', boussole.config.minimapColorParty, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Alliance##MMColor', boussole.config.minimapColorAlliance, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('NPC entity##MMColor', boussole.config.minimapColorNpcEntity, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Mob entity##MMColor', boussole.config.minimapColorMobEntity, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Controls btn##MMColor', boussole.config.minimapColorControlsBtn, ImGuiColorEditFlags_NoInputs) then settings.save() end
    if imgui.ColorEdit4('Controls btn active##MMColor', boussole.config.minimapColorControlsBtnActive, ImGuiColorEditFlags_NoInputs) then settings.save() end
    imgui.Spacing()
end

function panel.draw(windowPosX, windowPosY, contentMinX, contentMinY, contentMaxX, contentMaxY)
    local x, y, z = map.get_player_position()
    local currentZone = map.get_player_zone()
    local currentFloor = 0
    local selZoneId = boussole.manualZoneId[1]

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
        zoneNames = { currentZoneName .. ' (current)' }
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

    local baseColor = boussole.config.colorToggleBtn
    local color = utils.rgb_to_abgr(baseColor)
    local hover = { baseColor[1], baseColor[2], baseColor[3], math.min(1.0, (baseColor[4] or 1.0) + 0.2) }
    local hoverColor = utils.rgb_to_abgr(hover)
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
        isHoveringButton and hoverColor or color,
        3.0
    )

    -- Draw toggle button text
    local buttonText = isPanelVisible and '>' or '<'
    local textSizeX, textSizeY = imgui.CalcTextSize(buttonText)
    local textX = toggleButtonX + (toggleButtonWidth - textSizeX) / 2
    local textY = toggleButtonY + (60 - textSizeY) / 2

    drawList:AddText({ textX, textY }, buttonTextColor, buttonText)

    imgui.SetCursorPos({ toggleButtonX - windowPosX, toggleButtonY - windowPosY })
    if imgui.BeginChild('##PanelToggle', { toggleButtonWidth, 60 }, ImGuiChildFlags_None, bit.bor(ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoBackground)) then
        if imgui.InvisibleButton('##ToggleBtn', { toggleButtonWidth, 60 }) then
            boussole.config.settingsPanelVisible[1] = not isPanelVisible
            settings.save()
        end
    end
    imgui.EndChild()

    -- Draw panel if visible
    if isPanelVisible then
        -- Draw panel background
        local color = utils.rgb_to_abgr(boussole.config.colorPanelBg)
        drawList:AddRectFilled(
            { panelX, panelY },
            { panelX + boussole.config.panelWidth[1], panelY + panelHeight },
            color,
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

        if imgui.BeginChild('##Panel', { boussole.config.panelWidth[1], panelHeight }, ImGuiChildFlags_AlwaysUseWindowPadding, ImGuiWindowFlags_NoBackground) then
            if imgui.BeginTabBar('##BoussolePanelTabs') then
                if imgui.BeginTabItem('Map') then
                    draw_map_tab(currentZone, currentFloor, selectedZoneName, filteredZoneIds, filteredZoneNames, selZoneId)
                    imgui.EndTabItem()
                end

                if imgui.BeginTabItem('Display') then
                    draw_display_tab()
                    imgui.EndTabItem()
                end

                if imgui.BeginTabItem('Minimap') then
                    draw_minimap_tab()
                    imgui.EndTabItem()
                end

                if imgui.BeginTabItem('Misc') then
                    draw_misc_tab(selZoneId)
                    imgui.EndTabItem()
                end

                imgui.EndTabBar()
            end
        end
        imgui.EndChild()
    end
end

return panel
