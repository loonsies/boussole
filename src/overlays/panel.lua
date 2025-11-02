local panel = {}

local imgui = require('imgui')
local settings = require('settings')

-- Panel state
panel.width = 200

-- Draw the settings panel on the right side
function panel.draw(config, windowPosX, windowPosY, contentMinX, contentMinY, contentMaxX, contentMaxY)
    local panelWidth = panel.width
    local toggleButtonWidth = 20
    local buttonSpacing = 5 -- Space between button and panel
    local isPanelVisible = config.settingsPanelVisible[1]

    -- Calculate positions
    local panelX = windowPosX + contentMaxX - (isPanelVisible and panelWidth or 0)
    local panelY = windowPosY + contentMinY
    local panelHeight = contentMaxY - contentMinY

    local toggleButtonX = isPanelVisible and (panelX - toggleButtonWidth - buttonSpacing) or (windowPosX + contentMaxX - toggleButtonWidth)
    local toggleButtonY = panelY + (panelHeight / 2) - 30

    local drawList = imgui.GetWindowDrawList()

    -- Draw toggle button background
    local buttonColor = 0xFF444444
    local buttonHoverColor = 0xFF666666
    local buttonTextColor = 0xFFFFFFFF

    -- Check if mouse is over toggle button
    local mousePosX, mousePosY = imgui.GetMousePos()
    local isHoveringButton = mousePosX >= toggleButtonX and mousePosX <= (toggleButtonX + toggleButtonWidth) and
        mousePosY >= toggleButtonY and mousePosY <= (toggleButtonY + 60)

    -- Draw visual button background
    drawList:AddRectFilled(
        { toggleButtonX, toggleButtonY },
        { toggleButtonX + toggleButtonWidth, toggleButtonY + 60 },
        isHoveringButton and buttonHoverColor or buttonColor,
        3.0
    )

    -- Draw toggle button text
    local buttonText = isPanelVisible and '>' or '<'
    local textSizeX, textSizeY = imgui.CalcTextSize(buttonText)
    local textX = toggleButtonX + (toggleButtonWidth - textSizeX) / 2
    local textY = toggleButtonY + (60 - textSizeY) / 2

    drawList:AddText({ textX, textY }, buttonTextColor, buttonText)

    -- Create a small window for the toggle button to capture clicks
    imgui.SetCursorPos({ toggleButtonX - windowPosX, toggleButtonY - windowPosY })

    if imgui.BeginChild('##PanelToggle', { toggleButtonWidth, 60 }, false, bit.bor(ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoBackground)) then
        if imgui.InvisibleButton('##ToggleBtn', { toggleButtonWidth, 60 }) then
            config.settingsPanelVisible[1] = not isPanelVisible
            settings.save()
        end
    end
    imgui.EndChild()

    -- Draw panel if visible
    if isPanelVisible then
        -- Draw panel background
        drawList:AddRectFilled(
            { panelX, panelY },
            { panelX + panelWidth, panelY + panelHeight },
            0xE0222222,
            0.0
        )

        -- Draw panel border
        drawList:AddRect(
            { panelX, panelY },
            { panelX + panelWidth, panelY + panelHeight },
            0xFF444444,
            0.0,
            0,
            1.0
        )

        -- Create an invisible window for the panel widgets
        imgui.SetCursorPos({ panelX - windowPosX, panelY - windowPosY })

        if imgui.BeginChild('##Panel', { panelWidth, panelHeight }, false, bit.bor(ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoBackground)) then
            imgui.Text('Display Options')
            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()

            if imgui.Checkbox('Homepoints', config.showHomepoints) then
                settings.save()
            end
            imgui.Spacing()

            if imgui.Checkbox('Survival Guides', config.showSurvivalGuides) then
                settings.save()
            end
            imgui.Spacing()

            if imgui.Checkbox('Player (me)', config.showPlayer) then
                settings.save()
            end
            imgui.Spacing()
        end
        imgui.EndChild()
    end
end

return panel
