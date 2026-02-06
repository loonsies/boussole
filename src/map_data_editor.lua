local map_data_editor = {}

local imgui = require('imgui')
local map = require('src.map')
local utils = require('src.utils')
local world_drawing = require('src.world_drawing')
local d3d8 = require('d3d8')
local ffi = require('ffi')
local C = ffi.C
local mem = ashita.memory

ffi.cdef [[
    struct camera_t
    {
        uint8_t Unknown0000[0x44];
        float X;
        float Z;
        float Y;
        float FocalX;
        float FocalZ;
        float FocalY;
    };
]]

local bounds_label_colors = {
    minY = { 1.0, 0.2, 0.2, 1.0 },
    maxX = { 0.2, 1.0, 0.2, 1.0 },
    maxY = { 0.2, 0.6, 1.0, 1.0 },
    minX = { 1.0, 1.0, 0.2, 1.0 }
}

local function get_camera_cursor_texture_id()
    if map_data_editor.camera_cursor_texture_id then
        return map_data_editor.camera_cursor_texture_id
    end

    local d3d8dev = d3d8.get_device()
    if not d3d8dev then
        return nil
    end

    local imagePath = string.format('%saddons\\boussole\\assets\\camera.png', AshitaCore:GetInstallPath())
    local texture_ptr = ffi.new('IDirect3DTexture8*[1]')
    local hr = C.D3DXCreateTextureFromFileA(d3d8dev, imagePath, texture_ptr)
    if hr ~= C.S_OK then
        return nil
    end

    map_data_editor.camera_cursor_texture_id = tonumber(ffi.cast('uint32_t', texture_ptr[0]))
    return map_data_editor.camera_cursor_texture_id
end

local function load_camera_button_texture(name)
    local cache_key = 'camera_btn_' .. name
    if map_data_editor[cache_key] ~= nil then
        return map_data_editor[cache_key]
    end

    local d3d8dev = d3d8.get_device()
    if not d3d8dev then
        map_data_editor[cache_key] = false
        return nil
    end

    local imagePath = string.format('%saddons\\boussole\\assets\\%s.png', AshitaCore:GetInstallPath(), name)
    local texture_ptr = ffi.new('IDirect3DTexture8*[1]')
    local hr = C.D3DXCreateTextureFromFileA(d3d8dev, imagePath, texture_ptr)
    if hr ~= C.S_OK then
        map_data_editor[cache_key] = false
        return nil
    end

    local texId = tonumber(ffi.cast('uint32_t', texture_ptr[0]))
    if not texId or texId == 0 then
        map_data_editor[cache_key] = false
        return nil
    end

    map_data_editor[cache_key] = texId
    return texId
end

