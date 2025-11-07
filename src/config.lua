local settings = require('settings')

local config = {}

local default = T {
    showHomepoints = { true },
    showSurvivalGuides = { true },
    showPlayer = { true },
    useCustomMaps = { false },
    settingsPanelVisible = { false },
    mapViews = {},
    mapRedirects = {},
}

config.load = function ()
    return settings.load(default)
end

return config
