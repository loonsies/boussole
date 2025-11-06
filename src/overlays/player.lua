local player_overlay = {}

local imgui = require('imgui')
local map = require('src.map')
local tooltip = require('src.overlays.tooltip')
local texture = require('src.texture')
local d3d8 = require('d3d8')
local ffi = require('ffi')

player_overlay.cursor_texture = nil
player_overlay.cursor_width = 0
player_overlay.cursor_height = 0

function player_overlay.load_cursor_texture()
    if player_overlay.cursor_texture then
        return true
    end

    local cursor_path = string.format('%saddons\\boussole\\assets\\cursor.png', AshitaCore:GetInstallPath())
    local d3d8dev = d3d8.get_device()
    if not d3d8dev then
        return false
    end

    local gcTexture, texture_data, err = texture.load_texture_from_file(cursor_path, d3d8dev)
    if not gcTexture or not texture_data then
        print(chat.header(addon.name):append(chat.error(string.format('Failed to load cursor.png: %s', err or 'unknown error'))))
        return false
    end

    player_overlay.cursor_texture = gcTexture
    player_overlay.cursor_width = texture_data.width
    player_overlay.cursor_height = texture_data.height

    return true
end

-- Draw player position
function player_overlay.draw(mapData, windowPosX, windowPosY, contentMinX, contentMinY, mapOffsetX, mapOffsetY, mapZoom, textureWidth)
    if not mapData then return end

    -- Check if player display is enabled
    if not boussole.config.showPlayer[1] then return end

    if not player_overlay.cursor_texture then
        player_overlay.load_cursor_texture()
    end

    if not player_overlay.cursor_texture then
        player_overlay.draw_dot(mapData, windowPosX, windowPosY, contentMinX, contentMinY, mapOffsetX, mapOffsetY, mapZoom, textureWidth)
        return
    end

    local playerX, playerY, playerZ = map.get_player_position()
    if not playerX then return end

    local mapX, mapY = map.world_to_map_coords(mapData.entry, playerX, playerY, playerZ)
    if not mapX then return end

    local texX = (mapX - mapData.entry.OffsetX) * (textureWidth / 512.0)
    local texY = (mapY - mapData.entry.OffsetY) * (textureWidth / 512.0)

    local screenX = windowPosX + contentMinX + mapOffsetX + texX * mapZoom
    local screenY = windowPosY + contentMinY + mapOffsetY + texY * mapZoom

    local entity = GetPlayerEntity()
    if not entity then return end

    local heading = (entity.Heading or 0) + (math.pi / 2)

    local cursorSize = 20.0
    local halfSize = cursorSize / 2.0

    local cos_angle = math.cos(heading)
    local sin_angle = math.sin(heading)

    local corners = {
        { x = -halfSize, y = -halfSize }, -- Top-left
        { x = halfSize,  y = -halfSize }, -- Top-right
        { x = halfSize,  y = halfSize },  -- Bottom-right
        { x = -halfSize, y = halfSize }   -- Bottom-left
    }

    -- Rotate each corner and convert to screen coordinates
    local rotated_corners = {}
    for i, corner in ipairs(corners) do
        local rotated_x = corner.x * cos_angle - corner.y * sin_angle
        local rotated_y = corner.x * sin_angle + corner.y * cos_angle

        rotated_corners[i] = {
            screenX + rotated_x,
            screenY + rotated_y
        }
    end

    -- Check if mouse is hovering over player cursor
    local mousePosX, mousePosY = imgui.GetMousePos()
    local dx = mousePosX - screenX
    local dy = mousePosY - screenY
    local distance = math.sqrt(dx * dx + dy * dy)
    local hoverRadius = halfSize

    if distance <= hoverRadius then
        local playerName = entity.Name
        if playerName and playerName ~= '' then
            tooltip.add_line(string.format('%s (me)', playerName), 0xFF0000FF)
        end
    end

    local drawList = imgui.GetWindowDrawList()
    local texturePointer = tonumber(ffi.cast('uint32_t', player_overlay.cursor_texture))
    if texturePointer then
        drawList:AddImageQuad(
            texturePointer,
            rotated_corners[1],
            rotated_corners[2],
            rotated_corners[3],
            rotated_corners[4],
            { 0, 0 },
            { 1, 0 },
            { 1, 1 },
            { 0, 1 },
            0xFF0000FF
        )
    end
end

function player_overlay.draw_dot(mapData, windowPosX, windowPosY, contentMinX, contentMinY, mapOffsetX, mapOffsetY, mapZoom, textureWidth)
    -- Get player world position
    local playerX, playerY, playerZ = map.get_player_position()
    if not playerX then return end

    -- Convert world coordinates to map coordinates
    local mapX, mapY = map.world_to_map_coords(mapData.entry, playerX, playerY, playerZ)
    if not mapX then return end

    -- Convert map coordinates to texture pixel coordinates
    local texX = (mapX - mapData.entry.OffsetX) * (textureWidth / 512.0)
    local texY = (mapY - mapData.entry.OffsetY) * (textureWidth / 512.0)

    -- Convert to screen coordinates
    local screenX = windowPosX + contentMinX + mapOffsetX + texX * mapZoom
    local screenY = windowPosY + contentMinY + mapOffsetY + texY * mapZoom

    -- Check if mouse is hovering over player dot
    local mousePosX, mousePosY = imgui.GetMousePos()
    local dx = mousePosX - screenX
    local dy = mousePosY - screenY
    local distance = math.sqrt(dx * dx + dy * dy)
    local hoverRadius = 10.0

    if distance <= hoverRadius then
        -- Get player name
        local entity = GetPlayerEntity()
        if entity then
            local playerName = entity.Name
            if playerName and playerName ~= '' then
                tooltip.add_line(string.format('%s (me)', playerName), 0xFF0000FF)
            end
        end
    end

    -- Draw dot
    local drawList = imgui.GetWindowDrawList()
    local dotRadius = 5.0
    local dotColor = 0xFF0000FF
    local outlineColor = 0xFFFFFFFF

    drawList:AddCircleFilled({ screenX, screenY }, dotRadius, dotColor)
    drawList:AddCircle({ screenX, screenY }, dotRadius, outlineColor, 0, 1.5)
end

return player_overlay
