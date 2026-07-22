local custom_points = {}

local imgui = require('imgui')
local chat = require('chat')
local utils = require('src.utils')
local settings = require('settings')
local tooltip = require('src.overlays.tooltip')
local json = require('json')
local ffi = require('ffi')
local d3d8 = require('d3d8')

local C = ffi.C

-- Check if a table uses only string/mixed keys with no integer sequence part (old dict format)
local function is_old_dict_format(t)
    if type(t) ~= 'table' then return false end
    if #t > 0 then return false end      -- has sequence part, already an array
    for _ in pairs(t) do return true end -- non empty with no seq keys, dict
    return false
end

-- Convert an old { pointId -> point } dict to an ordered array with the id embedded
local function dict_to_array(dict)
    local arr = {}
    for id, point in pairs(dict) do
        local entry = {}
        for k, v in pairs(point) do entry[k] = v end
        entry.id = id
        table.insert(arr, entry)
    end
    return arr
end

-- Helper to recursively flatten the tree for drawing and hit detection.
-- Computes the full path (e.g. "Folder1/Folder2/PointName") for tooltips.
local function flatten_visible_points(items, current_path, parent_visible, out_list)
    for _, item in ipairs(items) do
        local is_visible = parent_visible and (item.visible ~= false)
        local item_name = (item.name ~= nil and item.name ~= '') and item.name or '(unnamed)'
        local full_path = current_path == '' and item_name or (current_path .. '/' .. item_name)

        if item.type == 'folder' then
            if item.children then
                flatten_visible_points(item.children, full_path, is_visible, out_list)
            end
        else
            if is_visible then
                out_list[#out_list + 1] = {
                    point = item,
                    fullPath = full_path
                }
            end
        end
    end
end

-- Helper to recursively find an item and its containing list
local function find_item_and_parent(items, id)
    for i, item in ipairs(items) do
        if item.id == id then
            return item, items, i
        end
        if item.type == 'folder' and item.children then
            local found_item, found_parent, found_index = find_item_and_parent(item.children, id)
            if found_item then
                return found_item, found_parent, found_index
            end
        end
    end
    return nil, nil, nil
end

-- Helper to clone a table deeply and regenerate UUIDs
local function deep_clone_and_reid(item, zoneId, floorId)
    local clone = {}
    for k, v in pairs(item) do
        if type(v) == 'table' then
            if k == 'children' then
                clone.children = {}
                for _, child in ipairs(v) do
                    table.insert(clone.children, deep_clone_and_reid(child, zoneId, floorId))
                end
            else
                -- clone array like color
                local arr_clone = {}
                for ak, av in pairs(v) do arr_clone[ak] = av end
                clone[k] = arr_clone
            end
        else
            clone[k] = v
        end
    end
    -- Generate a new ID to avoid collisions
    local x = item.mapX and math.floor(item.mapX) or 0
    local y = item.mapY and math.floor(item.mapY) or 0
    clone.id = string.format('%d_%d_%d_%d_%d_%04d', os.time(), zoneId, floorId, x, y, math.random(0, 9999))
    return clone
end

-- Icon shapes
custom_points.ICON_SHAPES = {
    'Dot',
    'Square',
    'Triangle',
    'Diamond',
    'Cross',
    'Custom Image'
}

-- Texture cache for custom images
custom_points.texture_cache = {}
custom_points.data = {}

function custom_points.get_settings_path()
    if settings and type(settings.settings_path) == 'function' then
        return settings.settings_path()
    end
    return string.format('%s/config/addons/%s/defaults/', AshitaCore:GetInstallPath(), addon.name)
end

function custom_points.get_custom_points_path()
    local settingsPath = custom_points.get_settings_path()
    return settingsPath .. 'custom_points.json'
end

function custom_points.save_custom_points()
    local settingsPath = custom_points.get_settings_path()
    local filePath = custom_points.get_custom_points_path()

    ashita.fs.create_dir(settingsPath)

    local file = io.open(filePath, 'w')
    if file then
        file:write(json.encode({ points = custom_points.data }))
        file:close()
    end
end

