local alliance_overlay = {}

local imgui = require('imgui')
local map = require('src.map')
local tooltip = require('src.overlays.tooltip')
local utils = require('src.utils')
local texture = require('src.texture')
local ffi = require('ffi')

alliance_overlay.cursor = {}

function alliance_overlay.draw(contextConfig, mapData, windowPosX, windowPosY, contentMinX, contentMinY, mapOffsetX, mapOffsetY, mapZoom, textureWidth, contextAlpha, contextLabels)
    contextConfig = contextConfig or boussole.config
    contextAlpha = contextAlpha or 1.0
    local showLabels
    if contextLabels ~= nil then
        showLabels = contextLabels
    else
        showLabels = contextConfig.showLabels[1]
    end
    showLabels = showLabels and (contextConfig.showAllianceLabels == nil or contextConfig.showAllianceLabels[1])
    if not mapData then return end

    if not contextConfig.showAlliance or not contextConfig.showAlliance[1] then return end

    -- Only show alliance on the map matching the player's current zone
    local playerZone = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)
    if (mapData.entry and mapData.entry.ZoneId ~= playerZone and not (mapData.entry._redirected and mapData.entry._originalZone == playerZone)) then return end

    if not alliance_overlay.cursor.texture then
        texture.load_texture('cursor', alliance_overlay.cursor)
    end

    if not alliance_overlay.cursor.texture then
        return
    end

    local partyMgr = AshitaCore:GetMemoryManager():GetParty()
    if not partyMgr then return end

    local drawList = imgui.GetWindowDrawList()
    local mousePosX, mousePosY = imgui.GetMousePos()

    local cursorSize = contextConfig.iconSizeAlliance[1] or 20.0
    local halfSize = cursorSize / 2.0

    for i = 6, 17 do
        if partyMgr:GetMemberIsActive(i) == 1 then
            local entityIndex = partyMgr:GetMemberTargetIndex(i)

            if entityIndex and entityIndex > 0 then
                local entity = GetEntity(entityIndex)

                if entity and entity.Render.Flags0 ~= 0 then
                    local memberX = entity.Movement.LastPosition.X
                    local memberY = entity.Movement.LastPosition.Y
                    local memberZ = entity.Movement.LastPosition.Z

                    local mapX, mapY = map.world_to_map_coords(mapData.entry, memberX, memberY, memberZ)

                    if mapX then
                        local texX, texY
                        if mapData.entry._isCustomMap then
                            texX = (mapX - mapData.entry.OffsetX) * (textureWidth / mapData.entry._customData.referenceSize)
                            texY = (mapY - mapData.entry.OffsetY) * (textureWidth / mapData.entry._customData.referenceSize)
                        else
                            texX = (mapX - mapData.entry.OffsetX) * (textureWidth / 512.0)
                            texY = (mapY - mapData.entry.OffsetY) * (textureWidth / 512.0)
                        end

                        local screenX = windowPosX + contentMinX + mapOffsetX + texX * mapZoom
                        local screenY = windowPosY + contentMinY + mapOffsetY + texY * mapZoom

                        local heading = (entity.Heading or 0) + (math.pi / 2)

                        -- Draw label above alliance member if showLabels is enabled
                        if showLabels then
                            local memberName = entity.Name or ('Alliance ' .. i)
                            local textColor = utils.mul_alpha(utils.rgb_to_abgr(contextConfig.colorAlliance), contextAlpha)
                            utils.draw_label(drawList, memberName, screenX, screenY, cursorSize, textColor, contextAlpha)
                        end

                        local dx = mousePosX - screenX
                        local dy = mousePosY - screenY
                        local distance = math.sqrt(dx * dx + dy * dy)

                        if distance <= halfSize then
                            local memberName = entity.Name
                            if memberName and memberName ~= '' then
                                local color = utils.rgb_to_abgr(contextConfig.colorAlliance)
                                tooltip.add_line(string.format('%s (Alliance)', memberName), color)
                            end
                        end

                        if alliance_overlay.cursor.pointer then
                            local color = utils.mul_alpha(utils.rgb_to_abgr(contextConfig.colorAlliance), contextAlpha)
                            utils.draw_rotated_texture(drawList, alliance_overlay.cursor.pointer, screenX, screenY, cursorSize, heading, color)
                        end
                    end
                end
            end
        end
    end
end

return alliance_overlay
