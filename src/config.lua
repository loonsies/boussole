local settings = require('settings')

local config = {}

local default = T {
    showHomepoints = { true },
    showSurvivalGuides = { true },
    showPlayer = { true },
    showParty = { true },
    showAlliance = { true },
    showTrackedEntities = { true },
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
    iconSizeTrackedEntity = { 10 },
    colorHomepoint = { 0.0, 1.0, 1.0, 1.0 },
    colorSurvivalGuide = { 1.0, 0.667, 0.0, 1.0 },
    colorPlayer = { 1.0, 0.0, 0.0, 1.0 },
    colorParty = { 0.349, 0.639, 1.0, 1.0 },
    colorAlliance = { 0.212, 0.894, 0.424, 1.0 },
    colorInfoPanelBg = { 0.267, 0.267, 0.267, 0.533 },
    colorPanelBg = { 0.12, 0.12, 0.12, 0.85 },
    colorToggleBtn = { 0.53, 0.53, 0.53, 0.55 },
    colorControlsBtn = { 0.267, 0.267, 0.267, 0.533 },
    colorControlsBtnActive = { 0.2941, 0.3922, 0.7843, 1.0 },
    centerOnPlayer = { false },
    showLabels = { false },
    customPoints = {},
    enableTracker = { false },
    lastLoadedTrackerProfile = '',
    trackerPacketDelay = { 1.5 },
    trackerIdentifierType = 'Index (Hex)',
    trackerDefaultColor = { 0.0, 0.5, 0.25, 1.0 },
}

config.load = function ()
    return settings.load(default)
end

return config