function custom_points.load_custom_points()
    local filePath = custom_points.get_custom_points_path()
    local file = io.open(filePath, 'r')
    if not file then
        custom_points.data = {}
        return
    end

    local content = file:read('*all')
    file:close()

    local success, data = pcall(json.decode, content)
    if success and data and type(data.points) == 'table' then
        custom_points.data = data.points
    else
        custom_points.data = {}
    end

    -- upgrade any per-map dict entries left from the old format
    custom_points.upgrade_from_dict_format()
end

function custom_points.migrate_from_config(config)
    if not config or type(config.customPoints) ~= 'table' then
        return
    end

    local hadPoints = false
    custom_points.data = custom_points.data or {}
    for mapKey, points in pairs(config.customPoints) do
        if type(points) == 'table' then
            if not custom_points.data[mapKey] then
                custom_points.data[mapKey] = {}
            end
            -- Build a set of existing IDs to avoid duplicates
            local existingIds = {}
            for _, entry in ipairs(custom_points.data[mapKey]) do
                existingIds[entry.id] = true
            end
            for pointId, point in pairs(points) do
                hadPoints = true
                if not existingIds[pointId] then
                    local entry = {}
                    for k, v in pairs(point) do entry[k] = v end
                    entry.id = pointId
                    table.insert(custom_points.data[mapKey], entry)
                    existingIds[pointId] = true
                end
            end
        end
    end

    if hadPoints then
        custom_points.save_custom_points()
    end
    config.customPoints = nil
    settings.save()
end

-- Get custom icons folder path
function custom_points.get_custom_icons_folder()
    return string.format('%sconfig\\addons\\%s\\custom_icons\\',
        AshitaCore:GetInstallPath(),
        addon.name)
end

-- Load custom image texture
function custom_points.load_custom_image(imageName)
    if not imageName or imageName == '' then
        return nil
    end

    local folder = custom_points.get_custom_icons_folder()
    local imagePath = string.format('%s%s', folder, imageName)

    -- Check if already cached
    if custom_points.texture_cache[imageName] then
        return custom_points.texture_cache[imageName]
    end

    -- Try to load the image
    local d3d8dev = d3d8.get_device()
    if not d3d8dev then return nil end

    local texture_ptr = ffi.new('IDirect3DTexture8*[1]')
    local hr = ffi.C.D3DXCreateTextureFromFileA(d3d8dev, imagePath, texture_ptr)

    if hr == 0 then -- S_OK
        local texture_id = tonumber(ffi.cast('uint32_t', texture_ptr[0]))
        custom_points.texture_cache[imageName] = texture_id
        return texture_id
    end

    return nil
end

-- Clear texture cache for a specific image
function custom_points.clear_texture_cache(imageName)
    if custom_points.texture_cache[imageName] then
        local texture = ffi.cast('IDirect3DTexture8*', custom_points.texture_cache[imageName])
        if texture ~= nil then
            texture:Release()
        end
        custom_points.texture_cache[imageName] = nil
    end
end

-- Popup state
custom_points.popup_state = {
    open = false,
    editing = false,
    zoneId = 0,
    floorId = 0,
    mapX = 0,
    mapY = 0,
    pointId = nil,
    name = { '' },
    note = { '' },
    iconShape = { 1 },
    color = { 1.0, 1.0, 1.0, 1.0 },
    size = { 8 },
    imageName = { '' },
    applyColor = { false }
}

-- Generate unique ID for a point based on time, zone, floor, and position
function custom_points.generate_id(zoneId, floorId, mapX, mapY)
    local x = math.floor(mapX)
    local y = math.floor(mapY)
    return string.format('%d_%d_%d_%d_%d', os.time(), zoneId, floorId, x, y)
end

-- Get map key for zone/floor
function custom_points.get_map_key(zoneId, floorId)
    return string.format('%d_%d', zoneId, floorId)
end