local function ensure_state()
    if not boussole.mapDataEditor then
        boussole.mapDataEditor = {
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
    end
    return boussole.mapDataEditor
end

local function get_current_zone_id()
    if map.current_map_data and map.current_map_data.entry then
        return map.current_map_data.entry.ZoneId
    end
    return map.get_player_zone() or 0
end

local function get_sorted_floors(zoneData)
    local floors = {}
    for floorId, _ in pairs(zoneData) do
        table.insert(floors, floorId)
    end
    table.sort(floors)
    return floors
end

local camera_state = {
    baseCameraAddress = nil,
    cameraIsConnected = nil,
    initialized = false
}

local function init_camera_state()
    if camera_state.initialized then
        return
    end
    camera_state.initialized = true

    local injectionPoint = mem.find('FFXiMain.dll', 0, '83C40485C974118B116A01FF5218C705', 0, 0)
    if injectionPoint == 0 then
        return
    end

    local ptrToCamera = mem.read_uint32(injectionPoint + 0x10)
    if ptrToCamera == 0 then
        return
    end

    camera_state.baseCameraAddress = ffi.cast('uint32_t*', ptrToCamera)

    local cameraConnectSig = mem.find('FFXiMain.dll', 0, '80A0B2000000FBC605????????00', 0x09, 0)
    if cameraConnectSig ~= 0 then
        local cameraConnectPtr = mem.read_uint32(cameraConnectSig)
        if cameraConnectPtr ~= 0 then
            camera_state.cameraIsConnected = ffi.cast('bool*', cameraConnectPtr)
        end
    end
end

local function get_camera_position()
    init_camera_state()
    if not camera_state.baseCameraAddress then
        return nil
    end
    if camera_state.baseCameraAddress[0] == nil or camera_state.baseCameraAddress[0] == 0 then
        return nil
    end

    local camera = ffi.cast('struct camera_t*', camera_state.baseCameraAddress[0])
    if camera == nil then
        return nil
    end

    return camera.X, camera.Y, camera.Z
end

local function get_next_floor_id(zoneData)
    local nextId = 0
    if not zoneData then
        return nextId
    end

    for floorId, _ in pairs(zoneData) do
        if floorId >= nextId then
            nextId = floorId + 1
        end
    end
    return nextId
end

local function build_new_floor_data(base, subZoneName)
    return {
        scalingX = (base and base.scalingX) or 1.0,
        offsetX = (base and base.offsetX) or 0,
        scalingY = (base and base.scalingY) or -1.0,
        offsetY = (base and base.offsetY) or 0,
        minX = (base and base.minX) or 0,
        minY = (base and base.minY) or 0,
        minZ = (base and base.minZ) or -1000,
        maxX = (base and base.maxX) or 0,
        maxY = (base and base.maxY) or 0,
        maxZ = (base and base.maxZ) or 1000,
        referenceSize = (base and base.referenceSize) or 512,
        subZoneName = subZoneName or ''
    }
end

local function reset_edit_state(state, floorData)
    state.edit = {
        scalingX = { floorData.scalingX or 0 },
        offsetX = { floorData.offsetX or 0 },
        scalingY = { floorData.scalingY or 0 },
        offsetY = { floorData.offsetY or 0 },
        minX = { floorData.minX or 0 },
        minY = { floorData.minY or 0 },
        minZ = { floorData.minZ or 0 },
        maxX = { floorData.maxX or 0 },
        maxY = { floorData.maxY or 0 },
        maxZ = { floorData.maxZ or 0 },
        referenceSize = { floorData.referenceSize or 512 },
        subZoneName = { floorData.subZoneName or '' }
    }
end

local function ensure_selection(state, zoneId, zoneData)
    if state.selectedZoneId ~= zoneId then
        state.selectedZoneId = zoneId
        state.selectedFloorId = nil
    end

    if not zoneData then
        state.selectedFloorId = nil
        return
    end

    if not state.selectedFloorId or not zoneData[state.selectedFloorId] then
        local floors = get_sorted_floors(zoneData)
        state.selectedFloorId = floors[1]
        if state.selectedFloorId then
            reset_edit_state(state, zoneData[state.selectedFloorId])
        end
    end
end

local function json_escape(value)
    return tostring(value)
        :gsub('\\', '\\\\')
        :gsub('"', '\\"')
        :gsub('\n', '\\n')
        :gsub('\r', '\\r')
        :gsub('\t', '\\t')
end

local function format_number(value)
    local num = tonumber(value) or 0
    if num == math.floor(num) then
        return tostring(num)
    end
    return string.format('%.6g', num)
end

local function build_json_entry(floorId, data)
    local subZone = data.subZoneName or ''
    return string.format(
        '[%d] = {\n' ..
        '  scalingX = %s,\n' ..
        '  offsetX = %s,\n' ..
        '  scalingY = %s,\n' ..
        '  offsetY = %s,\n' ..
        '  minX = %s,\n' ..
        '  minY = %s,\n' ..
        '  minZ = %s,\n' ..
        '  maxX = %s,\n' ..
        '  maxY = %s,\n' ..
        '  maxZ = %s,\n' ..
        '  referenceSize = %s,\n' ..
        '  subZoneName = \'%s\'\n' ..
        '}',
        floorId,
        format_number(data.scalingX),
        format_number(data.offsetX),
        format_number(data.scalingY),
        format_number(data.offsetY),
        format_number(data.minX),
        format_number(data.minY),
        format_number(data.minZ),
        format_number(data.maxX),
        format_number(data.maxY),
        format_number(data.maxZ),
        format_number(data.referenceSize),
        json_escape(subZone)
    )
end

local function calc_input_width(label)
    local availWidth = imgui.GetContentRegionAvail()
    local labelWidth = select(1, imgui.CalcTextSize(label))
    local spacing = 8
    local inputWidth = availWidth - labelWidth - spacing
    if inputWidth < 80 then
        inputWidth = 80
    end
    return inputWidth
end

local function draw_float_input(state, data, key, label, step, stepFast, format, labelColor)
    local inputWidth = calc_input_width(label)
    imgui.AlignTextToFramePadding()
    if labelColor then
        imgui.PushStyleColor(ImGuiCol_Text, labelColor)
    end
    imgui.Text(label)
    if labelColor then
        imgui.PopStyleColor()
    end
    imgui.SameLine()
    imgui.SetNextItemWidth(inputWidth)
    if imgui.InputFloat('##' .. key, state.edit[key], step or 0.1, stepFast or 1.0, format or '%.3f') then
        data[key] = state.edit[key][1]
    end
end

local function draw_int_input(state, data, key, label, step, stepFast, labelColor)
    local inputWidth = calc_input_width(label)
    imgui.AlignTextToFramePadding()
    if labelColor then
        imgui.PushStyleColor(ImGuiCol_Text, labelColor)
    end
    imgui.Text(label)
    if labelColor then
        imgui.PopStyleColor()
    end
    imgui.SameLine()
    imgui.SetNextItemWidth(inputWidth)
    if imgui.InputInt('##' .. key, state.edit[key], step or 1, stepFast or 10, ImGuiInputTextFlags_CharsDecimal) then
        data[key] = state.edit[key][1]
    end
end

local function draw_text_input(state, data, key, label, maxLen, labelColor)
    local inputWidth = calc_input_width(label)
    imgui.AlignTextToFramePadding()
    if labelColor then
        imgui.PushStyleColor(ImGuiCol_Text, labelColor)
    end
    imgui.Text(label)
    if labelColor then
        imgui.PopStyleColor()
    end
    imgui.SameLine()
    imgui.SetNextItemWidth(inputWidth)
    if imgui.InputText('##' .. key, state.edit[key], maxLen or 64) then
        data[key] = state.edit[key][1]
    end
end

function map_data_editor.draw_window()
    local state = ensure_state()

    if not state.visible[1] then
        return
    end

    imgui.SetNextWindowSize({ 560, 540 }, ImGuiCond_FirstUseEver)
    if not imgui.Begin('Map data editor', state.visible) then
        imgui.End()
        return
    end

    local zoneId = get_current_zone_id()
    local zoneData = map.get_custom_map_zone_data(zoneId)

    if not zoneData then
        imgui.Text('No custom floors for this zone.')
        imgui.End()
        return
    end

    ensure_selection(state, zoneId, zoneData)

    local floors = get_sorted_floors(zoneData)

    local listAvailWidth = imgui.GetContentRegionAvail()
    local editorMinWidth = 260

    local maxLabelWidth = 0
    for _, floorId in ipairs(floors) do
        local floorData = zoneData[floorId]
        local label = tostring(floorId)
        if floorData and floorData.subZoneName and floorData.subZoneName ~= '' then
            label = string.format('%d - %s', floorId, floorData.subZoneName)
        end
        local labelWidth = select(1, imgui.CalcTextSize(label))
        if labelWidth > maxLabelWidth then
            maxLabelWidth = labelWidth
        end
    end

    local itemHeight = imgui.GetTextLineHeight()
    local eyeText = ICON_FA_EYE
    local eyeTextW = select(1, imgui.CalcTextSize(eyeText))
    local iconColumnWidth = math.max(itemHeight + 2, eyeTextW + 6)
    local idealListWidth = maxLabelWidth + iconColumnWidth + 24
    local maxListWidth = math.max(160, listAvailWidth - editorMinWidth)
    local listWidth = math.min(idealListWidth, maxListWidth)

    imgui.BeginGroup()

    if imgui.BeginPopupModal('Delete custom floor', nil, ImGuiWindowFlags_AlwaysAutoResize) then
        imgui.Text('Delete the selected floor? This cannot be undone.')
        imgui.Separator()
        if state.selectedFloorId == nil or zoneData[state.selectedFloorId] == nil then
            state.deleteFloor.error = 'No valid floor is selected.'
        else
            state.deleteFloor.error = ''
        end

        if state.deleteFloor.error ~= '' then
            imgui.TextColored({ 1.0, 0.4, 0.4, 1.0 }, state.deleteFloor.error)
        end

        local canConfirm = state.deleteFloor.error == ''
        if not canConfirm then
            imgui.BeginDisabled()
        end
        if imgui.Button('Delete', { 120, 0 }) then
            zoneData[state.selectedFloorId] = nil
            state.selectedFloorId = nil
            ensure_selection(state, zoneId, zoneData)
            imgui.CloseCurrentPopup()
        end
        if not canConfirm then
            imgui.EndDisabled()
        end

        imgui.SameLine()
        if imgui.Button('Cancel', { 120, 0 }) then
            imgui.CloseCurrentPopup()
        end

        imgui.EndPopup()
    end

    if imgui.BeginPopupModal('Add custom floor', nil, ImGuiWindowFlags_AlwaysAutoResize) then
        imgui.Text('Create a new virtual floor for this zone.')
        imgui.Separator()
        imgui.InputInt('Floor Id', state.addFloor.id, 1, 10, ImGuiInputTextFlags_CharsDecimal)
        imgui.InputText('Sub Zone Name', state.addFloor.subZoneName, 64)
        imgui.Checkbox('Copy from selected floor', state.addFloor.copyFromSelected)

        local newId = tonumber(state.addFloor.id[1])
        local error = ''
        if not newId or newId ~= math.floor(newId) then
            error = 'Floor Id must be an integer.'
        elseif newId < 0 then
            error = 'Floor Id must be 0 or higher.'
        elseif zoneData[newId] then
            error = 'Floor Id already exists.'
        end
        state.addFloor.error = error

        if state.addFloor.error ~= '' then
            imgui.TextColored({ 1.0, 0.4, 0.4, 1.0 }, state.addFloor.error)
        end

        local canCreate = state.addFloor.error == ''
        if not canCreate then
            imgui.BeginDisabled()
        end
        if imgui.Button('Create', { 120, 0 }) then
            local base = nil
            if state.addFloor.copyFromSelected[1] and state.selectedFloorId and zoneData[state.selectedFloorId] then
                base = zoneData[state.selectedFloorId]
            end
            zoneData[newId] = build_new_floor_data(base, state.addFloor.subZoneName[1])
            state.selectedFloorId = newId
            reset_edit_state(state, zoneData[newId])
            imgui.CloseCurrentPopup()
        end
        if not canCreate then
            imgui.EndDisabled()
        end

        imgui.SameLine()
        if imgui.Button('Cancel', { 120, 0 }) then
            imgui.CloseCurrentPopup()
        end

        imgui.EndPopup()
    end

    if imgui.BeginChild('##CustomFloors', { listWidth, -86 }, ImGuiChildFlags_Borders) then
        local drawList = imgui.GetWindowDrawList()

        local currentFloorId = nil
        if map.current_map_data and map.current_map_data.entry then
            currentFloorId = map.current_map_data.entry.FloorId
        end

        local innerAvailWidth = imgui.GetContentRegionAvail()
        local nameColumnWidth = math.max(60, innerAvailWidth - iconColumnWidth - 4)

        local tintR, tintG, tintB, tintA = imgui.GetStyleColorVec4(ImGuiCol_Text)
        if type(tintR) == 'table' then
            tintG = tintR[2]
            tintB = tintR[3]
            tintA = tintR[4]
            tintR = tintR[1]
        end
        local tintColor = utils.rgb_to_abgr({ tintR or 1.0, tintG or 1.0, tintB or 1.0, tintA or 1.0 })

        if imgui.BeginTable('##MapDataFloorTable', 2, 0, { innerAvailWidth, 0 }) then
            imgui.TableSetupColumn('##FloorName', ImGuiTableColumnFlags_WidthFixed, nameColumnWidth)
            imgui.TableSetupColumn('##FloorSwitch', ImGuiTableColumnFlags_WidthFixed, iconColumnWidth)

            for _, floorId in ipairs(floors) do
                local floorData = zoneData[floorId]
                local label = tostring(floorId)
                if floorData and floorData.subZoneName and floorData.subZoneName ~= '' then
                    label = string.format('%d - %s', floorId, floorData.subZoneName)
                end

                imgui.TableNextRow()
                imgui.TableSetColumnIndex(0)

                imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 0, 0 })
                if currentFloorId ~= nil and floorId == currentFloorId then
                    local colR, colG, colB, colA = imgui.GetStyleColorVec4(ImGuiCol_ButtonHovered)
                    if type(colR) == 'table' then
                        colG = colR[2]
                        colB = colR[3]
                        colA = colR[4]
                        colR = colR[1]
                    end
                    imgui.PushStyleColor(ImGuiCol_Text, { colR or 1.0, colG or 1.0, colB or 1.0, colA or 1.0 })
                end
                if imgui.Selectable(label .. '##floor' .. floorId, state.selectedFloorId == floorId, 0, { 0, itemHeight }) then
                    state.selectedFloorId = floorId
                    reset_edit_state(state, floorData)
                end
                if currentFloorId ~= nil and floorId == currentFloorId then
                    imgui.PopStyleColor()
                end
                imgui.PopStyleVar()

                imgui.TableSetColumnIndex(1)
                imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { 0, 0 })
                if imgui.InvisibleButton('##eye' .. floorId, { iconColumnWidth, itemHeight }) then
                    boussole.manualZoneId[1] = zoneId
                    boussole.manualFloorId[1] = floorId
                    boussole.manualMapReload[1] = true
                end
                if imgui.IsItemHovered() then
                    local rectMinX, rectMinY = imgui.GetItemRectMin()
                    local rectMaxX, rectMaxY = imgui.GetItemRectMax()
                    local textX = rectMinX + ((rectMaxX - rectMinX - eyeTextW) / 2)
                    local textY = rectMinY + ((rectMaxY - rectMinY - itemHeight) / 2)
                    drawList:AddText({ textX, textY }, tintColor, eyeText)
                end
                imgui.PopStyleVar()
            end

            imgui.EndTable()
        end
    end
    imgui.EndChild()

    if imgui.Button(ICON_FA_SQUARE_PLUS .. ' Add floor', { listWidth, 0 }) then
        state.addFloor.id[1] = get_next_floor_id(zoneData)
        state.addFloor.subZoneName[1] = ''
        state.addFloor.copyFromSelected[1] = true
        state.addFloor.error = ''
        imgui.OpenPopup('Add custom floor')
    end

    local canDelete = state.selectedFloorId ~= nil and zoneData[state.selectedFloorId] ~= nil
    if not canDelete then
        imgui.BeginDisabled()
    end
    if imgui.Button(ICON_FA_SQUARE_MINUS .. ' Delete floor', { listWidth, 0 }) then
        state.deleteFloor.error = ''
        imgui.OpenPopup('Delete custom floor')
    end
    if not canDelete then
        imgui.EndDisabled()
    end

    if imgui.Button(ICON_FA_CLIPBOARD .. ' Copy JSON', { listWidth, 0 }) then
        local json = '[' .. zoneId .. '] = {\n'
        local sortedFloors = get_sorted_floors(zoneData)
        for i, floorId in ipairs(sortedFloors) do
            local floorData = zoneData[floorId]
            local entry = build_json_entry(floorId, floorData)
            -- Indent each line of the entry
            entry = '    ' .. entry:gsub('\n', '\n    ')
            json = json .. entry
            if i < #sortedFloors then
                json = json .. ','
            end
            json = json .. '\n'
        end
        json = json .. '},'
        if ashita.misc.set_clipboard(json) then
            state.lastCopiedAt = os.clock()
        else
            state.lastCopiedAt = 0
        end
    end

    imgui.EndGroup()

    imgui.SameLine()

    if imgui.BeginChild('##CustomFloorEditor', { -1, -1 }, ImGuiChildFlags_Borders) then
        if not state.selectedFloorId then
            imgui.Text('Select a custom floor to edit.')
        else
            local floorData = zoneData[state.selectedFloorId]
            if not floorData then
                imgui.Text('Invalid floor selection.')
            else
                imgui.Text(string.format('Zone %d | Floor %d', zoneId, state.selectedFloorId))
                imgui.Separator()

                imgui.SeparatorText(ICON_FA_DOWN_LEFT_AND_UP_RIGHT_TO_CENTER .. ' Scaling & Offset')
                draw_float_input(state, floorData, 'scalingX', 'Scaling X', 0.01, 0.1, '%.4f')
                draw_float_input(state, floorData, 'scalingY', 'Scaling Y', 0.01, 0.1, '%.4f')
                draw_float_input(state, floorData, 'offsetX', 'Offset X', 1.0, 10.0, '%.3f')
                draw_float_input(state, floorData, 'offsetY', 'Offset Y', 1.0, 10.0, '%.3f')

                imgui.SeparatorText(ICON_FA_EXPAND .. ' Bounds')
                imgui.Checkbox('Draw borders (2D)', state.drawBorders2D)
                imgui.Checkbox('Draw borders (3D)', state.drawBorders3D)
                imgui.Spacing()

                local camX, camY, camZ = get_camera_position()
                local camReady = camX ~= nil and camY ~= nil and camZ ~= nil

                if not camReady then
                    imgui.BeginDisabled()
                end

                local btnSize = 16
                local bottomLeftIcon = load_camera_button_texture('bottom-left')
                local bottomRightIcon = load_camera_button_texture('bottom-right')
                local topRightIcon = load_camera_button_texture('top-right')
                local topLeftIcon = load_camera_button_texture('top-left')
                local leftIcon = load_camera_button_texture('left')
                local rightIcon = load_camera_button_texture('right')
                local bottomIcon = load_camera_button_texture('bottom')
                local topIcon = load_camera_button_texture('top')
                local heightBottomIcon = load_camera_button_texture('height-bottom')
                local heightTopIcon = load_camera_button_texture('height-top')

                if bottomLeftIcon then
                    if imgui.ImageButton('##camBtnBottomLeft', bottomLeftIcon, { btnSize, btnSize }) then
                        floorData.minX = camX
                        floorData.minY = camY
                        state.edit.minX[1] = camX
                        state.edit.minY[1] = camY
                    end
                else
                    if imgui.Button('MinX/MinY', { btnSize, 0 }) then
                        floorData.minX = camX
                        floorData.minY = camY
                        state.edit.minX[1] = camX
                        state.edit.minY[1] = camY
                    end
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Set MinX/MinY to camera position')
                end
                imgui.SameLine()
                if bottomRightIcon then
                    if imgui.ImageButton('##camBtnBottomRight', bottomRightIcon, { btnSize, btnSize }) then
                        floorData.maxX = camX
                        floorData.minY = camY
                        state.edit.maxX[1] = camX
                        state.edit.minY[1] = camY
                    end
                else
                    if imgui.Button('MaxX/MinY', { btnSize, 0 }) then
                        floorData.maxX = camX
                        floorData.minY = camY
                        state.edit.maxX[1] = camX
                        state.edit.minY[1] = camY
                    end
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Set MaxX/MinY to camera position')
                end
                imgui.SameLine()
                if topRightIcon then
                    if imgui.ImageButton('##camBtnTopRight', topRightIcon, { btnSize, btnSize }) then
                        floorData.maxX = camX
                        floorData.maxY = camY
                        state.edit.maxX[1] = camX
                        state.edit.maxY[1] = camY
                    end
                else
                    if imgui.Button('MaxX/MaxY', { btnSize, 0 }) then
                        floorData.maxX = camX
                        floorData.maxY = camY
                        state.edit.maxX[1] = camX
                        state.edit.maxY[1] = camY
                    end
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Set MaxX/MaxY to camera position')
                end
                imgui.SameLine()
                if topLeftIcon then
                    if imgui.ImageButton('##camBtnTopLeft', topLeftIcon, { btnSize, btnSize }) then
                        floorData.minX = camX
                        floorData.maxY = camY
                        state.edit.minX[1] = camX
                        state.edit.maxY[1] = camY
                    end
                else
                    if imgui.Button('MinX/MaxY', { btnSize, 0 }) then
                        floorData.minX = camX
                        floorData.maxY = camY
                        state.edit.minX[1] = camX
                        state.edit.maxY[1] = camY
                    end
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Set MinX/MaxY to camera position')
                end
                imgui.SameLine()
                imgui.Dummy({ 4, 0 })
                imgui.SameLine()
                if leftIcon then
                    if imgui.ImageButton('##camBtnLeft', leftIcon, { btnSize, btnSize }) then
                        floorData.minX = camX
                        state.edit.minX[1] = camX
                    end
                else
                    if imgui.Button('Left', { btnSize, 0 }) then
                        floorData.minX = camX
                        state.edit.minX[1] = camX
                    end
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Set MinX to camera position')
                end
                imgui.SameLine()
                if rightIcon then
                    if imgui.ImageButton('##camBtnRight', rightIcon, { btnSize, btnSize }) then
                        floorData.maxX = camX
                        state.edit.maxX[1] = camX
                    end
                else
                    if imgui.Button('Right', { btnSize, 0 }) then
                        floorData.maxX = camX
                        state.edit.maxX[1] = camX
                    end
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Set MaxX to camera position')
                end
                imgui.SameLine()
                if bottomIcon then
                    if imgui.ImageButton('##camBtnBottom', bottomIcon, { btnSize, btnSize }) then
                        floorData.minY = camY
                        state.edit.minY[1] = camY
                    end
                else
                    if imgui.Button('Bottom', { btnSize, 0 }) then
                        floorData.minY = camY
                        state.edit.minY[1] = camY
                    end
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Set MinY to camera position')
                end
                imgui.SameLine()
                if topIcon then
                    if imgui.ImageButton('##camBtnTop', topIcon, { btnSize, btnSize }) then
                        floorData.maxY = camY
                        state.edit.maxY[1] = camY
                    end
                else
                    if imgui.Button('Top', { btnSize, 0 }) then
                        floorData.maxY = camY
                        state.edit.maxY[1] = camY
                    end
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Set MaxY to camera position')
                end
                imgui.SameLine()
                imgui.Dummy({ 4, 0 })
                imgui.SameLine()
                if heightBottomIcon then
                    if imgui.ImageButton('##camBtnHeightBottom', heightBottomIcon, { btnSize, btnSize }) then
                        floorData.minZ = camZ
                        state.edit.minZ[1] = camZ
                    end
                else
                    if imgui.Button('MinZ', { btnSize, 0 }) then
                        floorData.minZ = camZ
                        state.edit.minZ[1] = camZ
                    end
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Set MinZ to camera height')
                end
                imgui.SameLine()
                if heightTopIcon then
                    if imgui.ImageButton('##camBtnHeightTop', heightTopIcon, { btnSize, btnSize }) then
                        floorData.maxZ = camZ
                        state.edit.maxZ[1] = camZ
                    end
                else
                    if imgui.Button('MaxZ', { btnSize, 0 }) then
                        floorData.maxZ = camZ
                        state.edit.maxZ[1] = camZ
                    end
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Set MaxZ to camera height')
                end
                if not camReady then
                    imgui.EndDisabled()
                end
                imgui.Spacing()

                draw_float_input(state, floorData, 'minX', 'Min X', 1.0, 10.0, '%.2f', bounds_label_colors.minX)
                draw_float_input(state, floorData, 'maxX', 'Max X', 1.0, 10.0, '%.2f', bounds_label_colors.maxX)
                draw_float_input(state, floorData, 'minY', 'Min Y', 1.0, 10.0, '%.2f', bounds_label_colors.minY)
                draw_float_input(state, floorData, 'maxY', 'Max Y', 1.0, 10.0, '%.2f', bounds_label_colors.maxY)
                draw_float_input(state, floorData, 'minZ', 'Min Z', 1.0, 10.0, '%.2f')
                draw_float_input(state, floorData, 'maxZ', 'Max Z', 1.0, 10.0, '%.2f')

                imgui.SeparatorText(ICON_FA_DISPLAY .. ' Display')
                draw_int_input(state, floorData, 'referenceSize', 'Reference size', 1, 16)
                draw_text_input(state, floorData, 'subZoneName', 'Sub-zone name', 64)

                imgui.Spacing()
                if imgui.Button(ICON_FA_CLIPBOARD .. ' Copy JSON entry', { -1, 0 }) then
                    local json = build_json_entry(state.selectedFloorId, floorData)
                    if ashita.misc.set_clipboard(json) then
                        state.lastCopiedAt = os.clock()
                    else
                        state.lastCopiedAt = 0
                    end
                end

                if state.lastCopiedAt > 0 and (os.clock() - state.lastCopiedAt) < 2.0 then
                    imgui.Text(ICON_FA_CHECK .. ' Copied to clipboard.')
                end
            end
        end
    end
    imgui.EndChild()

    imgui.End()
