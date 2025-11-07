local info_overlay = {}

local imgui = require('imgui')
local utils = require('src.utils')
local map = require('src.map')

-- Draw overlay information on the map
function info_overlay.draw(windowPosX, windowPosY, contentMinX, contentMinY, mapData)
    local zoneId, floorId

    if not mapData then
        zoneId = map.get_player_zone()
        if not zoneId then return end

        local x, y, z = map.get_player_position()
        if not x then return end

        floorId, err = map.get_floor_id(x, y, z)
        if not floorId then return end
    else
        zoneId = mapData.entry.ZoneId
        floorId = mapData.entry.FloorId
    end

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

        local fontSize = boussole.config.infoPanelFontSize[1] or 13
        local fontScale = fontSize / 13.0

        imgui.SetWindowFontScale(fontScale)

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
        local bgColor = utils.rgb_to_abgr(boussole.config.colorInfoPanelBg)
        drawList:AddRectFilled(
            { bgX, bgY },
            { bgX + bgWidth, bgY + bgHeight },
            bgColor,
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

        imgui.SetWindowFontScale(1.0)
    end
end

return info_overlay