-- Find point at given screen coordinates
function custom_points.find_point_at_position(zoneId, floorId, screenX, screenY, mapData, windowPosX, windowPosY, contentMinX, contentMinY, mapOffsetX, mapOffsetY, mapZoom, textureWidth)
    local mapKey = custom_points.get_map_key(zoneId, floorId)
    local points = custom_points.data[mapKey]

    if not points then return nil end

    local visible_points = {}
    flatten_visible_points(points, '', true, visible_points)

    for _, entryData in ipairs(visible_points) do
        local entry = entryData.point
        -- Convert map coordinates to texture pixel coordinates
        local texX = (entry.mapX - mapData.entry.OffsetX) * (textureWidth / 512.0)
        local texY = (entry.mapY - mapData.entry.OffsetY) * (textureWidth / 512.0)

        -- Convert to screen coordinates
        local pointScreenX = windowPosX + contentMinX + mapOffsetX + texX * mapZoom
        local pointScreenY = windowPosY + contentMinY + mapOffsetY + texY * mapZoom

        -- Use square hitbox based on point size
        local pointSize = entry.size or 8
        local halfSize = pointSize

        -- Check if click is within square bounds
        if screenX >= pointScreenX - halfSize and screenX <= pointScreenX + halfSize and
            screenY >= pointScreenY - halfSize and screenY <= pointScreenY + halfSize then
            return { id = entry.id, point = entry, fullPath = entryData.fullPath }
        end
    end

    return nil
end

-- Open popup to add a new point
function custom_points.open_add_popup(zoneId, floorId, mapX, mapY)
    custom_points.popup_state.open = true
    custom_points.popup_state.editing = false
    custom_points.popup_state.isFolder = false
    custom_points.popup_state.zoneId = zoneId
    custom_points.popup_state.floorId = floorId
    custom_points.popup_state.mapX = mapX
    custom_points.popup_state.mapY = mapY
    custom_points.popup_state.pointId = nil
    custom_points.popup_state.name = { '' }
    custom_points.popup_state.note = { '' }
    custom_points.popup_state.iconShape = { 1 }
    custom_points.popup_state.color = { 1.0, 1.0, 1.0, 1.0 }
    custom_points.popup_state.size = { 8 }
    custom_points.popup_state.imageName = { '' }
    custom_points.popup_state.applyColor = { false }
end

-- Open popup to edit an existing point
function custom_points.open_edit_popup(zoneId, floorId, pointId, point)
    custom_points.popup_state.open = true
    custom_points.popup_state.editing = true
    custom_points.popup_state.isFolder = false
    custom_points.popup_state.zoneId = zoneId
    custom_points.popup_state.floorId = floorId
    custom_points.popup_state.mapX = point.mapX
    custom_points.popup_state.mapY = point.mapY
    custom_points.popup_state.pointId = pointId
    custom_points.popup_state.name = { point.name or '' }
    custom_points.popup_state.note = { point.note or '' }
    custom_points.popup_state.iconShape = { point.iconShape or 1 }
    custom_points.popup_state.color = { point.color[1], point.color[2], point.color[3], point.color[4] }
    custom_points.popup_state.size = { point.size or 8 }
    custom_points.popup_state.imageName = { point.imageName or '' }
    custom_points.popup_state.applyColor = { point.applyColor or false }
end

-- Open popup to edit an existing folder
function custom_points.open_edit_folder_popup(zoneId, floorId, folderId, folder)
    custom_points.popup_state.open = true
    custom_points.popup_state.editing = true
    custom_points.popup_state.isFolder = true
    custom_points.popup_state.zoneId = zoneId
    custom_points.popup_state.floorId = floorId
    custom_points.popup_state.pointId = folderId
    custom_points.popup_state.name = { folder.name or '' }
end

