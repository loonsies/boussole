local settings = require('settings')

local config = {}

local default = T {
    showHomepoints = { true },
    showSurvivalGuides = { true },
    showPlayer = { true },
    showParty = { true },
    showAlliance = { true },
    useCustomMaps = { false },
    settingsPanelVisible = { false },
    mapViews = {},
    mapRedirects = {},
    panelWidth = { 260 },
    iconSizeHomepoint = { 8 },
    iconSizeSurvivalGuide = { 8 },
    iconSizePlayer = { 20 },
    iconSizeParty = { 20 },
    iconSizeAlliance = { 20 },
    infoPanelFontSize = { 13 },
    colorHomepoint = { 0.0, 1.0, 1.0, 1.0 },
    colorSurvivalGuide = { 1.0, 0.667, 0.0, 1.0 },
    colorPlayer = { 1.0, 0.0, 0.0, 1.0 },
    colorParty = { 0.349, 0.639, 1.0, 1.0 },
    colorAlliance = { 0.212, 0.894, 0.424, 1.0 },
    colorInfoPanelBg = { 0.267, 0.267, 0.267, 0.533 },
    colorPanelBg = { 0.12, 0.12, 0.12, 0.85 },
    colorToggleBtn = { 0.53, 0.53, 0.53, 0.55 },
    customPoints = {},
    enableTracker = { false },
}

config.load = function ()
    return settings.load(default)
end

return config
