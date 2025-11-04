local info_overlay = {}

local imgui = require('imgui')
local utils = require('src/utils')
local map = require('src/map')

-- Draw overlay information on the map
function info_overlay.draw(windowPosX, windowPosY, contentMinX, contentMinY, mapData)
    if not mapData then return end

    local zoneId = mapData.entry.ZoneId
    local floorId = mapData.entry.FloorId

    local location = nil
    local resMgr = AshitaCore:GetResourceManager()

    if resMgr then
        local zoneName = resMgr:GetString('zones.names', zoneId)
        local regionID = utils.getRegionIDByZoneID(zoneId)
        local regionName = utils.getRegionNameById(regionID)

        if regionName and zoneName then
            location = string.format('%s - %s', regionName, zoneName)
            if floorId > 0 then
                location = location .. string.format(' (Floor %d)', floorId)
            end
        end
    end

    if location then
        local playerGrid = nil
        local gridX, gridY = map.get_player_grid_position()
        if gridX and gridY then
            playerGrid = string.format('(%s-%d)', gridX, gridY)
        end

        local locationSizeX, locationSizeY = imgui.CalcTextSize(location)
        local gridSizeX, gridSizeY = 0, 0
        if playerGrid then
            gridSizeX, gridSizeY = imgui.CalcTextSize(playerGrid)
        end

        local maxWidth = math.max(locationSizeX, gridSizeX)
        local totalHeight = locationSizeY + (playerGrid and (gridSizeY + 5) or 0)
        local padding = 8

        -- Draw background
        local bgX = windowPosX + contentMinX + 10 - padding
        local bgY = windowPosY + contentMinY + 10 - padding
        local bgWidth = maxWidth + (padding * 2)
        local bgHeight = totalHeight + (padding * 2)

        local drawList = imgui.GetWindowDrawList()
        drawList:AddRectFilled(
            { bgX, bgY },
            { bgX + bgWidth, bgY + bgHeight },
            0x88444444,
            3.0
        )

        -- Draw text
        local textColor = 0xFFFFFFFF
        local yOffset = contentMinY + 10

        imgui.PushStyleColor(ImGuiCol_Text, textColor)
        imgui.SetCursorPos({ contentMinX + 10, yOffset })
        imgui.Text(location)
        imgui.PopStyleColor()

        -- Draw player grid position below if available
        if playerGrid then
            yOffset = yOffset + locationSizeY + 5

            imgui.PushStyleColor(ImGuiCol_Text, textColor)
            imgui.SetCursorPos({ contentMinX + 10, yOffset })
            imgui.Text(playerGrid)
            imgui.PopStyleColor()
        end
    end
end

return info_overlay
