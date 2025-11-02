local info_overlay = {}

local imgui = require('imgui')
local utils = require('src/utils')
local map = require('src/map')

-- Draw overlay information on the map
function info_overlay.draw(contentMinX, contentMinY, mapData)
    if not mapData then return end

    local zoneId = mapData.entry.ZoneId
    local floorId = mapData.entry.FloorId

    -- Get zone name from resource manager
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
        -- Get player grid position
        local playerGrid = nil
        local gridX, gridY = map.get_player_grid_position()
        if gridX and gridY then
            playerGrid = string.format('(%s-%d)', gridX, gridY)
        end

        -- Draw text with white shadow and black fill
        local fillColor = 0xFF000000
        local shadowColor = 0xFFFFFFFF
        local yOffset = contentMinY + 10

        -- Shadow
        imgui.PushStyleColor(ImGuiCol_Text, shadowColor)
        imgui.SetCursorPos({ contentMinX + 11, yOffset + 1 })
        imgui.Text(location)
        imgui.PopStyleColor()

        -- Main black text
        imgui.PushStyleColor(ImGuiCol_Text, fillColor)
        imgui.SetCursorPos({ contentMinX + 10, yOffset })
        imgui.Text(location)
        imgui.PopStyleColor()

        -- Draw player grid position below if available
        if playerGrid then
            yOffset = yOffset + 20 -- Move down for next line

            -- Shadow for grid position
            imgui.PushStyleColor(ImGuiCol_Text, shadowColor)
            imgui.SetCursorPos({ contentMinX + 11, yOffset + 1 })
            imgui.Text(playerGrid)
            imgui.PopStyleColor()

            -- Main black text for grid position
            imgui.PushStyleColor(ImGuiCol_Text, fillColor)
            imgui.SetCursorPos({ contentMinX + 10, yOffset })
            imgui.Text(playerGrid)
            imgui.PopStyleColor()
        end
    end
end

return info_overlay
