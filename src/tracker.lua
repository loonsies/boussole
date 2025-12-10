local tracker = {}

local chat = require('chat')

-- Local state
local trackedEntities = {} -- { [id] = { id, name, alias, color, alarm, draw, widescan, lastPacket } }
local zoneEntities = {}    -- { [id] = { id, name, index } }
local activeEntities = {}  -- { [id] = { x, y, z, lastSeen } }
local packetQueue = {}
local packetNextSend = 0
local lastSend = 0
local locationCache = {}

-- Profile management
local currentProfile = nil
local profiles = {}
local currentZoneId = 0

-- Degree map for direction calculation
local degreeMap = {
    { Degrees = -168.75, Direction = 'S' },
    { Degrees = -146.25, Direction = 'SSW' },
    { Degrees = -123.75, Direction = 'SW' },
    { Degrees = -101.25, Direction = 'WSW' },
    { Degrees = -78.75,  Direction = 'W' },
    { Degrees = -56.25,  Direction = 'WNW' },
    { Degrees = -33.75,  Direction = 'NW' },
    { Degrees = -11.25,  Direction = 'NNW' },
    { Degrees = 11.25,   Direction = 'N' },
    { Degrees = 33.75,   Direction = 'NNE' },
    { Degrees = 56.25,   Direction = 'NE' },
    { Degrees = 78.75,   Direction = 'ENE' },
    { Degrees = 101.25,  Direction = 'E' },
    { Degrees = 123.75,  Direction = 'ESE' },
    { Degrees = 146.25,  Direction = 'SE' },
    { Degrees = 168.75,  Direction = 'SSE' },
}

-- Calculate direction from player to entity
local function get_direction(position)
    local playerEntity = GetPlayerEntity()
    if position == nil or playerEntity == nil then
        return ', but position could not be detected'
    end

    local myPosition = {
        X = playerEntity.Movement.LocalPosition.X,
        Y = playerEntity.Movement.LocalPosition.Y,
        Z = playerEntity.Movement.LocalPosition.Z,
    }

    local xDiff = myPosition.X - position.X
    local yDiff = myPosition.Y - position.Y
    local distance = math.sqrt((xDiff * xDiff) + (yDiff * yDiff))
    local direction = 'S'

    local rads = math.atan2(position.X - myPosition.X, position.Y - myPosition.Y)
    local degrees = (rads * (180 / math.pi))
    for _, entry in ipairs(degreeMap) do
        if entry.Degrees > degrees then
            direction = entry.Direction
            break
        end
    end

    return string.format(' %0.1f yalms %s', distance, direction)
end

-- Load zone entities from DAT file
function tracker.load_zone_entities(zoneId, subZoneId)
    zoneEntities = {}
    currentZoneId = zoneId

    local dats = require('ffxi.dats')
    local file = dats.get_zone_npclist(zoneId, subZoneId)

    if file == nil or file:len() == 0 then
        return
    end

    local f = io.open(file, 'rb')
    if f == nil then
        return
    end

    local size = f:seek('end')
    f:seek('set', 0)

    if size == 0 or ((size - math.floor(size / 0x20) * 0x20) ~= 0) then
        f:close()
        return
    end

    for _ = 0, ((size / 0x20) - 0x01) do
        local data = f:read(0x20)
        local name, id = struct.unpack('c28L', data)
        name = name:trim('\0')

        if id > 0 and string.len(name) > 0 then
            zoneEntities[id] = {
                id = id,
                name = name,
                index = bit.band(id, 0x7FF)
            }
        end
    end

    f:close()
end

-- Get zone entities
function tracker.get_zone_entities()
    return zoneEntities
end

-- Get tracked entities
function tracker.get_tracked_entities()
    return trackedEntities
end

-- Get active entities (with positions)
function tracker.get_active_entities()
    return activeEntities
end

-- Get location cache
function tracker.get_location_cache()
    return locationCache
end

-- Add entity to tracking
function tracker.add_entity(id, name, alias)
    if not zoneEntities[id] then
        return false
    end

    -- Check if entity already exists
    if trackedEntities[id] then
        return 'exists'
    end

    -- Use default color from config
    local defaultColor = boussole.config.trackerDefaultColor or { 0.0, 0.5, 0.25, 1.0 }

    trackedEntities[id] = {
        id = id,
        zoneId = currentZoneId,
        name = name or zoneEntities[id].name,
        alias = alias or name or zoneEntities[id].name,
        color = { defaultColor[1], defaultColor[2], defaultColor[3], defaultColor[4] },
        alarm = false,
        draw = true,
        widescan = false,
        lastPacket = 0,
        timeout = 0,
    }

    return true
