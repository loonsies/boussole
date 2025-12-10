local ui = {}

local imgui = require('imgui')
local chat = require('chat')
local settings = require('settings')
local map = require('src.map')
local texture = require('src.texture')
local info_overlay = require('src.overlays.info')
local player_overlay = require('src.overlays.player')
local party_overlay = require('src.overlays.party')
local alliance_overlay = require('src.overlays.alliance')
local warp_overlay = require('src.overlays.warp')
local custom_points = require('src.overlays.custom_points')
local tracked_entities = require('src.overlays.tracked_entities')
local tooltip = require('src.overlays.tooltip')
local controls = require('src.overlays.controls')
local panel = require('src.overlays.panel')
local ffi = require('ffi')

-- Cached map texture
ui.map_texture = nil
ui.texture_id = nil

-- Map view state
ui.map_offset = { x = 0, y = 0 }
ui.map_zoom = 0.0
ui.is_dragging = false
ui.drag_start = { x = 0, y = 0 }
ui.drag_moved = false
ui.window_bounds = nil
ui.window_focused = false
ui.current_view_key = nil
ui.last_saved_offset = { x = 0, y = 0 }
ui.last_saved_zoom = 0.0
ui.save_timer = 0

-- Get the key for current zone+floor
function ui.get_view_key()
    if not map.current_map_data or not map.current_map_data.entry then
        return nil
    end
    local zoneId = map.current_map_data.entry.ZoneId
    local floorId = map.current_map_data.entry.FloorId
    return string.format('%d_%d', zoneId, floorId)
end

-- Restore map view state from config for current zone+floor
function ui.restore_view_state()
    local viewKey = ui.get_view_key()
    if viewKey and boussole.config.mapViews and boussole.config.mapViews[viewKey] then
        local savedView = boussole.config.mapViews[viewKey]
        ui.map_offset.x = savedView.offsetX or 0
        ui.map_offset.y = savedView.offsetY or 0
        ui.map_zoom = savedView.zoom or -1
        ui.current_view_key = viewKey
    else
        -- Reset to defaults if no saved view
        ui.map_offset.x = 0
        ui.map_offset.y = 0
        ui.map_zoom = -1
        ui.current_view_key = viewKey
    end

    -- Update last saved values to match restored values
    ui.last_saved_offset.x = ui.map_offset.x
    ui.last_saved_offset.y = ui.map_offset.y
    ui.last_saved_zoom = ui.map_zoom
end

-- Save current map view state to config for current zone+floor
function ui.save_view_state()
    local viewKey = ui.get_view_key()
    if viewKey then
        if not boussole.config.mapViews then
            boussole.config.mapViews = {}
        end
        boussole.config.mapViews[viewKey] = {
            offsetX = ui.map_offset.x,
            offsetY = ui.map_offset.y,
            zoom = ui.map_zoom,
        }
        ui.current_view_key = viewKey

        -- Update last saved values
        ui.last_saved_offset.x = ui.map_offset.x
        ui.last_saved_offset.y = ui.map_offset.y
        ui.last_saved_zoom = ui.map_zoom
    end
end

function ui.save_view_state_debounce()
    local changed = math.abs(ui.map_offset.x - ui.last_saved_offset.x) > 0.1 or
        math.abs(ui.map_offset.y - ui.last_saved_offset.y) > 0.1 or
        math.abs(ui.map_zoom - ui.last_saved_zoom) > 0.01

    if changed then
        local current_time = os.clock()

        if current_time - ui.save_timer > 1 then
            ui.save_view_state()
            settings.save()
            ui.save_timer = current_time
        end
    end
end

