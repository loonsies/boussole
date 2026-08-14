local controls = {
    cursor_icon = {},
    center_icon = {},
    tag_icon = {},
    reset_icon = {},
}

local imgui = require('imgui')
local utils = require('src.utils')
local settings = require('settings')
local texture = require('src.texture')

function controls.load_textures()
    if not controls.cursor_icon.texture then
        texture.load_texture('cursor_alt', controls.cursor_icon)
    end
    if not controls.center_icon.texture then
        texture.load_texture('center', controls.center_icon)
    end
    if not controls.tag_icon.texture then
        texture.load_texture('tag', controls.tag_icon)
    end
    if not controls.reset_icon.texture then
        texture.load_texture('reset', controls.reset_icon)
    end
end

function controls.draw(windowPosX, windowPosY, contentMinX, contentMinY)
    -- Load textures if not already loaded
    controls.load_textures()

    local padding = 8
    local buttonSize = 28
    local spacing = 4

    -- Position at bottom left with padding
    local startX = windowPosX + contentMinX + padding
    local startY = windowPosY + imgui.GetWindowHeight() - padding - buttonSize

    imgui.SetCursorScreenPos({ startX, startY })

    -- Push rounded button style
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 3.0)
    imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 0.0)

    -- Track if any button is hovered to prevent map tooltips
    local anyButtonHovered = false

    -- Button 1: Center on player
    local baseColor = boussole.config.colorControlsBtn
    local buttonColor = utils.rgb_to_abgr(baseColor)
    local hoverColor = utils.rgb_to_abgr({ baseColor[1], baseColor[2], baseColor[3], math.min(1.0, (baseColor[4] or 1.0) + 0.2) })
    local activeColor = utils.rgb_to_abgr({ baseColor[1], baseColor[2], baseColor[3], math.min(1.0, (baseColor[4] or 1.0) + 0.3) })

    imgui.PushStyleColor(ImGuiCol_Button, buttonColor)
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, hoverColor)
    imgui.PushStyleColor(ImGuiCol_ButtonActive, activeColor)

    local centerActive = boussole.config.centerOnPlayer[1]

    -- Use invisible button and draw cursor texture manually
    if imgui.Button('##Ctrl1', { buttonSize, buttonSize }) then
        boussole.config.centerOnPlayer[1] = not boussole.config.centerOnPlayer[1]
        settings.save()
    end
    local btn1Hovered = imgui.IsItemHovered()
    imgui.PopStyleColor(3)

    -- Draw cursor texture on top of button (rotated 45 degrees)
    if controls.cursor_icon.texture then
        local drawList = imgui.GetWindowDrawList()
        local btnPosX = startX + buttonSize / 2
        local btnPosY = startY + buttonSize / 2
        local cursorSize = buttonSize * 0.6
        local halfSize = cursorSize / 2

        -- 45 degrees = pi/4 radians (northwest)
        local angle = math.pi / 4
        local cos_angle = math.cos(angle)
        local sin_angle = math.sin(angle)

        local corners = {
            { x = -halfSize, y = -halfSize },
            { x = halfSize,  y = -halfSize },
            { x = halfSize,  y = halfSize },
            { x = -halfSize, y = halfSize }
        }

        local rotated_corners = {}
        for i, corner in ipairs(corners) do
            rotated_corners[i] = {
                x = btnPosX + corner.x * cos_angle - corner.y * sin_angle,
                y = btnPosY + corner.x * sin_angle + corner.y * cos_angle
            }
        end

        local iconColor = centerActive and
            utils.rgb_to_abgr(boussole.config.colorControlsBtnActive) or
            utils.rgb_to_abgr({ 1.0, 1.0, 1.0, 1.0 })

        drawList:AddImageQuad(
            controls.cursor_icon.pointer,
            { rotated_corners[1].x, rotated_corners[1].y },
            { rotated_corners[2].x, rotated_corners[2].y },
            { rotated_corners[3].x, rotated_corners[3].y },
            { rotated_corners[4].x, rotated_corners[4].y },
            { 0, 0 },
            { 1, 0 },
            { 1, 1 },
            { 0, 1 },
            iconColor
        )
    end

    if btn1Hovered then
        imgui.SetTooltip('Keep map centered on player position')
        anyButtonHovered = true
    end

    -- Button 2: Recenter once
    imgui.SameLine(0, spacing)

    imgui.PushStyleColor(ImGuiCol_Button, buttonColor)
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, hoverColor)
    imgui.PushStyleColor(ImGuiCol_ButtonActive, activeColor)
    if imgui.Button('##Ctrl2', { buttonSize, buttonSize }) then
        boussole.recenterMap = true
    end
    local btn2Hovered = imgui.IsItemHovered()
    imgui.PopStyleColor(3)

    -- Draw center texture on top of button
    if controls.center_icon.texture then
        local drawList = imgui.GetWindowDrawList()
        local btn2PosX = startX + buttonSize + spacing
        local btn2PosY = startY
        local iconSize = buttonSize * 0.7
        local offsetX = (buttonSize - iconSize) / 2
        local offsetY = (buttonSize - iconSize) / 2

        drawList:AddImage(
            controls.center_icon.pointer,
            { btn2PosX + offsetX, btn2PosY + offsetY },
            { btn2PosX + offsetX + iconSize, btn2PosY + offsetY + iconSize },
            { 0, 0 },
            { 1, 1 },
            utils.rgb_to_abgr({ 1.0, 1.0, 1.0, 1.0 })
        )
    end

    if btn2Hovered then
        imgui.SetTooltip('Center map on player once')
        anyButtonHovered = true
    end

    -- Button 3: Show labels
    imgui.SameLine(0, spacing)

    imgui.PushStyleColor(ImGuiCol_Button, buttonColor)
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, hoverColor)
    imgui.PushStyleColor(ImGuiCol_ButtonActive, activeColor)

    local labelsActive = boussole.config.showLabels[1]

    if imgui.Button('##Ctrl3', { buttonSize, buttonSize }) then
        boussole.config.showLabels[1] = not boussole.config.showLabels[1]
        settings.save()
    end
    local btn3Hovered = imgui.IsItemHovered()
    imgui.PopStyleColor(3)

    -- Draw tag texture on top of button
    if controls.tag_icon.texture then
        local drawList = imgui.GetWindowDrawList()
        local btn3PosX = startX + (buttonSize + spacing) * 2
        local btn3PosY = startY
        local iconSize = buttonSize * 0.7
        local offsetX = (buttonSize - iconSize) / 2
        local offsetY = (buttonSize - iconSize) / 2

        local iconColor = labelsActive and
            utils.rgb_to_abgr(boussole.config.colorControlsBtnActive) or
            utils.rgb_to_abgr({ 1.0, 1.0, 1.0, 1.0 })

        drawList:AddImage(
            controls.tag_icon.pointer,
            { btn3PosX + offsetX, btn3PosY + offsetY },
            { btn3PosX + offsetX + iconSize, btn3PosY + offsetY + iconSize },
            { 0, 0 },
            { 1, 1 },
            iconColor
        )
    end

    if btn3Hovered then
        imgui.SetTooltip('Display names above entities')
        anyButtonHovered = true
    end

    -- Button 4: Reset Zoom
    imgui.SameLine(0, spacing)

    imgui.PushStyleColor(ImGuiCol_Button, buttonColor)
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, hoverColor)
    imgui.PushStyleColor(ImGuiCol_ButtonActive, activeColor)
    if imgui.Button('##Ctrl4', { buttonSize, buttonSize }) then
        boussole.resetZoom = true
    end
    local btn4Hovered = imgui.IsItemHovered()
    imgui.PopStyleColor(3)

    -- Draw reset texture on top of button
    if controls.reset_icon.texture then
        local drawList = imgui.GetWindowDrawList()
        local btn4PosX = startX + (buttonSize + spacing) * 3
        local btn4PosY = startY
        local iconSize = buttonSize * 0.7
        local offsetX = (buttonSize - iconSize) / 2
        local offsetY = (buttonSize - iconSize) / 2

        drawList:AddImage(
            controls.reset_icon.pointer,
            { btn4PosX + offsetX, btn4PosY + offsetY },
            { btn4PosX + offsetX + iconSize, btn4PosY + offsetY + iconSize },
            { 0, 0 },
            { 1, 1 },
            utils.rgb_to_abgr({ 1.0, 1.0, 1.0, 1.0 })
        )
    end

    if btn4Hovered then
        imgui.SetTooltip('Reset map zoom')
        anyButtonHovered = true
    end

    imgui.PopStyleVar(2)

    return anyButtonHovered
end

return controls