-- Save point to config
function custom_points.save_point()
    local mapKey = custom_points.get_map_key(custom_points.popup_state.zoneId, custom_points.popup_state.floorId)

    if not custom_points.data[mapKey] then
        custom_points.data[mapKey] = {}
    end

    local pointId = custom_points.popup_state.pointId
    if not pointId then
        -- New point: generate id and append to the end of the array
        pointId = custom_points.generate_id(
            custom_points.popup_state.zoneId,
            custom_points.popup_state.floorId,
            custom_points.popup_state.mapX,
            custom_points.popup_state.mapY
        )
        table.insert(custom_points.data[mapKey], {
            id         = pointId,
            type       = 'point',
            visible    = true,
            mapX       = custom_points.popup_state.mapX,
            mapY       = custom_points.popup_state.mapY,
            name       = custom_points.popup_state.name[1],
            note       = custom_points.popup_state.note[1],
            iconShape  = custom_points.popup_state.iconShape[1],
            color      = {
                custom_points.popup_state.color[1],
                custom_points.popup_state.color[2],
                custom_points.popup_state.color[3],
                custom_points.popup_state.color[4]
            },
            size       = custom_points.popup_state.size[1],
            imageName  = custom_points.popup_state.imageName[1],
            applyColor = custom_points.popup_state.applyColor[1]
        })
    else
        -- Edit existing point: find it by id and update in place
        local points = custom_points.data[mapKey]
        local entry = find_item_and_parent(points, pointId)
        if entry then
            entry.name = custom_points.popup_state.name[1]
            if not custom_points.popup_state.isFolder then
                -- Clear texture cache if icon shape or image changed
                if entry.iconShape ~= custom_points.popup_state.iconShape[1] or
                    entry.imageName ~= custom_points.popup_state.imageName[1] then
                    if entry.imageName then
                        custom_points.clear_texture_cache(entry.imageName)
                    end
                end
                entry.mapX       = custom_points.popup_state.mapX
                entry.mapY       = custom_points.popup_state.mapY
                entry.note       = custom_points.popup_state.note[1]
                entry.iconShape  = custom_points.popup_state.iconShape[1]
                entry.color      = {
                    custom_points.popup_state.color[1],
                    custom_points.popup_state.color[2],
                    custom_points.popup_state.color[3],
                    custom_points.popup_state.color[4]
                }
                entry.size       = custom_points.popup_state.size[1]
                entry.imageName  = custom_points.popup_state.imageName[1]
                entry.applyColor = custom_points.popup_state.applyColor[1]
            end
        end
    end

    custom_points.save_custom_points()
    custom_points.popup_state.open = false
end

-- Delete point from config
function custom_points.delete_point()
    local mapKey = custom_points.get_map_key(custom_points.popup_state.zoneId, custom_points.popup_state.floorId)
    local points = custom_points.data[mapKey]

    if points and custom_points.popup_state.pointId then
        -- Clear texture cache if it exists
        custom_points.clear_texture_cache(custom_points.popup_state.imageName[1])

        local entry, parent_list, index = find_item_and_parent(points, custom_points.popup_state.pointId)
        if parent_list and index then
            table.remove(parent_list, index)
            custom_points.save_custom_points()
        end
    end

    custom_points.popup_state.open = false
end

