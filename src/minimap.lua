local minimap = {}

local imgui = require('imgui')
local settings = require('settings')
local map = require('src.map')
local ffi = require('ffi')
local utils = require('src.utils')
local player_overlay = require('src.overlays.player')
local party_overlay = require('src.overlays.party')
local alliance_overlay = require('src.overlays.alliance')
local warp_overlay = require('src.overlays.warp')
local tracked_entities = require('src.overlays.tracked_entities')
local controls = require('src.overlays.controls')
local tooltip = require('src.overlays.tooltip')

-- Minimap state
minimap.map_zoom = -1.0
minimap.map_offset = { x = 0, y = 0 }
minimap.window_bounds = nil
minimap.last_zone_key = nil

-- Right-click pan state
minimap.is_dragging = false
minimap.drag_start = { x = 0, y = 0 }
minimap.is_manually_panned = false
minimap.last_pan_time = 0.0
minimap.last_player_pos = nil
minimap.is_recentering = false
minimap.last_frame_time = 0.0

-- Returns the zone+floor key for detecting zone changes
local function get_zone_key()
    if not map.current_map_data or not map.current_map_data.entry then
        return nil
    end
    return string.format('%d_%d', map.current_map_data.entry.ZoneId, map.current_map_data.entry.FloorId)
end

-- Load saved zoom for a zone key - returns nil if not saved
local function load_zone_zoom(zoneKey)
    if not zoneKey then return nil end
    if boussole.config.minimapViews and boussole.config.minimapViews[zoneKey] then
        return boussole.config.minimapViews[zoneKey].zoom
    end
    return nil
end

-- Save current zoom for a zone key
local function save_zone_zoom(zoneKey)
    if not zoneKey then return end
    if not boussole.config.minimapViews then
        boussole.config.minimapViews = {}
    end
    boussole.config.minimapViews[zoneKey] = { zoom = minimap.map_zoom }
    settings.save()
end

-- Compute & return the offset that would center the player, without writing it
local function get_centered_offset(mapData, availWidth, availHeight, textureWidth)
    if not mapData or not mapData.entry then return nil, nil end

    local playerX, playerY, playerZ = map.get_player_position()
    if not playerX then return nil, nil end

    local mapX, mapY = map.world_to_map_coords(mapData.entry, playerX, playerY, playerZ)
    if not mapX then return nil, nil end

    local scale
    if mapData.entry._isCustomMap and mapData.entry._customData and mapData.entry._customData.referenceSize then
        scale = textureWidth / mapData.entry._customData.referenceSize
    else
        scale = textureWidth / 512.0
    end

    local texX = (mapX - mapData.entry.OffsetX) * scale
    local texY = (mapY - mapData.entry.OffsetY) * scale

    return (availWidth / 2) - texX * minimap.map_zoom,
        (availHeight / 2) - texY * minimap.map_zoom
end

-- Snap offset directly to centered position
local function compute_centered_offset(mapData, availWidth, availHeight, textureWidth)
    local tx, ty = get_centered_offset(mapData, availWidth, availHeight, textureWidth)
    if tx then
        minimap.map_offset.x = tx
        minimap.map_offset.y = ty
        return true
    end
    return false
end

