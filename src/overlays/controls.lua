local controls = {}
local imgui = require('imgui')
local utils = require('src.utils')
local settings = require('settings')
local texture = require('src.texture')
local d3d8 = require('d3d8')
local ffi = require('ffi')

controls.cursor_alt_texture = nil
controls.cursor_alt_width = 0
controls.cursor_alt_height = 0

controls.center_texture = nil
controls.center_width = 0
controls.center_height = 0

controls.tag_texture = nil
controls.tag_width = 0
controls.tag_height = 0

controls.reset_texture = nil
controls.reset_width = 0
controls.reset_height = 0

function controls.load_textures()
    if controls.cursor_alt_texture and controls.center_texture and controls.tag_texture and controls.reset_texture then
        return true
    end

    local d3d8dev = d3d8.get_device()
    if not d3d8dev then
        return false
    end

    -- Load cursor_alt.png for button 1
    if not controls.cursor_alt_texture then
        local cursor_alt_path = string.format('%saddons\\boussole\\assets\\cursor_alt.png', AshitaCore:GetInstallPath())
        local gcTexture, texture_data, err = texture.load_texture_from_file(cursor_alt_path, d3d8dev)
        if gcTexture and texture_data then
            controls.cursor_alt_texture = gcTexture
            controls.cursor_alt_width = texture_data.width
            controls.cursor_alt_height = texture_data.height
        end
    end

    -- Load center.png for button 2
    if not controls.center_texture then
        local center_path = string.format('%saddons\\boussole\\assets\\center.png', AshitaCore:GetInstallPath())
        local gcTexture, texture_data, err = texture.load_texture_from_file(center_path, d3d8dev)
        if gcTexture and texture_data then
            controls.center_texture = gcTexture
            controls.center_width = texture_data.width
            controls.center_height = texture_data.height
        end
    end

    -- Load tag.png for button 3
    if not controls.tag_texture then
        local tag_path = string.format('%saddons\\boussole\\assets\\tag.png', AshitaCore:GetInstallPath())
        local gcTexture, texture_data, err = texture.load_texture_from_file(tag_path, d3d8dev)
        if gcTexture and texture_data then
            controls.tag_texture = gcTexture
            controls.tag_width = texture_data.width
            controls.tag_height = texture_data.height
        end
    end

    -- Load reset.png for button 4
    if not controls.reset_texture then
        local reset_path = string.format('%saddons\\boussole\\assets\\reset.png', AshitaCore:GetInstallPath())
        local gcTexture, texture_data, err = texture.load_texture_from_file(reset_path, d3d8dev)
        if gcTexture and texture_data then
            controls.reset_texture = gcTexture
            controls.reset_width = texture_data.width
            controls.reset_height = texture_data.height
        end
    end

    return true
end

function controls.draw(windowPosX, windowPosY, contentMinX, contentMinY)
    -- Load textures if not already loaded
    if not controls.cursor_alt_texture or not controls.center_texture or not controls.tag_texture or not controls.reset_texture then
        controls.load_textures()
    end
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
    if controls.cursor_alt_texture then
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

        local texturePointer = tonumber(ffi.cast('uint32_t', controls.cursor_alt_texture))
        local iconColor = centerActive and
            utils.rgb_to_abgr(boussole.config.colorControlsBtnActive) or
            0xFFFFFFFF

        drawList:AddImageQuad(
            texturePointer,
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
    if controls.center_texture then
        local drawList = imgui.GetWindowDrawList()
        local btn2PosX = startX + buttonSize + spacing
        local btn2PosY = startY
        local iconSize = buttonSize * 0.7
        local offsetX = (buttonSize - iconSize) / 2
        local offsetY = (buttonSize - iconSize) / 2

        local texturePointer = tonumber(ffi.cast('uint32_t', controls.center_texture))

        drawList:AddImage(
            texturePointer,
            { btn2PosX + offsetX, btn2PosY + offsetY },
            { btn2PosX + offsetX + iconSize, btn2PosY + offsetY + iconSize },
            { 0, 0 },
            { 1, 1 },
            0xFFFFFFFF
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
    if controls.tag_texture then
        local drawList = imgui.GetWindowDrawList()
        local btn3PosX = startX + (buttonSize + spacing) * 2
        local btn3PosY = startY
        local iconSize = buttonSize * 0.7
        local offsetX = (buttonSize - iconSize) / 2
        local offsetY = (buttonSize - iconSize) / 2

        local texturePointer = tonumber(ffi.cast('uint32_t', controls.tag_texture))
        local iconColor = labelsActive and
            utils.rgb_to_abgr(boussole.config.colorControlsBtnActive) or
            0xFFFFFFFF

        drawList:AddImage(
            texturePointer,
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
    if controls.reset_texture then
        local drawList = imgui.GetWindowDrawList()
        local btn4PosX = startX + (buttonSize + spacing) * 3
        local btn4PosY = startY
        local iconSize = buttonSize * 0.7
        local offsetX = (buttonSize - iconSize) / 2
        local offsetY = (buttonSize - iconSize) / 2

        local texturePointer = tonumber(ffi.cast('uint32_t', controls.reset_texture))

        drawList:AddImage(
            texturePointer,
            { btn4PosX + offsetX, btn4PosY + offsetY },
            { btn4PosX + offsetX + iconSize, btn4PosY + offsetY + iconSize },
            { 0, 0 },
            { 1, 1 },
            0xFFFFFFFF
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
