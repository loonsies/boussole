local warp_points = {}

local chat = require('chat')

warp_points.homepoints = {}
warp_points.survival_guides = {}

local function parse_warp_xml(content)
    local entries = {}

    -- Match all <entry ...> tags
    for entry_str in content:gmatch('<entry[^>]+>') do
        local entry = {}

        -- Extract attributes
        entry.alias = entry_str:match('alias="([^"]+)"')
        entry.bitflag = tonumber(entry_str:match('bitflag="([^"]+)"'))
        entry.param = tonumber(entry_str:match('param="([^"]+)"'))
        entry.zone = tonumber(entry_str:match('zone="([^"]+)"'))
        entry.posx = tonumber(entry_str:match('posx="([^"]+)"'))
        entry.posy = tonumber(entry_str:match('posy="([^"]+)"'))
        entry.posz = tonumber(entry_str:match('posz="([^"]+)"'))

        if entry.zone and entry.posx and entry.posy and entry.posz then
            table.insert(entries, entry)
        end
    end

    return entries
end

-- Load homepoint data from XML
function warp_points.load_homepoints()
    local filepath = string.format('%s\\addons\\boussole\\data\\homepoint.xml', AshitaCore:GetInstallPath())

    local f = io.open(filepath, 'r')
    if not f then
        print(chat.header(addon.name):append(chat.error('Failed to open homepoint.xml')))
        return false
    end

    local content = f:read('*all')
    f:close()

    local entries = parse_warp_xml(content)
    if not entries then
        print(chat.header(addon.name):append(chat.error('Failed to parse homepoint.xml')))
        return false
    end

    warp_points.homepoints = {}

    for _, point in ipairs(entries) do
        -- Group by zone
        if not warp_points.homepoints[point.zone] then
            warp_points.homepoints[point.zone] = {}
        end

        table.insert(warp_points.homepoints[point.zone], point)
    end

    print(chat.header(addon.name):append(chat.success(string.format('Loaded %d homepoints', #entries))))
    return true
end

-- Load survival guide data from XML
function warp_points.load_survival_guides()
    local filepath = string.format('%s\\addons\\boussole\\data\\survivalguide.xml', AshitaCore:GetInstallPath())

    local f = io.open(filepath, 'r')
    if not f then
        print(chat.header(addon.name):append(chat.error('Failed to open survivalguide.xml')))
        return false
    end

    local content = f:read('*all')
    f:close()

    local entries = parse_warp_xml(content)
    if not entries then
        print(chat.header(addon.name):append(chat.error('Failed to parse survivalguide.xml')))
        return false
    end

    warp_points.survival_guides = {}

    for _, point in ipairs(entries) do
        -- Group by zone
        if not warp_points.survival_guides[point.zone] then
            warp_points.survival_guides[point.zone] = {}
        end

        table.insert(warp_points.survival_guides[point.zone], point)
    end

    print(chat.header(addon.name):append(chat.success(string.format('Loaded %d survival guides', #entries))))
    return true
end

-- Initialize - load all warp point data
function warp_points.init()
    warp_points.load_homepoints()
    warp_points.load_survival_guides()
end

return warp_points
