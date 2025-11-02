local settings = require('settings')

local config = {}

local default = T {
    showHomepoints = { true },
    showSurvivalGuides = { true },
    showPlayer = { true },
    settingsPanelVisible = { false },
}

config.load = function ()
    return settings.load(default)
end

return config
