local tracked_entities = {}
local tracker = require('src.tracker')
local utils = require('src.utils')
local imgui = require('imgui')
local map = require('src.map')
local tooltip = require('src.overlays.tooltip')

function tracked_entities.draw(mapData, windowPosX, windowPosY, contentMinX, contentMinY, mapOffsetX, mapOffsetY, mapZoom, textureWidth)
    if not boussole.config.showTrackedEntities[1] or not boussole.config.enableTracker[1] or not mapData or not mapData.entry then
        return
    end

    local trackedEntities = tracker.get_tracked_entities()
    local activeEntities = tracker.get_active_entities()
    local locationCache = tracker.get_location_cache()

    local iconSize = boussole.config.iconSizeTrackedEntity and boussole.config.iconSizeTrackedEntity[1] or 10
    local drawList = imgui.GetWindowDrawList()

    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    local zone = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)

    for index = 1, 0x400 do
        local id = entMgr:GetServerId(index)
        if id == 0 and locationCache[index] then
            id = bit.bor(0x01000000, bit.lshift(zone, 0x0C), index)
        end

        if id > 0 then
            local entity = trackedEntities[id]
            if entity and entity.draw and entity.zoneId == zone then
                local enemyEntity = GetEntity(index)
                local targetPosition = nil

                local activePos = activeEntities[id]
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
                        if mapX == nil or mapY == nil then
                            return
                        end

                        -- Convert map coordinates to texture coordinates
                        local texX = (mapX - mapData.entry.OffsetX) * (textureWidth / 512.0)
                        local texY = (mapY - mapData.entry.OffsetY) * (textureWidth / 512.0)

                        -- Convert texture coordinates to screen coordinates
                        local screenX = windowPosX + contentMinX + mapOffsetX + texX * mapZoom
                        local screenY = windowPosY + contentMinY + mapOffsetY + texY * mapZoom

                        -- Get entity color
                        local color = entity.color or { 0.0, 1.0, 0.5, 1.0 }
                        local colorU32 = utils.rgb_to_abgr(color)

                        -- Draw filled circle for entity
                        drawList:AddCircleFilled(
                            { screenX, screenY },
                            iconSize,
                            colorU32
                        )

                        -- Draw border
                        drawList:AddCircle(
                            { screenX, screenY },
                            iconSize,
                            0xFF000000,
                            0,
                            2.0
                        )

                        -- Add to tooltip if hovering
                        local mousePosX, mousePosY = imgui.GetMousePos()
                        local distance = math.sqrt((mousePosX - screenX) ^ 2 + (mousePosY - screenY) ^ 2)

                        if distance <= iconSize + 5 then
                            local displayName = entity.alias or entity.name
                            tooltip.add_line(displayName, colorU32)
                        end

                        -- Draw label above marker if showLabels is enabled
                        if boussole.config.showLabels[1] then
                            local displayName = entity.alias or entity.name
                            local textWidth, textHeight = imgui.CalcTextSize(displayName)
                            local labelX = screenX - textWidth / 2
                            local labelY = screenY - iconSize - textHeight - 4
                            local padding = 4

                            -- Draw background
                            local bgColor = utils.rgb_to_abgr({ 0.0, 0.0, 0.0, 0.7 })
                            drawList:AddRectFilled(
                                { labelX - padding, labelY - padding },
                                { labelX + textWidth + padding, labelY + textHeight + padding },
                                bgColor,
                                3.0
                            )

                            -- Draw text with entity color
                            drawList:AddText({ labelX, labelY }, colorU32, displayName)
                        end
                    end
                end
            end
        end
    end
end

return tracked_entities
