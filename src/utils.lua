local utils = {}

local imgui = require('imgui')
local regionZones = require('data.regionZones')
local regions = require('data.regions')

function utils.getRegionIDByZoneID(zoneID)
    for regionID, zoneIDs in pairs(regionZones.map) do
        for _, id in ipairs(zoneIDs) do
            if id == zoneID then
                return regionID
            end
        end
    end
    return nil
end

function utils.getRegionNameById(id)
    if not regions then
        return nil
    end

    for _, region in ipairs(regions) do
        if region.id == id then
            return region.en
        end
    end
    return nil
end

function utils.rgb_to_abgr(rgbaTable)
    if not rgbaTable or #rgbaTable < 3 then
        return 0xFFFFFFFF
    end

    local r = math.floor((rgbaTable[1] or 1.0) * 255)
    local g = math.floor((rgbaTable[2] or 1.0) * 255)
    local b = math.floor((rgbaTable[3] or 1.0) * 255)
    local a = math.floor((rgbaTable[4] or 1.0) * 255)

    -- ABGR format: (A << 24) | (B << 16) | (G << 8) | R
    return bit.bor(
        bit.lshift(a, 24),
        bit.lshift(b, 16),
        bit.lshift(g, 8),
        r
    )
end

function utils.round2(x)
    if x >= 0 then
        return math.floor(x * 100 + 0.5) / 100
    else
        return math.ceil(x * 100 - 0.5) / 100
    end
end

-- Multiply the alpha byte of a packed ABGR colour by a [0,1] factor
function utils.mul_alpha(color, alpha)
    local a = bit.rshift(bit.band(color, 0xFF000000), 24)
    local rgb = bit.band(color, 0x00FFFFFF)
    return bit.bor(bit.lshift(math.floor(a * alpha), 24), rgb)
end

function utils.draw_label(drawList, label, screenX, screenY, markerSize, textColor, alpha)
    alpha = alpha or 1.0

    local textWidth, textHeight = imgui.CalcTextSize(label)
    local labelX = screenX - textWidth / 2
    local labelY = screenY - markerSize - textHeight - 4
    local padding = 4
    local bgColor = utils.mul_alpha(utils.rgb_to_abgr({ 0.0, 0.0, 0.0, 0.7 }), alpha)

    drawList:AddRectFilled(
        { labelX - padding, labelY - padding },
        { labelX + textWidth + padding, labelY + textHeight + padding },
        bgColor,
        3.0
    )
    drawList:AddText({ labelX, labelY }, textColor, label)
end

function utils.draw_circle_marker(drawList, screenX, screenY, radius, color, outlineColor, outlineThickness)
    drawList:AddCircleFilled({ screenX, screenY }, radius, color)

    if outlineColor ~= nil and outlineThickness ~= 0 then
        drawList:AddCircle({ screenX, screenY }, radius, outlineColor, 0, outlineThickness or 2.0)
    end
end

function utils.draw_diamond_marker(drawList, screenX, screenY, radius, color, outlineColor, xScale)
    local size = radius
    xScale = xScale or 0.7
    local top = { screenX, screenY - size }
    local right = { screenX + size * xScale, screenY }
    local bottom = { screenX, screenY + size }
    local left = { screenX - size * xScale, screenY }

    drawList:AddTriangleFilled(top, left, right, color)
    drawList:AddTriangleFilled(bottom, left, right, color)

    if outlineColor ~= nil then
        drawList:AddLine(top, left, outlineColor, 1.0)
        drawList:AddLine(left, bottom, outlineColor, 1.0)
        drawList:AddLine(bottom, right, outlineColor, 1.0)
        drawList:AddLine(right, top, outlineColor, 1.0)
    end
end

function utils.draw_square_marker(drawList, screenX, screenY, radius, color, outlineColor, outlineThickness)
    local size = radius * 0.8

    drawList:AddRectFilled(
        { screenX - size, screenY - size },
        { screenX + size, screenY + size },
        color
    )

    if outlineColor ~= nil and outlineThickness ~= 0 then
        drawList:AddRect(
            { screenX - size, screenY - size },
            { screenX + size, screenY + size },
            outlineColor,
            0.0,
            0,
            outlineThickness or 1.5
        )
    end
end

function utils.draw_rotated_texture(drawList, texturePtr, centerX, centerY, size, angle, color)
    local halfSize = size / 2
    local cos_angle = math.cos(angle)
    local sin_angle = math.sin(angle)
    local corners = {
        { x = -halfSize, y = -halfSize },
        { x = halfSize, y = -halfSize },
        { x = halfSize, y = halfSize },
        { x = -halfSize, y = halfSize },
    }
    local rotated = {}

    for i, corner in ipairs(corners) do
        rotated[i] = {
            centerX + corner.x * cos_angle - corner.y * sin_angle,
            centerY + corner.x * sin_angle + corner.y * cos_angle,
        }
    end

    drawList:AddImageQuad(
        texturePtr,
        rotated[1],
        rotated[2],
        rotated[3],
        rotated[4],
        { 0, 0 },
        { 1, 0 },
        { 1, 1 },
        { 0, 1 },
        color
    )
end

return utils
