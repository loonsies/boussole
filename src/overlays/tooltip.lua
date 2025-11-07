local tooltip = {}

local imgui = require('imgui')

-- Tooltip state
tooltip.active = false
tooltip.lines = {}

-- Reset tooltip state (call at start of each frame)
function tooltip.reset()
    tooltip.active = false
    tooltip.lines = {}
end

-- Add a line to the tooltip
function tooltip.add_line(text, color)
    table.insert(tooltip.lines, {
        text = text,
        color = color or 0xFFFFFFFF
    })
    tooltip.active = true
end

-- Add a separator to the tooltip
function tooltip.add_separator()
    table.insert(tooltip.lines, {
        separator = true
    })
end

-- Render the tooltip if it has content
function tooltip.render()
    if not tooltip.active or #tooltip.lines == 0 then
        return
    end

    if imgui.IsWindowHovered() and not boussole.panelHovered then
        imgui.BeginTooltip()

        for _, line in ipairs(tooltip.lines) do
            if line.separator then
                imgui.Separator()
            else
                if line.color and line.color ~= 0xFFFFFFFF then
                    -- Convert ABGR to float table {r, g, b, a}
                    local a = bit.band(bit.rshift(line.color, 24), 0xFF) / 255.0
                    local b = bit.band(bit.rshift(line.color, 16), 0xFF) / 255.0
                    local g = bit.band(bit.rshift(line.color, 8), 0xFF) / 255.0
                    local r = bit.band(line.color, 0xFF) / 255.0
                    imgui.TextColored({ r, g, b, a }, line.text)
                else
                    imgui.Text(line.text)
                end
            end
        end

        imgui.EndTooltip()
    end
end

-- Check if tooltip has content
function tooltip.has_content()
    return tooltip.active and #tooltip.lines > 0
end

return tooltip
