local warp_overlay = {}

local imgui = require('imgui')
local map = require('src.map')
local warp_points = require('src.warp_points')
local tooltip = require('src.overlays.tooltip')
local utils = require('src.utils')

-- Track hovered warp point for tooltip
local hovered_point = nil
local hovered_type = nil
local hovered_index = 0

-- Draw warp point markers on the map
function warp_overlay.draw(contextConfig, mapData, windowPosX, windowPosY, contentMinX, contentMinY, mapOffsetX, mapOffsetY, mapZoom, textureWidth, contextAlpha, contextLabels)
    contextConfig = contextConfig or boussole.config
    contextAlpha = contextAlpha or 1.0
    local showLabels
    if contextLabels ~= nil then
        showLabels = contextLabels
    else
        showLabels = contextConfig.showLabels[1]
    end
    if not mapData then return end

    local resMgr = AshitaCore:GetResourceManager()
    local zoneId = mapData.entry.ZoneId
    local zoneName = ''
    if resMgr then
        zoneName = resMgr:GetString('zones.names', zoneId)
    end

    if not zoneId then return end

    local drawList = imgui.GetWindowDrawList()

    -- Reset hovered state
    hovered_point = nil
    hovered_type = nil
    hovered_index = 0

    -- Get mouse position for hover detection
    local mousePosX, mousePosY = imgui.GetMousePos()
    local hoverRadius = 10.0

    -- Draw homepoints for current zone (if enabled)
    if contextConfig.showHomepoints[1] then
        local homepoints = warp_points.homepoints[zoneId]
        if homepoints then
            for idx, point in ipairs(homepoints) do
                local mapX, mapY = map.world_to_map_coords(mapData.entry, point.posx, point.posy, point.posz)

                if mapX then
                    -- Convert map coordinates to texture pixel coordinates
                    local texX, texY
                    if mapData.entry._isCustomMap then
                        texX = (mapX - mapData.entry.OffsetX) * (textureWidth / mapData.entry._customData.referenceSize)
                        texY = (mapY - mapData.entry.OffsetY) * (textureWidth / mapData.entry._customData.referenceSize)
                    else
                        texX = (mapX - mapData.entry.OffsetX) * (textureWidth / 512.0)
                        texY = (mapY - mapData.entry.OffsetY) * (textureWidth / 512.0)
                    end

                    -- Convert to screen coordinates
                    local screenX = windowPosX + contentMinX + mapOffsetX + texX * mapZoom
                    local screenY = windowPosY + contentMinY + mapOffsetY + texY * mapZoom

                    -- Check if mouse is hovering over this point
                    local dx = mousePosX - screenX
                    local dy = mousePosY - screenY
                    local distance = math.sqrt(dx * dx + dy * dy)

                    if distance <= hoverRadius then
                        hovered_point = point
                        hovered_type = 'Homepoint'
                        hovered_index = idx
                    end

                    local markerRadius = contextConfig.iconSizeHomepoint[1] or 8.0
                    local markerColor = utils.mul_alpha(utils.rgb_to_abgr(contextConfig.colorHomepoint), contextAlpha)
                    local outlineColor = utils.mul_alpha(0xFFFFFFFF, contextAlpha)

                    utils.draw_diamond_marker(drawList, screenX, screenY, markerRadius, markerColor, outlineColor)

                    if showLabels and (contextConfig.showHomepointLabels == nil or contextConfig.showHomepointLabels[1]) then
                        utils.draw_label(drawList, string.format('Homepoint #%d', idx), screenX, screenY, markerRadius, markerColor, contextAlpha)
                    end
                end
            end
        end
    end

    if contextConfig.showSurvivalGuides[1] then
        local survival_guides = warp_points.survival_guides[zoneId]
        if survival_guides then
            for idx, point in ipairs(survival_guides) do
                local mapX, mapY = map.world_to_map_coords(mapData.entry, point.posx, point.posy, point.posz)

                if mapX then
                    -- Convert map coordinates to texture pixel coordinates
                    local texX, texY
                    if mapData.entry._isCustomMap then
                        texX = (mapX - mapData.entry.OffsetX) * (textureWidth / mapData.entry._customData.referenceSize)
                        texY = (mapY - mapData.entry.OffsetY) * (textureWidth / mapData.entry._customData.referenceSize)
                    else
                        texX = (mapX - mapData.entry.OffsetX) * (textureWidth / 512.0)
                        texY = (mapY - mapData.entry.OffsetY) * (textureWidth / 512.0)
                    end

                    -- Convert to screen coordinates
                    local screenX = windowPosX + contentMinX + mapOffsetX + texX * mapZoom
                    local screenY = windowPosY + contentMinY + mapOffsetY + texY * mapZoom

                    -- Check if mouse is hovering over this point
                    local dx = mousePosX - screenX
                    local dy = mousePosY - screenY
                    local distance = math.sqrt(dx * dx + dy * dy)

                    if distance <= hoverRadius then
                        hovered_point = point
                        hovered_type = 'Survival Guide'
                        hovered_index = 0 -- No index for survival guides
                    end

                    local markerRadius = contextConfig.iconSizeSurvivalGuide[1] or 8.0
                    local markerColor = utils.mul_alpha(utils.rgb_to_abgr(contextConfig.colorSurvivalGuide), contextAlpha)
                    local outlineColor = utils.mul_alpha(0xFFFFFFFF, contextAlpha)

                    utils.draw_square_marker(drawList, screenX, screenY, markerRadius, markerColor, outlineColor, 1.5)

                    if showLabels and (contextConfig.showSurvivalGuideLabels == nil or contextConfig.showSurvivalGuideLabels[1]) then
                        utils.draw_label(drawList, 'Survival Guide', screenX, screenY, markerRadius, markerColor, contextAlpha)
                    end
                end
            end
        end
    end

    -- Draw tooltip if hovering over a point
    if hovered_point and hovered_type then
        -- Determine color based on type
        local typeColor
        if hovered_type == 'Survival Guide' then
            typeColor = utils.rgb_to_abgr(contextConfig.colorSurvivalGuide)
        else
            typeColor = utils.rgb_to_abgr(contextConfig.colorHomepoint)
        end

        -- Add title with index if applicable
        if hovered_index > 0 then
            tooltip.add_line(string.format('%s - %s #%d', zoneName, hovered_type, hovered_index), typeColor)
        else
            tooltip.add_line(hovered_type, typeColor)
        end
    end
end

return warp_overlay