-- Center map on player position
function ui.center_on_player(mapData, availWidth, availHeight, textureWidth, textureHeight)
    if not mapData or not mapData.entry then
        return false
    end

    local playerX, playerY, playerZ = map.get_player_position()
    if not playerX then
        return false
    end

    -- Convert world position to map coordinates
    local mapX, mapY = map.world_to_map_coords(mapData.entry, playerX, playerY, playerZ)
    if not mapX or not mapY then
        return false
    end

    -- Convert map coordinates to texture coordinates
    local scale = textureWidth / 512.0
    local texX = (mapX - mapData.entry.OffsetX) * scale
    local texY = (mapY - mapData.entry.OffsetY) * scale

    -- Calculate texture display size with zoom
    local texWidth = textureWidth * ui.map_zoom
    local texHeight = textureHeight * ui.map_zoom

    -- Center the texture point on screen
    local newOffsetX = (availWidth / 2) - (texX * ui.map_zoom)
    local newOffsetY = (availHeight / 2) - (texY * ui.map_zoom)

    -- Clamp to prevent going out of bounds
    if texWidth > availWidth then
        newOffsetX = math.min(0, newOffsetX)
        newOffsetX = math.max(availWidth - texWidth, newOffsetX)
    else
        newOffsetX = (availWidth - texWidth) / 2
    end

    if texHeight > availHeight then
        newOffsetY = math.min(0, newOffsetY)
        newOffsetY = math.max(availHeight - texHeight, newOffsetY)
    else
        newOffsetY = (availHeight - texHeight) / 2
    end

    ui.map_offset.x = newOffsetX
    ui.map_offset.y = newOffsetY

    return true
end