-- Draw icon shape
function custom_points.draw_icon(drawList, screenX, screenY, shape, size, color, imageName, applyColor)
    if shape == 1 then -- Dot
        drawList:AddCircleFilled({ screenX, screenY }, size, color)
        drawList:AddCircle({ screenX, screenY }, size, 0xFFFFFFFF, 0, 1.0)
    elseif shape == 2 then -- Square
        local halfSize = size * 0.8
        drawList:AddRectFilled(
            { screenX - halfSize, screenY - halfSize },
            { screenX + halfSize, screenY + halfSize },
            color
        )
        drawList:AddRect(
            { screenX - halfSize, screenY - halfSize },
            { screenX + halfSize, screenY + halfSize },
            0xFFFFFFFF, 0.0, 0, 1.5
        )
    elseif shape == 3 then -- Triangle
        drawList:AddTriangleFilled(
            { screenX, screenY - size },
            { screenX - size * 0.866, screenY + size * 0.5 },
            { screenX + size * 0.866, screenY + size * 0.5 },
            color
        )
        drawList:AddTriangle(
            { screenX, screenY - size },
            { screenX - size * 0.866, screenY + size * 0.5 },
            { screenX + size * 0.866, screenY + size * 0.5 },
            0xFFFFFFFF, 1.5
        )
    elseif shape == 4 then -- Diamond
        drawList:AddTriangleFilled(
            { screenX, screenY - size },
            { screenX - size * 0.7, screenY },
            { screenX, screenY },
            color
        )
        drawList:AddTriangleFilled(
            { screenX, screenY - size },
            { screenX + size * 0.7, screenY },
            { screenX, screenY },
            color
        )
        drawList:AddTriangleFilled(
            { screenX, screenY + size },
            { screenX - size * 0.7, screenY },
            { screenX, screenY },
            color
        )
        drawList:AddTriangleFilled(
            { screenX, screenY + size },
            { screenX + size * 0.7, screenY },
            { screenX, screenY },
            color
        )
        drawList:AddLine({ screenX, screenY - size }, { screenX - size * 0.7, screenY }, 0xFFFFFFFF, 1.0)
        drawList:AddLine({ screenX - size * 0.7, screenY }, { screenX, screenY + size }, 0xFFFFFFFF, 1.0)
        drawList:AddLine({ screenX, screenY + size }, { screenX + size * 0.7, screenY }, 0xFFFFFFFF, 1.0)
        drawList:AddLine({ screenX + size * 0.7, screenY }, { screenX, screenY - size }, 0xFFFFFFFF, 1.0)
    elseif shape == 5 then          -- Cross (tilted 45 degrees)
        local thickness = size * 0.3
        local offset = size * 0.707 -- cos(45°) ≈ 0.707
        -- Diagonal lines (tilted cross)
        drawList:AddLine({ screenX - offset, screenY - offset }, { screenX + offset, screenY + offset }, color, thickness)
        drawList:AddLine({ screenX - offset, screenY + offset }, { screenX + offset, screenY - offset }, color, thickness)
    elseif shape == 6 then -- Custom Image
        if imageName then
            local textureId = custom_points.load_custom_image(imageName)
            if textureId then
                -- Draw custom image
                local halfSize = size
                local texture = ffi.cast('IDirect3DTexture8*', textureId)
                local imageColor = applyColor and color or 0xFFFFFFFF
                drawList:AddImage(
                    textureId,
                    { screenX - halfSize, screenY - halfSize },
                    { screenX + halfSize, screenY + halfSize },
                    { 0, 0 },
                    { 1, 1 },
                    imageColor
                )
                return
            end
        end
        -- Fall back to dot if image doesn't exist
        drawList:AddCircleFilled({ screenX, screenY }, size, color)
        drawList:AddCircle({ screenX, screenY }, size, 0xFFFFFFFF, 0, 1.0)
    end
end

-- Draw custom points on the map
function custom_points.draw(mapData, windowPosX, windowPosY, contentMinX, contentMinY, mapOffsetX, mapOffsetY, mapZoom, textureWidth)
    if not mapData then return end

    local zoneId = mapData.entry.ZoneId
    local floorId = mapData.entry.FloorId
    local mapKey = custom_points.get_map_key(zoneId, floorId)

    local points = custom_points.data[mapKey]
    if not points then return end

    local drawList = imgui.GetWindowDrawList()
    local mousePosX, mousePosY = imgui.GetMousePos()

    local visible_points = {}
    flatten_visible_points(points, '', true, visible_points)

    for _, entryData in ipairs(visible_points) do
        local point = entryData.point
        -- Convert map coordinates to texture pixel coordinates
        local texX, texY
        if mapData.entry._isCustomMap then
            texX = (point.mapX - mapData.entry.OffsetX) * (textureWidth / mapData.entry._customData.referenceSize)
            texY = (point.mapY - mapData.entry.OffsetY) * (textureWidth / mapData.entry._customData.referenceSize)
        else
            texX = (point.mapX - mapData.entry.OffsetX) * (textureWidth / 512.0)
            texY = (point.mapY - mapData.entry.OffsetY) * (textureWidth / 512.0)
        end

        -- Convert to screen coordinates
        local screenX = windowPosX + contentMinX + mapOffsetX + texX * mapZoom
        local screenY = windowPosY + contentMinY + mapOffsetY + texY * mapZoom

        -- Check hover using square hitbox based on point size
        local size = point.size or 8
        local halfSize = size
        local isHovered = mousePosX >= screenX - halfSize and mousePosX <= screenX + halfSize and
            mousePosY >= screenY - halfSize and mousePosY <= screenY + halfSize

        if isHovered then
            local color = utils.rgb_to_abgr(point.color)
            if entryData.fullPath and entryData.fullPath ~= '' then
                tooltip.add_line(entryData.fullPath, color)
            end
            if point.note and point.note ~= '' then
                if entryData.fullPath and entryData.fullPath ~= '' then
                    tooltip.add_separator()
                end
                for line in tostring(point.note):gmatch('[^\r\n]+') do
                    tooltip.add_line(line, color)
                end
            end
        end

        -- Draw icon
        local color = utils.rgb_to_abgr(point.color)
        custom_points.draw_icon(drawList, screenX, screenY, point.iconShape or 1, size, color, point.imageName, point.applyColor)
    end
