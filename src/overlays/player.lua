local player_overlay = {}

local imgui = require('imgui')
local map = require('src.map')
local tooltip = require('src.overlays.tooltip')
local utils = require('src.utils')
local texture = require('src.texture')
local ffi = require('ffi')

player_overlay.cursor = {}

-- Draw player position
function player_overlay.draw(contextConfig, mapData, windowPosX, windowPosY, contentMinX, contentMinY, mapOffsetX, mapOffsetY, mapZoom, textureWidth, contextAlpha, contextLabels)
    contextConfig = contextConfig or boussole.config
    contextAlpha = contextAlpha or 1.0
    local showLabels
    if contextLabels ~= nil then
        showLabels = contextLabels
    else
        showLabels = contextConfig.showLabels[1]
    end
    showLabels = showLabels and (contextConfig.showPlayerLabels == nil or contextConfig.showPlayerLabels[1])
    if not mapData then return end

    -- Check if player display is enabled
    if not contextConfig.showPlayer[1] then return end

    -- Only show player on the map matching the player's current zone
    local playerZone = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)
    if (mapData.entry and mapData.entry.ZoneId ~= playerZone and not (mapData.entry._redirected and mapData.entry._originalZone == playerZone)) then return end

    if not player_overlay.cursor.texture then
        texture.load_texture('cursor', player_overlay.cursor)
    end

    if not player_overlay.cursor.texture then
        player_overlay.draw_dot(mapData, windowPosX, windowPosY, contentMinX, contentMinY, mapOffsetX, mapOffsetY, mapZoom, textureWidth, contextAlpha, contextLabels)
        return
    end

    local playerX, playerY, playerZ = map.get_player_position()
    if not playerX then return end

    local mapX, mapY = map.world_to_map_coords(mapData.entry, playerX, playerY, playerZ)
    if not mapX then return end

    local texX, texY
    if mapData.entry._isCustomMap then
        texX = (mapX - mapData.entry.OffsetX) * (textureWidth / mapData.entry._customData.referenceSize)
        texY = (mapY - mapData.entry.OffsetY) * (textureWidth / mapData.entry._customData.referenceSize)
    else
        -- Standard maps: convert from map space to texture space
        texX = (mapX - mapData.entry.OffsetX) * (textureWidth / 512.0)
        texY = (mapY - mapData.entry.OffsetY) * (textureWidth / 512.0)
    end

    local screenX = windowPosX + contentMinX + mapOffsetX + texX * mapZoom
    local screenY = windowPosY + contentMinY + mapOffsetY + texY * mapZoom

    local entity = GetPlayerEntity()
    if not entity then return end

    local heading = (entity.Heading or 0) + (math.pi / 2)

    local cursorSize = contextConfig.iconSizePlayer[1] or 20.0
    local halfSize = cursorSize / 2.0

    -- Draw label above player if showLabels is enabled
    if showLabels then
        local playerName = entity.Name or 'Player'
        local drawList = imgui.GetWindowDrawList()
        local textColor = utils.mul_alpha(utils.rgb_to_abgr(contextConfig.colorPlayer), contextAlpha)
        utils.draw_label(drawList, playerName, screenX, screenY, cursorSize, textColor, contextAlpha)
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
            local color = utils.rgb_to_abgr(contextConfig.colorPlayer)
            tooltip.add_line(string.format('%s (me)', playerName), color)
        end
    end

    local drawList = imgui.GetWindowDrawList()
    local color = utils.mul_alpha(utils.rgb_to_abgr(contextConfig.colorPlayer), contextAlpha)
    if player_overlay.cursor.pointer then
        utils.draw_rotated_texture(drawList, player_overlay.cursor.pointer, screenX, screenY, cursorSize, heading, color)
    end
end

function player_overlay.draw_dot(mapData, windowPosX, windowPosY, contentMinX, contentMinY, mapOffsetX, mapOffsetY, mapZoom, textureWidth, contextAlpha, contextLabels)
    contextAlpha = contextAlpha or 1.0
    -- Get player world position
    local playerX, playerY, playerZ = map.get_player_position()
    if not playerX then return end

    -- Convert world coordinates to map coordinates
    local mapX, mapY = map.world_to_map_coords(mapData.entry, playerX, playerY, playerZ)
    if not mapX then return end

    -- Convert map coordinates to texture pixel coordinates
    local texX, texY
    if mapData.entry._isCustomMap then
        texX = (mapX - mapData.entry.OffsetX) * (textureWidth / mapData.entry._customData.referenceSize)
        texY = (mapY - mapData.entry.OffsetY) * (textureWidth / mapData.entry._customData.referenceSize)
    else
        -- Standard maps: convert from map space to texture space
        texX = (mapX - mapData.entry.OffsetX) * (textureWidth / 512.0)
        texY = (mapY - mapData.entry.OffsetY) * (textureWidth / 512.0)
    end

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
    local dotColor = utils.mul_alpha(0xFF0000FF, contextAlpha)
    local outlineColor = utils.mul_alpha(0xFFFFFFFF, contextAlpha)

    utils.draw_circle_marker(drawList, screenX, screenY, dotRadius, dotColor, outlineColor, 1.5)
end

return player_overlay