-- Draw the minimap controls (labels toggle, reset zoom, lock position)
local function draw_controls(windowPosX, windowPosY, contentMinX, contentMinY, availWidth, availHeight)
    -- Ensure shared textures are loaded
    controls.load_textures()

    local padding = 6
    local buttonSize = 22
    local spacing = 3

    local startX = windowPosX + contentMinX + padding
    local startY = windowPosY + contentMinY + availHeight - padding - buttonSize

    imgui.SetCursorScreenPos({ startX, startY })
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 3.0)
    imgui.PushStyleVar(ImGuiStyleVar_FrameBorderSize, 0.0)

    local baseColor    = boussole.config.minimapColorControlsBtn
    local btnColor     = utils.rgb_to_abgr(baseColor)
    local hoverColor   = utils.rgb_to_abgr({ baseColor[1], baseColor[2], baseColor[3], math.min(1.0, (baseColor[4] or 1.0) + 0.2) })
    local actColor     = utils.rgb_to_abgr({ baseColor[1], baseColor[2], baseColor[3], math.min(1.0, (baseColor[4] or 1.0) + 0.3) })

    -- Button 1: Toggle labels
    local labelsActive = boussole.config.minimapShowLabels[1]

    imgui.PushStyleColor(ImGuiCol_Button, btnColor)
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, hoverColor)
    imgui.PushStyleColor(ImGuiCol_ButtonActive, actColor)

    if imgui.Button('##MinimapCtrl1', { buttonSize, buttonSize }) then
        boussole.config.minimapShowLabels[1] = not boussole.config.minimapShowLabels[1]
        settings.save()
    end
    local btn1Hovered = imgui.IsItemHovered()
    imgui.PopStyleColor(3)

    if controls.tag_texture then
        local drawList  = imgui.GetWindowDrawList()
        local iconSize  = buttonSize * 0.7
        local offsetX   = (buttonSize - iconSize) / 2
        local offsetY   = (buttonSize - iconSize) / 2
        local texPtr    = tonumber(ffi.cast('uint32_t', controls.tag_texture))
        local iconColor = labelsActive and utils.rgb_to_abgr(boussole.config.minimapColorControlsBtnActive) or 0xFFFFFFFF
        drawList:AddImage(texPtr,
            { startX + offsetX, startY + offsetY },
            { startX + offsetX + iconSize, startY + offsetY + iconSize },
            { 0, 0 }, { 1, 1 }, iconColor)
    end

    if btn1Hovered then imgui.SetTooltip('Display names above entities') end

    -- Button 2: Reset zoom
    imgui.SameLine(0, spacing)

    imgui.PushStyleColor(ImGuiCol_Button, btnColor)
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, hoverColor)
    imgui.PushStyleColor(ImGuiCol_ButtonActive, actColor)

    if imgui.Button('##MinimapCtrl2', { buttonSize, buttonSize }) then
        boussole.minimapResetZoom = true
    end
    local btn2Hovered = imgui.IsItemHovered()
    imgui.PopStyleColor(3)

    if controls.reset_texture then
        local drawList = imgui.GetWindowDrawList()
        local btn2PosX = startX + buttonSize + spacing
        local iconSize = buttonSize * 0.7
        local offsetX  = (buttonSize - iconSize) / 2
        local offsetY  = (buttonSize - iconSize) / 2
        local texPtr   = tonumber(ffi.cast('uint32_t', controls.reset_texture))
        drawList:AddImage(texPtr,
            { btn2PosX + offsetX, startY + offsetY },
            { btn2PosX + offsetX + iconSize, startY + offsetY + iconSize },
            { 0, 0 }, { 1, 1 }, 0xFFFFFFFF)
    end

    if btn2Hovered then imgui.SetTooltip('Reset minimap zoom') end

    -- Button 3: Lock/Unlock position
    imgui.SameLine(0, spacing)

    local isLocked      = boussole.config.minimapLocked[1]
    local lockLabel     = (isLocked and ICON_FA_LOCK or ICON_FA_UNLOCK) .. '##MinimapLock'

    -- Tint button background when locked to show active state
    local lockBtnColor  = isLocked and utils.rgb_to_abgr(boussole.config.minimapColorControlsBtnActive) or btnColor

    local lockIconColor = isLocked and utils.rgb_to_abgr(boussole.config.minimapColorControlsBtnActive) or 0xFFFFFFFF

    imgui.PushStyleColor(ImGuiCol_Button, lockBtnColor)
    imgui.PushStyleColor(ImGuiCol_ButtonHovered, hoverColor)
    imgui.PushStyleColor(ImGuiCol_ButtonActive, actColor)
    imgui.PushStyleColor(ImGuiCol_Text, lockIconColor)

    if imgui.Button(lockLabel, { buttonSize, buttonSize }) then
        boussole.config.minimapLocked[1] = not boussole.config.minimapLocked[1]
        settings.save()
    end
    local btn3Hovered = imgui.IsItemHovered()
    imgui.PopStyleColor(4)

    if btn3Hovered then
        imgui.SetTooltip(isLocked and 'Unlock minimap position' or 'Lock minimap position')
    end

    imgui.PopStyleVar(2)