end

-- Draw popup window
function custom_points.draw_popup()
    if not custom_points.popup_state.open then return end

    imgui.OpenPopup('Custom point')

    local size = custom_points.popup_state.editing and { 300, 550 } or { 300, 430 }
    if custom_points.popup_state.isFolder then
        size = { 300, 200 }
    end
    imgui.SetNextWindowSize(size, ImGuiCond_OnAppearing)
    if imgui.BeginPopupModal('Custom point', nil, bit.bor(ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoScrollWithMouse)) then
        imgui.Text(custom_points.popup_state.editing and (custom_points.popup_state.isFolder and 'Rename folder' or 'Edit custom point') or 'Add custom point')
        imgui.Separator()
        imgui.Spacing()

        -- Name input
        imgui.Text('Name:')
        imgui.SetNextItemWidth(-1)
        imgui.InputText('##Name', custom_points.popup_state.name, 128)
        imgui.Spacing()

        if not custom_points.popup_state.isFolder then
            -- Note input
            imgui.Text('Note:')
            imgui.SetNextItemWidth(-1)
            imgui.InputTextMultiline('##Note', custom_points.popup_state.note, 512, { -1, 80 })
            imgui.Spacing()

            -- Icon shape combo
            imgui.Text('Icon Shape:')
            imgui.SetNextItemWidth(-1)
            local currentShape = custom_points.ICON_SHAPES[custom_points.popup_state.iconShape[1]] or 'Dot'
            if imgui.BeginCombo('##IconShape', currentShape) then
                for i, shape in ipairs(custom_points.ICON_SHAPES) do
                    local isSelected = (custom_points.popup_state.iconShape[1] == i)
                    if imgui.Selectable(shape, isSelected) then
                        custom_points.popup_state.iconShape[1] = i
                    end
                end
                imgui.EndCombo()
            end
            imgui.Spacing()

            -- Image Name input (only show for Custom Image shape)
            if custom_points.popup_state.iconShape[1] == 6 then
                imgui.Text('Image Name:')
                imgui.SetNextItemWidth(-1)
                imgui.InputText('##ImageName', custom_points.popup_state.imageName, 128)
                imgui.Spacing()

                -- Apply color checkbox for custom images
                imgui.Checkbox('Apply Color Tint', custom_points.popup_state.applyColor)
                imgui.Spacing()
            end

            -- Size input
            imgui.Text('Size:')
            imgui.SetNextItemWidth(-1)
            if imgui.InputInt('##Size', custom_points.popup_state.size, 1, 2) then
                if custom_points.popup_state.size[1] < 4 then
                    custom_points.popup_state.size[1] = 4
                elseif custom_points.popup_state.size[1] > 20 then
                    custom_points.popup_state.size[1] = 20
                end
            end
            imgui.Spacing()

            -- Color picker
            imgui.Text('Color:')
            imgui.ColorEdit4('##Color', custom_points.popup_state.color)
            imgui.Spacing()
        end

        imgui.Separator()
        imgui.Spacing()

        -- Buttons
        local buttonWidth = custom_points.popup_state.editing and 80 or 120
        if imgui.Button('Save', { buttonWidth, 0 }) then
            custom_points.save_point()
        end

        imgui.SameLine()
        if imgui.Button('Cancel', { buttonWidth, 0 }) then
            custom_points.popup_state.open = false
        end
        -- Delete button
        if custom_points.popup_state.editing then
            local text = custom_points.popup_state.isFolder and 'Delete folder' or 'Delete point'
            if imgui.Button(text, { 140, 24 }) then
                custom_points.delete_point()
            end
        end

        imgui.EndPopup()
    end
