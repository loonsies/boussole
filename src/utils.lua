local utils = {}

local regionZones = require('data.regionZones')
local regions = require('data.regions')

function utils.getRegionIDByZoneID(zoneID)
    for regionID, zoneIDs in pairs(regionZones.map) do
        for _, id in ipairs(zoneIDs) do
            if id == zoneID then
                return regionID
            end
        end
    end
    return nil
end

function utils.getRegionNameById(id)
    if not regions then
        return nil
    end

    for _, region in ipairs(regions) do
        if region.id == id then
            return region.en
        end
    end
    return nil
end

function utils.rgb_to_abgr(rgbaTable)
    if not rgbaTable or #rgbaTable < 3 then
        return 0xFFFFFFFF
    end

    local r = math.floor((rgbaTable[1] or 1.0) * 255)
    local g = math.floor((rgbaTable[2] or 1.0) * 255)
    local b = math.floor((rgbaTable[3] or 1.0) * 255)
    local a = math.floor((rgbaTable[4] or 1.0) * 255)

    -- ABGR format: (A << 24) | (B << 16) | (G << 8) | R
    return bit.bor(
        bit.lshift(a, 24),
        bit.lshift(b, 16),
        bit.lshift(g, 8),
        r
    )
end

return utils