end

-- Remove entity from tracking
function tracker.remove_entity(id)
    trackedEntities[id] = nil
    activeEntities[id] = nil

    local count = 0
    -- Remove from packet queue if present
    for i = #packetQueue, 1, -1 do
        if packetQueue[i].id == id then
            table.remove(packetQueue, i)
            count = count + 1
        end
    end

    local index = bit.band(id, 0x7FF)
    if count > 0 then
        print(chat.header('boussole'):append(chat.message(string.format('Removed %d packets for entity ID %X from queue', count, index))))
    end
end

-- Update entity properties
function tracker.update_entity(id, properties)
    if trackedEntities[id] then
        for key, value in pairs(properties) do
            trackedEntities[id][key] = value
        end
        return true
    end
    return false
end

-- Clear all tracked entities
function tracker.clear_all()
    trackedEntities = {}
    activeEntities = {}

    if #packetQueue > 0 then
        print(chat.header('boussole'):append(chat.message(string.format('%d packets removed from queue', #packetQueue))))
    end

    packetQueue = {}
    locationCache = {}
    boussole.trackedSearchResults = nil
end

-- Clear zone-specific data on zone change
function tracker.clear_zone_data()
    activeEntities = {}
    locationCache = {}
    boussole.trackerSelections = {}
    boussole.trackedSearchResults = nil
end

-- Send single packet for entity
function tracker.send_single_packet(id)
    if not trackedEntities[id] then
        return false
    end

    local packet = struct.pack('LL', 0, bit.band(id, 0x7FF))
    AshitaCore:GetPacketManager():AddOutgoingPacket(0x16, packet:totable())
    trackedEntities[id].lastPacket = os.clock()

    -- Print chat message
    local entity = trackedEntities[id]
    local displayName = entity.alias or entity.name
    print(chat.header('boussole'):append(chat.message(string.format('Sent tracker packet for: %s', displayName))))

    return true
end

-- Send widescan for entity
function tracker.send_widescan(id)
    if not trackedEntities[id] then
        return false
    end

    local cmd = string.format('/watchdog track %u', bit.band(id, 0x7FF))
    AshitaCore:GetChatManager():QueueCommand(-1, cmd)

    return true
end

-- Queue all tracked entities for packet sending
function tracker.send_all_packets()
    packetQueue = {}
    for id, entity in pairs(trackedEntities) do
        table.insert(packetQueue, entity)
    end
    packetNextSend = os.clock()

    -- Print chat message
    if #packetQueue > 0 then
        print(chat.header('boussole'):append(chat.message(string.format('Starting tracker packet queue: %d entities', #packetQueue))))
    end
end

-- Process packet queue
function tracker.process_packet_queue()
    if #packetQueue > 0 and os.clock() >= packetNextSend then
        local entity = table.remove(packetQueue, 1)
        if entity then
            tracker.send_single_packet(entity.id)
        end
        packetNextSend = os.clock() + boussole.config.trackerPacketDelay[1]

        -- Print completion message when queue finishes
        if #packetQueue == 0 then
            print(chat.header('boussole'):append(chat.message('Tracker packet queue completed')))
        end
    end
end

-- Get packet queue status
function tracker.is_sending_packets()
    return #packetQueue > 0
end

-- Handle incoming entity update packet (0x00E)
function tracker.handle_entity_update(e)
    local id = struct.unpack('L', e.data, 0x04 + 1)

    if not trackedEntities[id] then
        return
    end

    local mask = struct.unpack('B', e.data, 0x0A + 1)

    -- Check if entity is hidden
    if bit.band(mask, 0x07) ~= 0 then
        local flags1 = struct.unpack('L', e.data, 0x20 + 1)
        if bit.band(flags1, 0x02) == 2 then
            activeEntities[id] = nil
            return
        end
    else
        -- Not dealing with these packets
        if bit.band(mask, 0x20) == 0x20 then
            activeEntities[id] = nil
        end
        return
    end

    -- Check HP
    if bit.band(mask, 0x04) == 0x04 then
        local hp = struct.unpack('B', e.data, 0x1E + 1)
        if hp == 0 then
            activeEntities[id] = nil
            return
        end
    elseif AshitaCore:GetMemoryManager():GetEntity():GetHPPercent(bit.band(id, 0xFFF)) == 0 then
        -- Fallback HP check using memory manager
        activeEntities[id] = nil
        return
    end

    -- Get position
    local index = struct.unpack('H', e.data, 0x08 + 1)
    local position = locationCache[index]

    if position == nil then
        local enemyEntity = GetEntity(index)
        if enemyEntity then
            position = {
                x = enemyEntity.Movement.LocalPosition.X,
                y = enemyEntity.Movement.LocalPosition.Y,
                z = enemyEntity.Movement.LocalPosition.Z,
            }
        end
    end

    if position then
        activeEntities[id] = {
            x = position.x,
            y = position.y,
            z = position.z,
            lastSeen = os.clock(),
            index = index
        }

        -- Trigger alarm if enabled
        local entity = trackedEntities[id]
        if entity.alarm then
            -- Play sound (would need to implement sound playing)
        end

        -- Auto widescan if enabled
        if entity.widescan then
            tracker.send_widescan(id)
        end
    end
end

-- Handle position cache update (0x0E with position data)
function tracker.cache_position(index, x, y, z)
    locationCache[index] = { x = x, y = y, z = z }
end

-- Process entity timeouts
function tracker.process_timeouts()
    local currentTime = os.clock()
    for id, entity in pairs(trackedEntities) do
        -- Only process if timeout is enabled (> 0) and entity is active
        if entity.timeout > 0 and activeEntities[id] then
            local timeSinceLastSeen = currentTime - activeEntities[id].lastSeen
            if timeSinceLastSeen >= entity.timeout then
                activeEntities[id] = nil
            end
        end
    end
end

-- Handle zone change
function tracker.handle_zone_change()
    tracker.clear_zone_data()

    -- Clear packet queue and notify if packets were queued
    if tracker.is_sending_packets() then
        print(chat.header('boussole'):append(chat.message(string.format('%d packets removed from queue due to zone change', #packetQueue))))
        packetQueue = {}
    end
end

-- Profile management
function tracker.get_profiles()
    return profiles
end

function tracker.get_current_profile()
    return currentProfile
end

function tracker.save_profile(name)
    if not name or name == '' then
        return false
    end

    profiles[name] = {}
    for id, entity in pairs(trackedEntities) do
        table.insert(profiles[name], {
            id = id,
            zoneId = entity.zoneId,
            name = entity.name,
            alias = entity.alias,
            color = { entity.color[1], entity.color[2], entity.color[3], entity.color[4] },
            alarm = entity.alarm,
            draw = entity.draw,
            widescan = entity.widescan,
            timeout = entity.timeout or 0
        })
    end

    currentProfile = name
    return true
end

function tracker.load_profile(name)
    if not name or not profiles[name] then
        return false
    end

    trackedEntities = {}
    for _, entity in ipairs(profiles[name]) do
        local id = entity.id
        if entity.zoneId == currentZoneId and zoneEntities[id] then
            trackedEntities[id] = {
                id = id,
                zoneId = entity.zoneId,
                name = entity.name,
                alias = entity.alias,
                color = { entity.color[1], entity.color[2], entity.color[3], entity.color[4] },
                alarm = entity.alarm,
                draw = entity.draw,
                widescan = entity.widescan,
                lastPacket = 0,
                timeout = entity.timeout or 0
            }
        end
    end

    currentProfile = name
    activeEntities = {}
    return true
end

function tracker.delete_profile(name)
    if not name or not profiles[name] then
        return false
    end

    profiles[name] = nil
    if currentProfile == name then
        currentProfile = nil
    end

    return true
end

function tracker.set_profiles(loadedProfiles)
    profiles = loadedProfiles or {}
end

function tracker.set_current_profile(name)
    currentProfile = name
end

-- Save tracker data to JSON file
function tracker.save_tracker_data()
    local profiles = tracker.get_profiles()
    local data = {
        profiles = profiles
    }

    local json = require('json')
    local settingsPath = string.format('%s/config/addons/%s/', AshitaCore:GetInstallPath(), 'boussole')
    local filePath = settingsPath .. 'tracker_profiles.json'

    -- Ensure directory exists
    ashita.fs.create_dir(settingsPath)

    local file = io.open(filePath, 'w')
    if file then
        file:write(json.encode(data))
        file:close()
    end
end

-- Load tracker data from JSON file
function tracker.load_tracker_data()
    local json = require('json')
    local settingsPath = string.format('%s/config/addons/%s/', AshitaCore:GetInstallPath(), 'boussole')
    local filePath = settingsPath .. 'tracker_profiles.json'

    local file = io.open(filePath, 'r')
    if file then
        local content = file:read('*all')
        file:close()

        local success, data = pcall(json.decode, content)
        if success and data then
            if data.profiles then
                tracker.set_profiles(data.profiles)
            end
        end
    end
end

return tracker