end

function custom_points.upgrade_from_dict_format()
    local needsSave = false
    for mapKey, points in pairs(custom_points.data) do
        if is_old_dict_format(points) then
            custom_points.data[mapKey] = dict_to_array(points)
            needsSave = true
        end
    end
    if needsSave then
        custom_points.save_custom_points()
    end
end

-- Move a point from sourceId to a target position relative to targetId
-- dropAction: 'before', 'after', or 'into' (when targetId is a folder)
function custom_points.move_item(mapKey, sourceId, targetId, dropAction)
    local points = custom_points.data[mapKey]
    if not points then return end
    if sourceId == targetId then return end

    local sourceItem, sourceParent, sourceIndex = find_item_and_parent(points, sourceId)
    if not sourceItem then return end

    -- Remove from old position
    table.remove(sourceParent, sourceIndex)

    local targetItem, targetParent, targetIndex = find_item_and_parent(points, targetId)
    if not targetItem then
        -- fallback insert at root
        table.insert(points, sourceItem)
        custom_points.save_custom_points()
        return
    end

    if dropAction == 'into' and targetItem.type == 'folder' then
        targetItem.children = targetItem.children or {}
        table.insert(targetItem.children, sourceItem)
    elseif dropAction == 'before' then
        table.insert(targetParent, targetIndex, sourceItem)
    else -- 'after'
        table.insert(targetParent, targetIndex + 1, sourceItem)
    end

    custom_points.save_custom_points()
end

-- Create a new folder
function custom_points.create_folder(zoneId, floorId, parentId)
    local mapKey = custom_points.get_map_key(zoneId, floorId)
    if not custom_points.data[mapKey] then
        custom_points.data[mapKey] = {}
    end
    local points = custom_points.data[mapKey]

    local folder = {
        id = string.format('%d_%d_%d_%04d_folder', os.time(), zoneId, floorId, math.random(0, 9999)),
        type = 'folder',
        name = 'New Folder',
        visible = true,
        isExpanded = true,
        children = {}
    }

    if parentId then
        local targetItem = find_item_and_parent(points, parentId)
        if targetItem and targetItem.type == 'folder' then
            targetItem.children = targetItem.children or {}
            table.insert(targetItem.children, folder)
        else
            table.insert(points, folder)
        end
    else
        table.insert(points, folder)
    end

    custom_points.save_custom_points()
end

-- Global clipboard copy
function custom_points.copy_item(item)
    if not item then return end
    local j = json.encode(item)
    imgui.SetClipboardText(j)
end

-- Global clipboard paste
function custom_points.paste_item(zoneId, floorId, targetFolderId)
    local j = imgui.GetClipboardText()
    if not j or j == '' then return end

    local success, item = pcall(json.decode, j)
    if not success or type(item) ~= 'table' or not item.id then
        print(chat.header('boussole'):append(chat.error('Clipboard content is not a valid custom point or folder.')))
        return
    end

    local mapKey = custom_points.get_map_key(zoneId, floorId)
    if not custom_points.data[mapKey] then
        custom_points.data[mapKey] = {}
    end
    local points = custom_points.data[mapKey]

    local clone = deep_clone_and_reid(item, zoneId, floorId)

    if targetFolderId then
        local targetItem = find_item_and_parent(points, targetFolderId)
        if targetItem and targetItem.type == 'folder' then
            targetItem.children = targetItem.children or {}
            table.insert(targetItem.children, clone)
        else
            table.insert(points, clone)
        end
    else
        table.insert(points, clone)
    end

    custom_points.save_custom_points()
end

return custom_points