end

function map_data_editor.draw_world_bounds()
    local state = ensure_state()
    if not state.visible[1] or not state.drawBorders3D[1] then
        return
    end

    local zoneId = get_current_zone_id()
    local zoneData = map.get_custom_map_zone_data(zoneId)
    if not zoneData or not state.selectedFloorId then
        return
    end

    local floorData = zoneData[state.selectedFloorId]
    if not floorData then
        return
    end

    local function rgb_to_argb(rgbaTable)
        if not rgbaTable or #rgbaTable < 3 then
            return 0xFFFFFFFF
        end
        local r = math.floor((rgbaTable[1] or 1.0) * 255)
        local g = math.floor((rgbaTable[2] or 1.0) * 255)
        local b = math.floor((rgbaTable[3] or 1.0) * 255)
        local a = math.floor((rgbaTable[4] or 1.0) * 255)
        return bit.bor(
            bit.lshift(a, 24),
            bit.lshift(r, 16),
            bit.lshift(g, 8),
            b
        )
    end

    local minZ = floorData.minZ or 0
    local maxZ = floorData.maxZ or 0

    local function with_alpha(colorTable, alpha)
        return {
            colorTable[1] or 1.0,
            colorTable[2] or 1.0,
            colorTable[3] or 1.0,
            alpha
        }
    end

    local faceColors = {
        minY = rgb_to_argb(with_alpha(bounds_label_colors.minY, 0.2)),
        maxX = rgb_to_argb(with_alpha(bounds_label_colors.maxX, 0.2)),
        maxY = rgb_to_argb(with_alpha(bounds_label_colors.maxY, 0.2)),
        minX = rgb_to_argb(with_alpha(bounds_label_colors.minX, 0.2)),
        minZ = rgb_to_argb({ 0.6, 0.6, 0.6, 0.14 }),
        maxZ = rgb_to_argb({ 0.6, 0.6, 0.6, 0.14 })
    }

    world_drawing:DrawBox(
        floorData.minX, floorData.minY, minZ,
        floorData.maxX, floorData.maxY, maxZ,
        faceColors
    )

    local edgeColors = {
        rgb_to_argb(bounds_label_colors.minY),
        rgb_to_argb(bounds_label_colors.maxX),
        rgb_to_argb(bounds_label_colors.maxY),
        rgb_to_argb(bounds_label_colors.minX)
    }

    local function draw_edges(z)
        local p1 = { X = floorData.minX, Y = floorData.minY, Z = z }
        local p2 = { X = floorData.maxX, Y = floorData.minY, Z = z }
        local p3 = { X = floorData.maxX, Y = floorData.maxY, Z = z }
        local p4 = { X = floorData.minX, Y = floorData.maxY, Z = z }

        world_drawing:DrawLine(p1, p2, edgeColors[1])
        world_drawing:DrawLine(p2, p3, edgeColors[2])
        world_drawing:DrawLine(p3, p4, edgeColors[3])
        world_drawing:DrawLine(p4, p1, edgeColors[4])
    end

    draw_edges(minZ)
    draw_edges(maxZ)
