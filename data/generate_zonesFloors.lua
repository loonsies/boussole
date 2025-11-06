-- Floor Data Generator for Boussole
-- This script scans the map table in memory and generates a Lua table with zone floor data

local map = require('src.map')
local zones = require('data.zones')

-- Build a lookup table of valid zone IDs from zones.lua
local valid_zones = {}
for _, zone in pairs(zones) do
    if zone.id then
        valid_zones[zone.id] = true
    end
end

-- Specific zone+floor combinations to exclude (unused/duplicate maps)
-- Format: [zoneid] = { excluded_floor_ids }
-- from https://github.com/Windower/ResourceExtractor/blob/73d8b2469f7afcddb0d61d04efca97caa02d51f9/MapParser.cs
local excluded_floors = {
    [2] = { 0 },                -- 0 is not used in game
    [29] = { 2 },               -- Duplicate of map 1
    [30] = { 2 },               -- Duplicate of map 1
    [44] = { 2 },               -- Duplicate of map 1
    [140] = { 15 },             -- 15 is not used in game
    [142] = { 0 },              -- Duplicate of map 1
    [169] = { 3 },              -- Duplicate of map 2
    [171] = { 0 },              -- 0 is a dummy map
    [173] = { 0 },              -- 0 is not used in game
    [174] = { 0 },              -- 0 is not used in game
    [190] = { 1001 },           -- Duplicate of map 1
    [191] = { 0 },              -- Duplicate of map 1
    [205] = { 1015, 1016, 18 }, -- 1015/1016 never made it to game, 18 not used
    [226] = { 0 },              -- 0 is a dummy map
    [242] = { 0 },              -- 0 is a dummy map
}

local function is_floor_excluded(zoneid, floorid)
    local excluded = excluded_floors[zoneid]
    if not excluded then
        return false
    end

    for _, fid in ipairs(excluded) do
        if fid == floorid then
            return true
        end
    end
    return false
end

-- Initialize map table
print('Initializing map table...')
local ok, err = map.find_map_table()
if not ok then
    print('Error: ' .. tostring(err))
    return
end

-- Scan all entries
print('Scanning map entries...')
local zones_floors = {}
local entry_count = 0

for i = 0, 3000 do
    local entry = map.read_entry(i)

    if entry and entry.ZoneId > 0 and valid_zones[entry.ZoneId] then
        local zoneid = entry.ZoneId
        local floorid = entry.FloorId

        if not is_floor_excluded(zoneid, floorid) then
            if not zones_floors[zoneid] then
                zones_floors[zoneid] = {}
            end

            local found = false
            for _, floor_data in ipairs(zones_floors[zoneid]) do
                if floor_data.floor == floorid then
                    found = true
                    break
                end
            end

            if not found then
                table.insert(zones_floors[zoneid], {
                    floor = floorid,
                    index = i
                })
            end

            entry_count = entry_count + 1
        end
    end
end

print(string.format('Found %d entries across %d zones', entry_count, #zones_floors))

-- Sort by floor ID within each zone
for zoneid, floors in pairs(zones_floors) do
    table.sort(floors, function (a, b) return a.floor < b.floor end)
end

-- Generate Lua file content
local output = {}
table.insert(output, '-- Auto-generated zone floor data')
table.insert(output, '-- Generated: ' .. os.date('%Y-%m-%d %H:%M:%S'))
table.insert(output, '')
table.insert(output, 'local zones_floors = {')

-- Get sorted zone IDs
local zone_ids = {}
for zoneid, _ in pairs(zones_floors) do
    table.insert(zone_ids, zoneid)
end
table.sort(zone_ids)

-- Write each zone
for _, zoneid in ipairs(zone_ids) do
    local floors = zones_floors[zoneid]
    table.insert(output, string.format('    [%d] = {', zoneid))

    for _, floor_data in ipairs(floors) do
        table.insert(output, string.format('        [%d] = %d,', floor_data.floor, floor_data.index))
    end

    table.insert(output, '    },')
end

table.insert(output, '}')
table.insert(output, '')
table.insert(output, 'return zones_floors')
table.insert(output, '')

-- Write to file
local addon_path = AshitaCore:GetInstallPath() .. 'addons\\boussole\\data\\zonesFloors.lua'
local file = io.open(addon_path, 'w')
if file then
    file:write(table.concat(output, '\n'))
    file:close()
    print('Successfully generated: ' .. addon_path)
else
    print('Error: Could not write to file')
end
