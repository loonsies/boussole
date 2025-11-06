local player_overlay = {}

local imgui = require('imgui')
local map = require('src.map')
local tooltip = require('src.overlays.tooltip')

-- Draw player position dot on the map
function player_overlay.draw(config, mapData, windowPosX, windowPosY, contentMinX, contentMinY, mapOffsetX, mapOffsetY, mapZoom, textureWidth)
    if not mapData then return end

    -- Check if player display is enabled
    if not config.showPlayer[1] then return end

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
