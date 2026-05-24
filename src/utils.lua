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

function utils.is_entity_rendered(entity)
    if entity == nil or entity.Render == nil or entity.Render.Flags0 == nil then
        return false
    end

    local renderFlags = entity.Render.Flags0
    return bit.band(renderFlags, 0x200) == 0x200 and bit.band(renderFlags, 0x4000) == 0
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

function utils.clamp_text_to_width(text, maxWidth)
    if maxWidth <= 0 then return '' end
    if select(1, imgui.CalcTextSize(text)) <= maxWidth then return text end

    local ellipsis = '...'
    local ellipsisWidth = select(1, imgui.CalcTextSize(ellipsis))
    if ellipsisWidth >= maxWidth then return ellipsis end

    local lo = 0
    local hi = #text
    while lo < hi do
        local mid = math.ceil((lo + hi) / 2)
        if select(1, imgui.CalcTextSize(text:sub(1, mid) .. ellipsis)) <= maxWidth then
            lo = mid
        else
            hi = mid - 1
        end
    end

    return text:sub(1, lo) .. ellipsis
end

local function utf8_first_codepoint(text)
    local b1 = text:byte(1)
    if not b1 then return nil end

    if b1 < 0x80 then
        return b1
    elseif b1 < 0xE0 then
        local b2 = text:byte(2)
        if not b2 then return nil end
        return bit.bor(bit.lshift(bit.band(b1, 0x1F), 6), bit.band(b2, 0x3F))
    elseif b1 < 0xF0 then
        local b2, b3 = text:byte(2), text:byte(3)
        if not b2 or not b3 then return nil end
        return bit.bor(
            bit.lshift(bit.band(b1, 0x0F), 12),
            bit.lshift(bit.band(b2, 0x3F), 6),
            bit.band(b3, 0x3F)
        )
    end

    local b2, b3, b4 = text:byte(2), text:byte(3), text:byte(4)
    if not b2 or not b3 or not b4 then return nil end
    return bit.bor(
        bit.lshift(bit.band(b1, 0x07), 18),
        bit.lshift(bit.band(b2, 0x3F), 12),
        bit.lshift(bit.band(b3, 0x3F), 6),
        bit.band(b4, 0x3F)
    )
end

local glyphBoundsCache = {}

local function get_glyph_bounds(icon)
    local font = imgui.GetFontBaked()
    local codepoint = utf8_first_codepoint(icon)
    if not font or not codepoint then
        return nil
    end

    local ok, glyph = pcall(function ()
        return font:FindGlyph(codepoint)
    end)
    if not ok or not glyph or not glyph.X0 then
        if not ok or not glyph or not glyph.x0 then
            return nil
        end
    end

    local fontSize = imgui.GetFontSize()
    local bakedSize = font.Size or fontSize
    local cacheKey = tostring(codepoint) .. ':' .. tostring(bakedSize) .. ':' .. tostring(fontSize)
    local cached = glyphBoundsCache[cacheKey]
    if cached then
        return cached[1], cached[2], cached[3], cached[4]
    end

    local scale = fontSize / bakedSize
    local x0 = glyph.X0 or glyph.x0
    local y0 = glyph.Y0 or glyph.y0
    local x1 = glyph.X1 or glyph.x1
    local y1 = glyph.Y1 or glyph.y1
    local bounds = { x0 * scale, y0 * scale, x1 * scale, y1 * scale }
    glyphBoundsCache[cacheKey] = bounds
    return bounds[1], bounds[2], bounds[3], bounds[4]
end

function utils.draw_icon_button(id, icon, size)
    local clicked = imgui.Button('##' .. id, size)
    local minX, minY = imgui.GetItemRectMin()
    local maxX, maxY = imgui.GetItemRectMax()

    local glyphX0, glyphY0, glyphX1, glyphY1 = get_glyph_bounds(icon)
    local textX, textY
    if glyphX0 then
        local centerX = minX + (maxX - minX) * 0.5
        local centerY = minY + (maxY - minY) * 0.5
        textX = centerX - (glyphX0 + glyphX1) * 0.5
        textY = centerY - (glyphY0 + glyphY1) * 0.5
    else
        local textW, textH = imgui.CalcTextSize(icon)
        textX = minX + ((maxX - minX) - textW) * 0.5
        textY = minY + ((maxY - minY) - textH) * 0.5
    end

    imgui.GetWindowDrawList():AddText({ textX, textY }, 0xFFFFFFFF, icon)

    return clicked
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
