local tracked_entities = {}
local tracker = require('src.tracker')
local utils = require('src.utils')
local imgui = require('imgui')
local map = require('src.map')
local tooltip = require('src.overlays.tooltip')

function tracked_entities.draw(contextConfig, mapData, windowPosX, windowPosY, contentMinX, contentMinY, mapOffsetX, mapOffsetY, mapZoom, textureWidth, contextAlpha, contextLabels)
    contextConfig = contextConfig or boussole.config
    contextAlpha = contextAlpha or 1.0
    local showLabels
    if contextLabels ~= nil then
        showLabels = contextLabels
    else
        showLabels = contextConfig.showLabels[1]
    end
    showLabels = showLabels and (contextConfig.showTrackedEntityLabels == nil or contextConfig.showTrackedEntityLabels[1])
    if not contextConfig.showTrackedEntities[1] or not contextConfig.enableTracker[1] or not mapData or not mapData.entry then
        return
    end

    local trackedEntities = tracker.get_tracked_entities()
    local activeEntities = tracker.get_active_entities()

    local iconSize = contextConfig.iconSizeTrackedEntity and contextConfig.iconSizeTrackedEntity[1] or 10
    local drawList = imgui.GetWindowDrawList()

    local playerZone = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)
    local displayedZone = mapData.entry.ZoneId

    -- Only show entities when the displayed map matches the player's current zone
    if displayedZone ~= playerZone then return end

    for id, entity in pairs(trackedEntities) do
        if entity and entity.draw and entity.zoneId == playerZone then
            local activePos = activeEntities[id]
            local index = activePos and activePos.index or bit.band(id, 0x7FF)
            local enemyEntity = index and GetEntity(index) or nil
            local targetPosition = nil

            if activePos then
                targetPosition = { x = activePos.x, y = activePos.y, z = activePos.z }
            elseif enemyEntity ~= nil then
                -- Fallback to entity position if not in cache
                targetPosition = {
                    x = enemyEntity.Movement.LocalPosition.X,
                    y = enemyEntity.Movement.LocalPosition.Y,
                    z = enemyEntity.Movement.LocalPosition.Z,
                }
            end

            if targetPosition ~= nil then
                local shouldDraw = false

                if enemyEntity == nil then
                    shouldDraw = true
                else
                    -- Check render flags
                    local renderFlags = enemyEntity.Render.Flags0
                    if renderFlags then
                        local isRendered = bit.band(renderFlags, 0x200) == 0x200 and bit.band(renderFlags, 0x4000) == 0

                        if isRendered then
                            shouldDraw = true
                        elseif bit.band(renderFlags, 0x00040000) == 0 then
                            shouldDraw = true
                        end
                    end
                end

                if shouldDraw then
                    -- Convert world coordinates to map coordinates
                    local mapX, mapY = map.world_to_map_coords(mapData.entry, targetPosition.x, targetPosition.y, targetPosition.z)
                    if mapX ~= nil and mapY ~= nil then

                        -- Convert map coordinates to texture coordinates
                        local texX, texY
                        if mapData.entry._isCustomMap then
                            texX = (mapX - mapData.entry.OffsetX) * (textureWidth / mapData.entry._customData.referenceSize)
                            texY = (mapY - mapData.entry.OffsetY) * (textureWidth / mapData.entry._customData.referenceSize)
                        else
                            texX = (mapX - mapData.entry.OffsetX) * (textureWidth / 512.0)
                            texY = (mapY - mapData.entry.OffsetY) * (textureWidth / 512.0)
                        end

                        -- Convert texture coordinates to screen coordinates
                        local screenX = windowPosX + contentMinX + mapOffsetX + texX * mapZoom
                        local screenY = windowPosY + contentMinY + mapOffsetY + texY * mapZoom

                        -- Get entity color
                        local color = entity.color or { 0.0, 1.0, 0.5, 1.0 }
                        local colorU32 = utils.mul_alpha(utils.rgb_to_abgr(color), contextAlpha)

                        utils.draw_circle_marker(drawList, screenX, screenY, iconSize, colorU32, utils.mul_alpha(0xFF000000, contextAlpha), 2.0)

                        -- Add to tooltip if hovering
                        local mousePosX, mousePosY = imgui.GetMousePos()
                        local distance = math.sqrt((mousePosX - screenX) ^ 2 + (mousePosY - screenY) ^ 2)

                        if distance <= iconSize + 5 then
                            local displayName = entity.alias or entity.name
                            tooltip.add_line(displayName, colorU32)
                        end

                        -- Draw label above marker if showLabels is enabled
                        if showLabels then
                            local displayName = entity.alias or entity.name
                            utils.draw_label(drawList, displayName, screenX, screenY, iconSize, colorU32, contextAlpha)
                        end
                    end
                end
            end
        end
    end
end

return tracked_entities