end

function map_data_editor.draw_bounds(mapData, windowPosX, windowPosY, contentMinX, contentMinY, mapOffsetX, mapOffsetY, mapZoom, textureWidth)
    local state = ensure_state()

    if not state.visible[1] then
        return
    end

    if not state.drawBorders2D[1] then
        return
    end

    if not mapData or not mapData.entry or not mapData.entry._isCustomMap then
        return
    end

    local zoneId = mapData.entry.ZoneId
    local floorId = mapData.entry.FloorId
    if state.selectedZoneId ~= zoneId or state.selectedFloorId ~= floorId then
        return
    end

    local floorData = map.get_custom_map_data(zoneId, floorId)
    if not floorData then
        return
    end

    local refSize = floorData.referenceSize or 512.0
    local scale = textureWidth / refSize

    local corners = {
        { floorData.minX, floorData.minY },
        { floorData.maxX, floorData.minY },
        { floorData.maxX, floorData.maxY },
        { floorData.minX, floorData.maxY }
    }

    local screenPoints = {}
    for i = 1, 4 do
        local mapX, mapY = map.world_to_map_coords(mapData.entry, corners[i][1], corners[i][2], 0)
        if not mapX or not mapY then
            return
        end

        local texX = (mapX - mapData.entry.OffsetX) * scale
        local texY = (mapY - mapData.entry.OffsetY) * scale

        screenPoints[i] = {
            x = windowPosX + contentMinX + mapOffsetX + texX * mapZoom,
            y = windowPosY + contentMinY + mapOffsetY + texY * mapZoom
        }
    end

    local colors = {
        utils.rgb_to_abgr(bounds_label_colors.minY),
        utils.rgb_to_abgr(bounds_label_colors.maxX),
        utils.rgb_to_abgr(bounds_label_colors.maxY),
        utils.rgb_to_abgr(bounds_label_colors.minX)
    }

    local lineLabels = { 'Min Y', 'Max X', 'Max Y', 'Min X' }

    local drawList = imgui.GetWindowDrawList()
    local labelBg = 0xAA000000

    local centerX = (screenPoints[1].x + screenPoints[2].x + screenPoints[3].x + screenPoints[4].x) / 4
    local centerY = (screenPoints[1].y + screenPoints[2].y + screenPoints[3].y + screenPoints[4].y) / 4

    -- Draw lines and place labels evenly along each edge
    local labels = {}
    local padding = 2

    local function add_label_at(centerX, centerY, text, color)
        local textWidth, textHeight = imgui.CalcTextSize(text)
        local width = textWidth + (padding * 2)
        local height = textHeight + (padding * 2)
        table.insert(labels, {
            text = text,
            color = color,
            x1 = centerX - (width / 2),
            y1 = centerY - (height / 2),
            x2 = centerX + (width / 2),
            y2 = centerY + (height / 2),
            textX = centerX - (textWidth / 2),
            textY = centerY - (textHeight / 2)
        })
    end

    local function add_edge_labels(p1, p2, label, color)
        local dx = p2.x - p1.x
        local dy = p2.y - p1.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 1 then
            return
        end

        local dirX = dx / len
        local dirY = dy / len
        local midX = (p1.x + p2.x) / 2
        local midY = (p1.y + p2.y) / 2

        local outX = midX - centerX
        local outY = midY - centerY
        local outLen = math.sqrt(outX * outX + outY * outY)
        if outLen > 0 then
            outX = outX / outLen
            outY = outY / outLen
        else
            outX = 0
            outY = -1
        end

        local inset = math.min(16, math.max(6, len * 0.12))
        local normalOffset = 18

        local startX = p1.x + (dirX * inset) + (outX * normalOffset)
        local startY = p1.y + (dirY * inset) + (outY * normalOffset)
        local endX = p2.x - (dirX * inset) + (outX * normalOffset)
        local endY = p2.y - (dirY * inset) + (outY * normalOffset)

        add_label_at(startX, startY, string.format('%s (start)', label), color)
        add_label_at(endX, endY, string.format('%s (end)', label), color)
    end

    drawList:AddLine({ screenPoints[1].x, screenPoints[1].y }, { screenPoints[2].x, screenPoints[2].y }, colors[1], 2.0)
    add_edge_labels(screenPoints[1], screenPoints[2], lineLabels[1], colors[1])

    drawList:AddLine({ screenPoints[2].x, screenPoints[2].y }, { screenPoints[3].x, screenPoints[3].y }, colors[2], 2.0)
    add_edge_labels(screenPoints[2], screenPoints[3], lineLabels[2], colors[2])

    drawList:AddLine({ screenPoints[3].x, screenPoints[3].y }, { screenPoints[4].x, screenPoints[4].y }, colors[3], 2.0)
    add_edge_labels(screenPoints[3], screenPoints[4], lineLabels[3], colors[3])

    drawList:AddLine({ screenPoints[4].x, screenPoints[4].y }, { screenPoints[1].x, screenPoints[1].y }, colors[4], 2.0)
    add_edge_labels(screenPoints[4], screenPoints[1], lineLabels[4], colors[4])

    for _, label in ipairs(labels) do
        drawList:AddRectFilled({ label.x1, label.y1 }, { label.x2, label.y2 }, labelBg)
        drawList:AddText({ label.textX, label.textY }, label.color, label.text)
    end

    local camX, camY, camZ = get_camera_position()
    if camX ~= nil and camY ~= nil and camZ ~= nil then
        local mapX, mapY = map.world_to_map_coords(mapData.entry, camX, camY, camZ)
        if mapX and mapY then
            local texX = (mapX - mapData.entry.OffsetX) * scale
            local texY = (mapY - mapData.entry.OffsetY) * scale

            local screenX = windowPosX + contentMinX + mapOffsetX + texX * mapZoom
            local screenY = windowPosY + contentMinY + mapOffsetY + texY * mapZoom

            local cursorId = get_camera_cursor_texture_id()
            if cursorId then
                local cursorSize = boussole.config.iconSizePlayer[1] or 20.0
                local halfSize = cursorSize / 2
                drawList:AddImage(cursorId,
                    { screenX - halfSize, screenY - halfSize },
                    { screenX + halfSize, screenY + halfSize },
                    { 0, 0 }, { 1, 1 },
                    0xFFFFFFFF)
            else
                drawList:AddCircleFilled({ screenX, screenY }, 4, 0xFFFFFFFF)
            end
        end
    end
end

return map_data_editor
