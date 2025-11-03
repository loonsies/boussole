local ui = {}

local imgui = require('imgui')
local chat = require('chat')
local map = require('src/map')
local texture_module = require('src/texture')
local info_overlay = require('src/overlays/info')
local player_overlay = require('src/overlays/player')
local warp_overlay = require('src/overlays/warp')
local tooltip = require('src/overlays/tooltip')
local panel = require('src/overlays/panel')
local ffi = require('ffi')
local d3d8 = require('d3d8')

-- Cached map texture
ui.map_texture = nil
ui.texture_id = nil

-- Map view state
ui.map_offset = { x = 0, y = 0 } -- Pan offset
ui.map_zoom = 1.0                -- Zoom level
ui.is_dragging = false
ui.drag_start = { x = 0, y = 0 }
ui.window_bounds = nil    -- Window content area bounds for mouse blocking
ui.window_focused = false -- Whether our window has focus

-- Restore map view state from config
function ui.restore_view_state()
    if boussole.config.mapView then
        ui.map_offset.x = boussole.config.mapView.offsetX or 0
        ui.map_offset.y = boussole.config.mapView.offsetY or 0
        ui.map_zoom = boussole.config.mapView.zoom or 1.0
    end
end

-- Save current map view state to config
function ui.save_view_state()
    boussole.config.mapView = {
        offsetX = ui.map_offset.x,
        offsetY = ui.map_offset.y,
        zoom = ui.map_zoom,
    }
end

function ui.load_map_texture()
    -- Clean up old texture
    if ui.texture_id then
        ui.texture_id = nil
    end

    -- Get the DAT data
    if not map.current_map_data then
        print(chat.header(addon.name):append(chat.warning('No map data loaded')))
        return false
    end

    local datData, err = map.load_map_dat(map.current_map_data.entry)
    if not datData then
        print(chat.header(addon.name):append(chat.error(string.format('Failed to load map DAT: %s', err))))
        return false
    end

    local d3d8dev = d3d8.get_device()

    -- Load texture using texture module
    local gcTexture, texture_data, err = texture_module.load_texture_to_d3d(datData, d3d8dev)

    datData = nil

    if not gcTexture then
        print(chat.header(addon.name):append(chat.error(string.format('Failed to load texture: %s', err))))
        return false
    end

    ui.texture_id = gcTexture
    ui.texture_ptr = nil

    ui.map_texture = {
        width = texture_data.width,
        height = texture_data.height,
        type = texture_data.type
    }

    texture_data = nil

    collectgarbage('collect')

    return true
end

function ui.load_nomap_texture()
    -- Clean up old texture
    if ui.texture_id then
        ui.texture_id = nil
    end

    local d3d8dev = d3d8.get_device()
    local nomap_path = string.format('%saddons\\boussole\\assets\\nomap.png', AshitaCore:GetInstallPath())

    local gcTexture, texture_data, err = texture_module.load_texture_from_file(nomap_path, d3d8dev)

    if not gcTexture then
        print(chat.header(addon.name):append(chat.error(string.format('Failed to load nomap.png: %s', err))))
        return false
    end

    ui.texture_id = gcTexture
    ui.texture_ptr = nil

    ui.map_texture = {
        width = texture_data.width,
        height = texture_data.height,
        type = texture_data.type
    }

    texture_data = nil

    collectgarbage('collect')
    return true
end

function ui.drawUI()
    imgui.SetNextWindowSize({ 800, 600 }, ImGuiCond_FirstUseEver)

    if imgui.Begin('boussole', boussole.visible, bit.bor(ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse)) then
        -- Track window focus state
        ui.window_focused = imgui.IsWindowFocused()

        if ui.texture_id and ui.map_texture then
            local windowPosX, windowPosY = imgui.GetWindowPos()
            local windowWidth, windowHeight = imgui.GetWindowSize()
            local contentMinX, contentMinY = imgui.GetWindowContentRegionMin()
            local contentMaxX, contentMaxY = imgui.GetWindowContentRegionMax()

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
            if isMapHovered and mouseWheel ~= 0 then
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
                    local mousePosX, mousePosY = imgui.GetMousePos()
                    ui.drag_start.x = mousePosX
                    ui.drag_start.y = mousePosY
                elseif ui.is_dragging then
                    -- Continue dragging even if mouse leaves window
                    local mousePosX, mousePosY = imgui.GetMousePos()
                    local deltaX = mousePosX - ui.drag_start.x
                    local deltaY = mousePosY - ui.drag_start.y

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
                ui.is_dragging = false
            end

            -- Always ensure zoom fits map in window (handles window resize)
            local minZoomX = availWidth / ui.map_texture.width
            local minZoomY = availHeight / ui.map_texture.height
            local minZoom = math.min(minZoomX, minZoomY)
            ui.map_zoom = math.max(ui.map_zoom, minZoom) -- Enforce minimum zoom

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

            -- Draw the map texture
            local texturePointer = tonumber(ffi.cast('uint32_t', ui.texture_id))
            if texturePointer then
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

                info_overlay.draw(contentMinX, contentMinY, map.current_map_data)

                -- Reset tooltip state for this frame
                tooltip.reset()

                warp_overlay.draw(boussole.config, map.current_map_data, windowPosX, windowPosY,
                    contentMinX, contentMinY,
                    ui.map_offset.x, ui.map_offset.y,
                    ui.map_zoom, ui.map_texture.width)

                player_overlay.draw(boussole.config, map.current_map_data, windowPosX, windowPosY,
                    contentMinX, contentMinY,
                    ui.map_offset.x, ui.map_offset.y,
                    ui.map_zoom, ui.map_texture.width)

                -- Add grid position to tooltip if hovering over map
                if isMapHovered and map.current_map_data then
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

                panel.draw(boussole.config, windowPosX, windowPosY, contentMinX, contentMinY, contentMaxX, contentMaxY)

                tooltip.render()
            end
        else
            imgui.Text('No map texture loaded')
            if imgui.Button('Load Map Texture') then
                ui.load_map_texture()
            end
        end

        imgui.End()
    end
end

function ui.update()
    if not boussole.visible[1] then
        return
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