end

-- Check if mouse is over the minimap content area
function minimap.is_over_map_area()
    if not minimap.window_bounds then return false end
    local mx, my = imgui.GetMousePos()
    return mx >= minimap.window_bounds.x1 and mx <= minimap.window_bounds.x2 and
        my >= minimap.window_bounds.y1 and my <= minimap.window_bounds.y2
end

-- Main draw function
function minimap.update()
    if not boussole.config.minimapVisible[1] then return end

    -- Grab shared texture from ui module
    local ui = require('src.ui')
    if not ui.texture_id or not ui.map_texture then return end
    if not map.current_map_data or not map.current_map_data.entry then return end

    local size = math.max(80, boussole.config.minimapSize[1] or 200)

    -- Detect zone change and restore saved zoom for the new zone
    local zoneKey = get_zone_key()
    if zoneKey ~= minimap.last_zone_key then
        local saved = load_zone_zoom(zoneKey)
        minimap.map_zoom = (saved and saved > 0) and saved or -1.0
        minimap.last_zone_key = zoneKey
        -- Reset pan/recenter state on zone change
        minimap.is_manually_panned = false
        minimap.is_recentering = false
        minimap.is_dragging = false
    end

    local isLocked = boussole.config.minimapLocked[1]

    -- Enforce square size every frame
    imgui.SetNextWindowSize({ size, size }, ImGuiCond_Always)

    local cornerRadius = boussole.config.minimapCornerRadius and boussole.config.minimapCornerRadius[1] or 0.0
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, cornerRadius)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })

    local windowFlags = bit.bor(
        ImGuiWindowFlags_NoTitleBar,
        ImGuiWindowFlags_NoScrollbar,
        ImGuiWindowFlags_NoScrollWithMouse,
        ImGuiWindowFlags_NoResize,
        ImGuiWindowFlags_NoBackground
    )
    if isLocked then
        windowFlags = bit.bor(windowFlags, ImGuiWindowFlags_NoMove)
    end

    if imgui.Begin('##boussole_minimap', boussole.config.minimapVisible, windowFlags) then
        imgui.PopStyleVar(2)

        local windowPosX, windowPosY   = imgui.GetWindowPos()
        local contentMinX, contentMinY = imgui.GetCursorStartPos()

        -- Available area inside the window
        local availWidth               = size - contentMinX
        local availHeight              = size - contentMinY

        -- Store bounds for mouse-over detection
        minimap.window_bounds          = {
            x1 = windowPosX + contentMinX,
            y1 = windowPosY + contentMinY,
            x2 = windowPosX + contentMinX + availWidth,
            y2 = windowPosY + contentMinY + availHeight,
        }

        local texW                     = ui.map_texture.width
        local texH                     = ui.map_texture.height

        -- Compute minimum zoom to fully cover available area
        local minZoomX                 = availWidth / texW
        local minZoomY                 = availHeight / texH
        local minZoom                  = math.min(minZoomX, minZoomY)

        -- First-time (or after zone change with no saved data) zoom initialisation
        if minimap.map_zoom < 0 then
            minimap.map_zoom = minZoom
        end

        -- Clamp zoom to valid range
        minimap.map_zoom = math.max(minZoom, math.min(minimap.map_zoom, 5.0))

        -- Reset zoom when requested (e.g. button press)
        if boussole.minimapResetZoom then
            minimap.map_zoom = minZoom
            save_zone_zoom(zoneKey)
            boussole.minimapResetZoom = false
        end

        -- Clamp offset so the map texture always fills the minimap window (no black borders)
        local function clamp_offset()
            local texWidth       = texW * minimap.map_zoom
            local texHeight      = texH * minimap.map_zoom
            minimap.map_offset.x = math.min(0, minimap.map_offset.x)
            minimap.map_offset.x = math.max(availWidth - texWidth, minimap.map_offset.x)
            minimap.map_offset.y = math.min(0, minimap.map_offset.y)
            minimap.map_offset.y = math.max(availHeight - texHeight, minimap.map_offset.y)
        end

        -- Mouse-wheel zoom (only when hovered)
        local isHovered = minimap.is_over_map_area()
        local mouseWheel = imgui.GetIO().MouseWheel
        if isHovered and mouseWheel ~= 0 then
            local step = boussole.config.minimapZoomStep[1] or 0.1
            local oldZoom = minimap.map_zoom
            local newZoom = math.max(minZoom, math.min(oldZoom + mouseWheel * step, 5.0))
            if newZoom ~= oldZoom then
                -- Keep the texture point under the cursor fixed during zoom
                local mx, my = imgui.GetMousePos()
                local mouseRelX = mx - (windowPosX + contentMinX)
                local mouseRelY = my - (windowPosY + contentMinY)
                local texPointX = (mouseRelX - minimap.map_offset.x) / oldZoom
                local texPointY = (mouseRelY - minimap.map_offset.y) / oldZoom
                minimap.map_zoom = newZoom
                minimap.map_offset.x = mouseRelX - texPointX * newZoom
                minimap.map_offset.y = mouseRelY - texPointY * newZoom
                clamp_offset()
                minimap.is_manually_panned = true
                minimap.last_pan_time = os.clock()
                save_zone_zoom(zoneKey)
            end
        end

        -- Delta time for smooth lerp
        local now = os.clock()
        local dt = math.min(now - minimap.last_frame_time, 0.1)
        minimap.last_frame_time = now

        -- Right-click drag to pan
        if imgui.IsMouseDown(1) then
            local mx, my = imgui.GetMousePos()
            if not minimap.is_dragging and minimap.is_over_map_area() then
                minimap.is_dragging = true
                minimap.is_recentering = false -- cancel any in-progress smooth recenter
                minimap.drag_start.x = mx
                minimap.drag_start.y = my
            elseif minimap.is_dragging then
                local dx = mx - minimap.drag_start.x
                local dy = my - minimap.drag_start.y
                if math.abs(dx) > 1 or math.abs(dy) > 1 then
                    minimap.map_offset.x = minimap.map_offset.x + dx
                    minimap.map_offset.y = minimap.map_offset.y + dy
                    clamp_offset()
                    minimap.drag_start.x = mx
                    minimap.drag_start.y = my
                    minimap.is_manually_panned = true
                    minimap.last_pan_time = os.clock()
                end
            end
        else
            minimap.is_dragging = false
        end

        -- Auto-recenter triggers (only checked while not actively dragging)
        local playerX, playerY = map.get_player_position()
        if minimap.is_manually_panned and not minimap.is_dragging then
            local timeout = boussole.config.minimapRecenterTimeout and boussole.config.minimapRecenterTimeout[1] or 5.0
            -- Optional: recenter when player moves significantly
            local recenterOnMove = boussole.config.minimapRecenterOnMove == nil or boussole.config.minimapRecenterOnMove[1]
            if recenterOnMove and playerX and minimap.last_player_pos then
                local dx = playerX - minimap.last_player_pos.x
                local dy = playerY - minimap.last_player_pos.y
                if math.sqrt(dx * dx + dy * dy) > 0.5 then
                    minimap.is_manually_panned = false
                    minimap.is_recentering = true
                end
            end
            -- Recenter on timeout (0 = disabled)
            if timeout > 0 and (os.clock() - minimap.last_pan_time) >= timeout then
                minimap.is_manually_panned = false
                minimap.is_recentering = true
            end
        end

        -- Only update reference position when not manually panned, so the recenter-on-move delta accumulates from the moment panning began
        if playerX and not minimap.is_manually_panned then
            minimap.last_player_pos = { x = playerX, y = playerY }
        end

        -- Apply offset: smooth lerp toward center, snap to center, or hold manual position
        if minimap.is_recentering then
            local tx, ty = get_centered_offset(map.current_map_data, availWidth, availHeight, texW)
            if tx then
                -- Clamp the target so the lerp path never exits valid bounds
                local texWidthZ      = texW * minimap.map_zoom
                local texHeightZ     = texH * minimap.map_zoom
                tx                   = math.min(0, math.max(availWidth - texWidthZ, tx))
                ty                   = math.min(0, math.max(availHeight - texHeightZ, ty))

                -- Exponential ease: closes ~86% of gap per second at speed=2
                local speed          = 4.0
                local t              = 1.0 - math.exp(-speed * dt)
                minimap.map_offset.x = minimap.map_offset.x + (tx - minimap.map_offset.x) * t
                minimap.map_offset.y = minimap.map_offset.y + (ty - minimap.map_offset.y) * t

                -- Snap once close enough
                if math.abs(minimap.map_offset.x - tx) < 0.5 and math.abs(minimap.map_offset.y - ty) < 0.5 then
                    minimap.map_offset.x = tx
                    minimap.map_offset.y = ty
                    minimap.is_recentering = false
                end
            else
                minimap.is_recentering = false
            end
        elseif not minimap.is_manually_panned then
            compute_centered_offset(map.current_map_data, availWidth, availHeight, texW)
            clamp_offset()
        end

        -- Computed texture draw position
        local texWidth       = texW * minimap.map_zoom
        local texHeight      = texH * minimap.map_zoom
        local posX           = windowPosX + contentMinX + minimap.map_offset.x
        local posY           = windowPosY + contentMinY + minimap.map_offset.y

        local texturePointer = tonumber(ffi.cast('uint32_t', ui.texture_id))
        if texturePointer then
            local drawList = imgui.GetWindowDrawList()

            -- Compute tint from opacity setting
            local opacity = boussole.config.minimapOpacity and boussole.config.minimapOpacity[1] or 1.0
            local alpha = math.floor(math.max(0.0, math.min(1.0, opacity)) * 255)
            local tint = bit.bor(bit.lshift(alpha, 24), 0x00FFFFFF)

            -- Minimap window corners in screen space
            local cx0 = windowPosX + contentMinX
            local cy0 = windowPosY + contentMinY
            local cx1 = cx0 + availWidth
            local cy1 = cy0 + availHeight

            -- Draw map texture and overlays, all clipped to the minimap content area
            drawList:PushClipRect({ cx0, cy0 }, { cx1, cy1 }, true)

            -- Draw the texture: if corner radius is set clamp the quad to the intersection
            -- of the window and the texture projection so UVs stay within [0,1], then
            -- let AddImageRounded cut the visible corners.
            if cornerRadius > 0 then
                local qx0 = math.max(cx0, posX)
                local qy0 = math.max(cy0, posY)
                local qx1 = math.min(cx1, posX + texWidth)
                local qy1 = math.min(cy1, posY + texHeight)
                if qx1 > qx0 and qy1 > qy0 then
                    local uvX0 = (qx0 - posX) / texWidth
                    local uvY0 = (qy0 - posY) / texHeight
                    local uvX1 = (qx1 - posX) / texWidth
                    local uvY1 = (qy1 - posY) / texHeight
                    -- Only round corners that coincide with the actual window corners
                    local eps = 0.5
                    local roundFlags = 0
                    if math.abs(qx0 - cx0) < eps and math.abs(qy0 - cy0) < eps then roundFlags = bit.bor(roundFlags, 1 * 16) end -- top-left
                    if math.abs(qx1 - cx1) < eps and math.abs(qy0 - cy0) < eps then roundFlags = bit.bor(roundFlags, 2 * 16) end -- top-right
                    if math.abs(qx0 - cx0) < eps and math.abs(qy1 - cy1) < eps then roundFlags = bit.bor(roundFlags, 4 * 16) end -- bottom-left
                    if math.abs(qx1 - cx1) < eps and math.abs(qy1 - cy1) < eps then roundFlags = bit.bor(roundFlags, 8 * 16) end -- bottom-right
                    if roundFlags == 0 then
                        drawList:AddImage(texturePointer, { qx0, qy0 }, { qx1, qy1 }, { uvX0, uvY0 }, { uvX1, uvY1 }, tint)
                    else
                        drawList:AddImageRounded(texturePointer, { qx0, qy0 }, { qx1, qy1 }, { uvX0, uvY0 }, { uvX1, uvY1 }, tint, cornerRadius, roundFlags)
                    end
                end
            else
                drawList:AddImage(
                    texturePointer,
                    { posX, posY },
                    { posX + texWidth, posY + texHeight },
                    { 0, 0 }, { 1, 1 },
                    tint
                )
            end

            tooltip.reset()

            -- Draw entity overlays
            local overlayAlpha = boussole.config.minimapOverlayOpacity and boussole.config.minimapOverlayOpacity[1] or 1.0
            local contextLabels = boussole.config.minimapShowLabels[1]

            -- Build minimap-specific context to pass directly to overlays
            local miniCtx = {
                showHomepoints        = boussole.config.minimapShowHomepoints,
                showSurvivalGuides    = boussole.config.minimapShowSurvivalGuides,
                showPlayer            = boussole.config.minimapShowPlayer,
                showParty             = boussole.config.minimapShowParty,
                showAlliance          = boussole.config.minimapShowAlliance,
                showTrackedEntities   = boussole.config.minimapShowTrackedEntities,
                enableTracker         = boussole.config.enableTracker,
                showLabels            = boussole.config.minimapShowLabels,
                iconSizeHomepoint     = boussole.config.minimapIconSizeHomepoint,
                iconSizeSurvivalGuide = boussole.config.minimapIconSizeSurvivalGuide,
                iconSizePlayer        = boussole.config.minimapIconSizePlayer,
                iconSizeParty         = boussole.config.minimapIconSizeParty,
                iconSizeAlliance      = boussole.config.minimapIconSizeAlliance,
                iconSizeTrackedEntity = boussole.config.minimapIconSizeTrackedEntity,
                colorHomepoint        = boussole.config.minimapColorHomepoint,
                colorSurvivalGuide    = boussole.config.minimapColorSurvivalGuide,
                colorPlayer           = boussole.config.minimapColorPlayer,
                colorParty            = boussole.config.minimapColorParty,
                colorAlliance         = boussole.config.minimapColorAlliance,
            }

            warp_overlay.draw(miniCtx, map.current_map_data,
                windowPosX, windowPosY, contentMinX, contentMinY,
                minimap.map_offset.x, minimap.map_offset.y,
                minimap.map_zoom, texW, overlayAlpha)

            tracked_entities.draw(miniCtx, map.current_map_data,
                windowPosX, windowPosY, contentMinX, contentMinY,
                minimap.map_offset.x, minimap.map_offset.y,
                minimap.map_zoom, texW, overlayAlpha, contextLabels)

            alliance_overlay.draw(miniCtx, map.current_map_data,
                windowPosX, windowPosY, contentMinX, contentMinY,
                minimap.map_offset.x, minimap.map_offset.y,
                minimap.map_zoom, texW, overlayAlpha, contextLabels)

            party_overlay.draw(miniCtx, map.current_map_data,
                windowPosX, windowPosY, contentMinX, contentMinY,
                minimap.map_offset.x, minimap.map_offset.y,
                minimap.map_zoom, texW, overlayAlpha, contextLabels)

            player_overlay.draw(miniCtx, map.current_map_data,
                windowPosX, windowPosY, contentMinX, contentMinY,
                minimap.map_offset.x, minimap.map_offset.y,
                minimap.map_zoom, texW, overlayAlpha, contextLabels)

            drawList:PopClipRect()

            -- Render accumulated tooltip from overlays
            tooltip.render()

            -- Draw minimap-specific controls only when mouse is over the minimap
            if minimap.is_over_map_area() then
                draw_controls(windowPosX, windowPosY, contentMinX, contentMinY, availWidth, availHeight)
            end
        end
    else
        imgui.PopStyleVar(2)
    end

    imgui.End()
end

return minimap
