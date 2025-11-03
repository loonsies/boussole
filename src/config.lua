local settings = require('settings')

local config = {}

local default = T {
    showHomepoints = { true },
    showSurvivalGuides = { true },
    showPlayer = { true },
    settingsPanelVisible = { false },
    mapView = {
        offsetX = 0,
        offsetY = 0,
        zoom = 1.0,
    },
}

config.load = function ()
    return settings.load(default)
end

return config
