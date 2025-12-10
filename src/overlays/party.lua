local party_overlay = {}

local imgui = require('imgui')
local map = require('src.map')
local tooltip = require('src.overlays.tooltip')
local texture = require('src.texture')
local utils = require('src.utils')
local d3d8 = require('d3d8')
local ffi = require('ffi')

party_overlay.cursor_texture = nil
party_overlay.cursor_width = 0
party_overlay.cursor_height = 0

function party_overlay.load_cursor_texture()
    if party_overlay.cursor_texture then
        return true
    end

    local cursor_path = string.format('%saddons\\boussole\\assets\\cursor.png', AshitaCore:GetInstallPath())
    local d3d8dev = d3d8.get_device()
    if not d3d8dev then
        return false
    end

    local gcTexture, texture_data, err = texture.load_texture_from_file(cursor_path, d3d8dev)
    if not gcTexture or not texture_data then
        return false
    end

    party_overlay.cursor_texture = gcTexture
    party_overlay.cursor_width = texture_data.width
    party_overlay.cursor_height = texture_data.height

    return true
end

function party_overlay.draw(config, mapData, windowPosX, windowPosY, contentMinX, contentMinY, mapOffsetX, mapOffsetY, mapZoom, textureWidth)
    if not mapData then return end

    if not config.showParty or not config.showParty[1] then return end

    if not party_overlay.cursor_texture then
        party_overlay.load_cursor_texture()
    end

    if not party_overlay.cursor_texture then
        return
    end

    local partyMgr = AshitaCore:GetMemoryManager():GetParty()
    if not partyMgr then return end

    local drawList = imgui.GetWindowDrawList()
    local mousePosX, mousePosY = imgui.GetMousePos()

    local cursorSize = boussole.config.iconSizeParty[1] or 20.0
    local halfSize = cursorSize / 2.0
    local texturePointer = tonumber(ffi.cast('uint32_t', party_overlay.cursor_texture))

    for i = 1, 5 do
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
                        local texX = (mapX - mapData.entry.OffsetX) * (textureWidth / 512.0)
                        local texY = (mapY - mapData.entry.OffsetY) * (textureWidth / 512.0)

                        local screenX = windowPosX + contentMinX + mapOffsetX + texX * mapZoom
                        local screenY = windowPosY + contentMinY + mapOffsetY + texY * mapZoom

                        local heading = (entity.Heading or 0) + (math.pi / 2)
                        local cos_angle = math.cos(heading)
                        local sin_angle = math.sin(heading)

                        -- Draw label above party member if showLabels is enabled
                        if boussole.config.showLabels[1] then
                            local memberName = entity.Name or ('Party ' .. i)
                            local textWidth, textHeight = imgui.CalcTextSize(memberName)
                            local labelX = screenX - textWidth / 2
                            local labelY = screenY - cursorSize - textHeight - 4
                            local padding = 4
                            
                            -- Draw background
                            local bgColor = utils.rgb_to_abgr({ 0.0, 0.0, 0.0, 0.7 })
                            drawList:AddRectFilled(
                                { labelX - padding, labelY - padding },
                                { labelX + textWidth + padding, labelY + textHeight + padding },
                                bgColor,
                                3.0
                            )
                            
                            -- Draw text with party color
                            local textColor = utils.rgb_to_abgr(boussole.config.colorParty)
                            drawList:AddText({ labelX, labelY }, textColor, memberName)
                        end

                        local corners = {
                            { x = -halfSize, y = -halfSize }, -- Top-left
                            { x = halfSize,  y = -halfSize }, -- Top-right
                            { x = halfSize,  y = halfSize },  -- Bottom-right
                            { x = -halfSize, y = halfSize }   -- Bottom-left
                        }

                        local rotated_corners = {}
                        for j, corner in ipairs(corners) do
                            local rotated_x = corner.x * cos_angle - corner.y * sin_angle
                            local rotated_y = corner.x * sin_angle + corner.y * cos_angle

                            rotated_corners[j] = {
                                screenX + rotated_x,
                                screenY + rotated_y
                            }
                        end

                        local dx = mousePosX - screenX
                        local dy = mousePosY - screenY
                        local distance = math.sqrt(dx * dx + dy * dy)

                        if distance <= halfSize then
                            local memberName = entity.Name
                            if memberName and memberName ~= '' then
                                local color = utils.rgb_to_abgr(boussole.config.colorParty)
                                tooltip.add_line(string.format('%s (Party)', memberName), color)
                            end
                        end

                        if texturePointer then
                            local color = utils.rgb_to_abgr(boussole.config.colorParty)
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
                                color
                            )
                        end
                    end
                end
            end
        end
    end
end

return party_overlay