function ui.drawUI()
    imgui.SetNextWindowSize({ 800, 600 }, ImGuiCond_FirstUseEver)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })

    if imgui.Begin('boussole', boussole.visible, bit.bor(ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse)) then
        imgui.PopStyleVar()

        -- Track window focus state
        ui.window_focused = imgui.IsWindowFocused()

        if ui.texture_id and ui.map_texture then
            local windowPosX, windowPosY = imgui.GetWindowPos()
            local windowWidth, windowHeight = imgui.GetWindowSize()
            local contentMinX, contentMinY = imgui.GetCursorStartPos()
            local contentMaxX = windowWidth
            local contentMaxY = windowHeight

            -- Calculate available space for map
            local availWidth = contentMaxX - contentMinX
            local availHeight = contentMaxY - contentMinY

            -- Store window content bounds for manual mouse position checking in event handler
            ui.window_bounds = {
                x1 = windowPosX + contentMinX,
                y1 = windowPosY + contentMinY,
                x2 = windowPosX + contentMaxX,
                y2 = windowPosY + contentMaxY
            }

            -- Check if mouse is over the map area using manual bounds check
            local isMapHovered = ui.is_over_map_area()

            -- Handle mouse wheel for zoom
            local mouseWheel = imgui.GetIO().MouseWheel
            if isMapHovered and mouseWheel ~= 0 and not boussole.dropdownOpened and not boussole.panelHovered and not custom_points.popup_state.open then
                -- Get mouse position relative to content area
                local mousePosX, mousePosY = imgui.GetMousePos()
                local mouseRelX = mousePosX - (windowPosX + contentMinX)
                local mouseRelY = mousePosY - (windowPosY + contentMinY)

                -- Calculate point on texture that mouse is over (before zoom)
                local texPointX = (mouseRelX - ui.map_offset.x) / ui.map_zoom
                local texPointY = (mouseRelY - ui.map_offset.y) / ui.map_zoom

                -- Calculate minimum zoom to fit entire texture in window
                local minZoomX = availWidth / ui.map_texture.width
                local minZoomY = availHeight / ui.map_texture.height
                local minZoom = math.min(minZoomX, minZoomY) -- Use min to fit entire map

                -- Update zoom
                ui.map_zoom = ui.map_zoom + mouseWheel * 0.1
                ui.map_zoom = math.max(minZoom, math.min(ui.map_zoom, 5.0)) -- Clamp zoom from minZoom to 5x

                -- Adjust offset so the same texture point stays under the mouse
                ui.map_offset.x = mouseRelX - texPointX * ui.map_zoom
                ui.map_offset.y = mouseRelY - texPointY * ui.map_zoom
            end

            -- Calculate texture display size with zoom (after zoom changes)
            local texWidth = ui.map_texture.width * ui.map_zoom
            local texHeight = ui.map_texture.height * ui.map_zoom

            -- Handle right mouse button for dragging (button 1 = right click)
            -- Start drag only when hovered, but continue even if mouse leaves window
            if imgui.IsMouseDown(1) then
                if not ui.is_dragging and isMapHovered then
                    -- Start dragging only when over the map
                    ui.is_dragging = true
                    ui.drag_moved = false
                    local mousePosX, mousePosY = imgui.GetMousePos()
                    ui.drag_start.x = mousePosX
                    ui.drag_start.y = mousePosY
                elseif ui.is_dragging then
                    -- Continue dragging even if mouse leaves window
                    local mousePosX, mousePosY = imgui.GetMousePos()
                    local deltaX = mousePosX - ui.drag_start.x
                    local deltaY = mousePosY - ui.drag_start.y

                    -- Check if mouse actually moved
                    if math.abs(deltaX) > 2 or math.abs(deltaY) > 2 then
                        ui.drag_moved = true
                    end

                    -- Calculate new offset with delta
                    local newOffsetX = ui.map_offset.x + deltaX
                    local newOffsetY = ui.map_offset.y + deltaY

                    -- Clamp to prevent dragging out of bounds
                    if texWidth > availWidth then
                        newOffsetX = math.min(0, newOffsetX)
                        newOffsetX = math.max(availWidth - texWidth, newOffsetX)
                    else
                        newOffsetX = (availWidth - texWidth) / 2
                    end

                    if texHeight > availHeight then
                        newOffsetY = math.min(0, newOffsetY)
                        newOffsetY = math.max(availHeight - texHeight, newOffsetY)
                    else
                        newOffsetY = (availHeight - texHeight) / 2
                    end

                    ui.map_offset.x = newOffsetX
                    ui.map_offset.y = newOffsetY
                    ui.drag_start.x = mousePosX
                    ui.drag_start.y = mousePosY
                end
            else
                -- Right mouse button released
                if ui.is_dragging and not ui.drag_moved and isMapHovered and not boussole.panelHovered and map.current_map_data and map.current_map_data.entry then
                    -- Open custom point popup if it wasn't a drag action
                    local mousePosX, mousePosY = imgui.GetMousePos()

                    -- Check if clicking on an existing point
                    local clickedPoint = custom_points.find_point_at_position(
                        map.current_map_data.entry.ZoneId,
                        map.current_map_data.entry.FloorId,
                        mousePosX, mousePosY,
                        map.current_map_data,
                        windowPosX, windowPosY,
                        contentMinX, contentMinY,
                        ui.map_offset.x, ui.map_offset.y,
                        ui.map_zoom,
                        ui.map_texture.width
                    )

                    if clickedPoint then
                        -- Edit existing point
                        custom_points.open_edit_popup(
                            map.current_map_data.entry.ZoneId,
                            map.current_map_data.entry.FloorId,
                            clickedPoint.id,
                            clickedPoint.point
                        )
                    else
                        -- Add new point - convert mouse to map coordinates
                        local texPosX = windowPosX + contentMinX + ui.map_offset.x
                        local texPosY = windowPosY + contentMinY + ui.map_offset.y
                        local texMouseX = (mousePosX - texPosX) / ui.map_zoom
                        local texMouseY = (mousePosY - texPosY) / ui.map_zoom

                        -- Check if click is within texture bounds
                        if texMouseX >= 0 and texMouseX <= ui.map_texture.width and
                            texMouseY >= 0 and texMouseY <= ui.map_texture.height then
                            -- Scale texture coordinates to 512x512 map coordinate space
                            local scale = 512.0 / ui.map_texture.width
                            local mapX = texMouseX * scale + map.current_map_data.entry.OffsetX
                            local mapY = texMouseY * scale + map.current_map_data.entry.OffsetY

                            custom_points.open_add_popup(
                                map.current_map_data.entry.ZoneId,
                                map.current_map_data.entry.FloorId,
                                mapX, mapY
                            )
                        end
                    end
                end
                ui.is_dragging = false
                ui.drag_moved = false
            end

            -- Always ensure zoom fits map in window (handles window resize)
            local minZoomX = availWidth / ui.map_texture.width
            local minZoomY = availHeight / ui.map_texture.height
            local minZoom = math.min(minZoomX, minZoomY)

            -- If zoom is -1 (not initialized), set it to minimum zoom for full map view
            if ui.map_zoom < 0 then
                ui.map_zoom = minZoom
                ui.last_saved_zoom = minZoom
            else
                ui.map_zoom = math.max(ui.map_zoom, minZoom)
            end

            -- Recalculate texture size with enforced zoom
            texWidth = ui.map_texture.width * ui.map_zoom
            texHeight = ui.map_texture.height * ui.map_zoom

            -- Always clamp offsets to keep map in bounds (handles window resize)
            if texWidth > availWidth then
                ui.map_offset.x = math.min(0, ui.map_offset.x)
                ui.map_offset.x = math.max(availWidth - texWidth, ui.map_offset.x)
            else
                ui.map_offset.x = (availWidth - texWidth) / 2
            end

            if texHeight > availHeight then
                ui.map_offset.y = math.min(0, ui.map_offset.y)
                ui.map_offset.y = math.max(availHeight - texHeight, ui.map_offset.y)
            else
                ui.map_offset.y = (availHeight - texHeight) / 2
            end

            -- Handle center on player mode
            if boussole.config.centerOnPlayer[1] then
                ui.center_on_player(map.current_map_data, availWidth, availHeight, ui.map_texture.width, ui.map_texture.height)
            end

            -- Handle one-time recenter
            if boussole.recenterMap then
                ui.center_on_player(map.current_map_data, availWidth, availHeight, ui.map_texture.width, ui.map_texture.height)
                boussole.recenterMap = false
            end

            -- Handle zoom reset
            if boussole.resetZoom then
                local minZoomX = availWidth / ui.map_texture.width
                local minZoomY = availHeight / ui.map_texture.height
                local minZoom = math.min(minZoomX, minZoomY)
                ui.map_zoom = minZoom

                -- Center the map after resetting zoom
                ui.map_offset.x = (availWidth - ui.map_texture.width * ui.map_zoom) / 2
                ui.map_offset.y = (availHeight - ui.map_texture.height * ui.map_zoom) / 2

                boussole.resetZoom = false
            end

            -- Draw the map texture
            local texturePointer = tonumber(ffi.cast('uint32_t', ui.texture_id))
            if texturePointer and map.current_map_data and map.current_map_data.entry then
                -- Calculate position
                local posX = windowPosX + contentMinX + ui.map_offset.x
                local posY = windowPosY + contentMinY + ui.map_offset.y

                -- Draw texture
                imgui.GetWindowDrawList():AddImage(
                    texturePointer,
                    { posX, posY },
                    { posX + texWidth, posY + texHeight },
                    { 0, 0 },  -- UV min
                    { 1, 1 },  -- UV max
                    0xFFFFFFFF -- White tint
                )

                info_overlay.draw(windowPosX, windowPosY, contentMinX, contentMinY, map.current_map_data)

                -- Reset tooltip state for this frame
                tooltip.reset()

                warp_overlay.draw(map.current_map_data, windowPosX, windowPosY,
                    contentMinX, contentMinY,
                    ui.map_offset.x, ui.map_offset.y,
                    ui.map_zoom, ui.map_texture.width)

                custom_points.draw(map.current_map_data, windowPosX, windowPosY,
                    contentMinX, contentMinY,
                    ui.map_offset.x, ui.map_offset.y,
                    ui.map_zoom, ui.map_texture.width)

                tracked_entities.draw(map.current_map_data, windowPosX, windowPosY,
                    contentMinX, contentMinY,
                    ui.map_offset.x, ui.map_offset.y,
                    ui.map_zoom, ui.map_texture.width)

                player_overlay.draw(map.current_map_data, windowPosX, windowPosY,
                    contentMinX, contentMinY,
                    ui.map_offset.x, ui.map_offset.y,
                    ui.map_zoom, ui.map_texture.width)

                party_overlay.draw(boussole.config, map.current_map_data, windowPosX, windowPosY,
                    contentMinX, contentMinY,
                    ui.map_offset.x, ui.map_offset.y,
                    ui.map_zoom, ui.map_texture.width)

                alliance_overlay.draw(boussole.config, map.current_map_data, windowPosX, windowPosY,
                    contentMinX, contentMinY,
                    ui.map_offset.x, ui.map_offset.y,
                    ui.map_zoom, ui.map_texture.width)

                -- Add grid position to tooltip if hovering over map
                if isMapHovered and map.current_map_data and map.current_map_data.entry then
                    local mousePosX, mousePosY = imgui.GetMousePos()

                    -- Convert mouse position to texture coordinates
                    local texMouseX = (mousePosX - posX) / ui.map_zoom
                    local texMouseY = (mousePosY - posY) / ui.map_zoom

                    -- Check if mouse is actually over the texture (not just the window)
                    if texMouseX >= 0 and texMouseX <= ui.map_texture.width and
                        texMouseY >= 0 and texMouseY <= ui.map_texture.height then
                        -- Scale texture coordinates to 512x512 map coordinate space
                        local scale = 512.0 / ui.map_texture.width
                        local mapX = texMouseX * scale + map.current_map_data.entry.OffsetX
                        local mapY = texMouseY * scale + map.current_map_data.entry.OffsetY

                        local gridX, gridY = map.map_to_grid_coords(map.current_map_data.entry, mapX, mapY)

                        -- Add separator before grid coords if tooltip has other content
                        if tooltip.has_content() then
                            tooltip.add_separator()
                        end

                        tooltip.add_line(string.format('(%s-%d)', gridX, gridY))
                    end
                end

                panel.draw(windowPosX, windowPosY, contentMinX, contentMinY, contentMaxX, contentMaxY)

                local controlsHovered = controls.draw(windowPosX, windowPosY, contentMinX, contentMinY)

                -- Only render map tooltip if not hovering controls
                if not controlsHovered then
                    tooltip.render()
                end

                custom_points.draw_popup()

                ui.save_view_state_debounce()
            end
        else
            imgui.Text('No map texture loaded')
            if imgui.Button('Reload Map') then
                texture.load_and_set(ui, map.current_map_data, chat, addon.name)
            end
        end
    else
        imgui.PopStyleVar()
    end
    imgui.End()
end

function ui.update()
    if not boussole.visible[1] then
        return
    end

    if boussole.manualMapReload[1] then
        if boussole.manualZoneId[1] and boussole.manualFloorId[1] then
            local entry = map.find_entry_by_floor(boussole.manualZoneId[1], boussole.manualFloorId[1])
            if entry then
                map.current_map_data = { entry = entry }
                texture.load_and_set(ui, map.current_map_data, chat, addon.name)
            end
        end
        boussole.manualMapReload[1] = false
    end

    ui.drawUI()
end

-- Check if mouse is over map area
function ui.is_over_map_area()
    if not ui.window_bounds then
        return false
    end

    -- Get current mouse position
    local mouseX, mouseY = imgui.GetMousePos()

    -- Check if mouse is within window content bounds
    return mouseX >= ui.window_bounds.x1 and mouseX <= ui.window_bounds.x2 and
        mouseY >= ui.window_bounds.y1 and mouseY <= ui.window_bounds.y2
end

return ui
