utils = {}

local regionZones = require('data/regionZones')
local regions = require('data/regions')

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

return utils
