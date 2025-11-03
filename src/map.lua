local map = {}

local mem = ashita.memory
local ffi = require('ffi')

local MAP_TABLE_SIG = '8A0D????????5333C05684C95774??8A5424188B7424148B7C2410B9'
local ENTRY_SIZE = 0x0E

ffi.cdef [[
    typedef int32_t (__thiscall* CheckFloorNumber_f)(void* pThis, float X, float Y, float Z);
    typedef uint32_t (__thiscall* GetFilePath_f)(void* pThis, uint32_t fileId, char* buffer, uint32_t bufferSize);

    typedef struct FILE FILE;
    int fopen_s(FILE** pFile, const char* filename, const char* mode);
    int fclose(FILE* stream);
    int fseek(FILE* stream, long offset, int origin);
    long ftell(FILE* stream);
    size_t fread(void* buffer, size_t size, size_t count, FILE* stream);
]]

map.table_ptr = 0
map.floor_func = nil
map.floor_this_ptr = nil
map.current_map_data = nil

function map.find_map_table()
    local addr = mem.find('FFXiMain.dll', 0, MAP_TABLE_SIG, 0, 0)
    if addr == 0 then
        return nil, 'signature not found'
    end

    map.table_ptr = mem.read_uint32(addr + 0x1C)
    if map.table_ptr == 0 then
        return nil, 'table pointer null'
    end
    return map.table_ptr
end

-- Initialize the GetMapFloorId function
function map.init_floor_function()
    local func_addr = mem.find('FFXiMain.dll', 0, '8B542408568D4424108BF18B4C2410508B44240C', 0, 0)
    local this_addr = mem.find('FFXiMain.dll', 0, '8B7424148B4424108B7C240C8B0D', 0x0E, 0)

    if func_addr == 0 or this_addr == 0 then
        return false, 'floor function signatures not found'
    end

    map.floor_func = ffi.cast('CheckFloorNumber_f', func_addr)
    map.floor_this_ptr = this_addr

    return true
end

function map.get_floor_id(x, y, z)
    if not map.floor_func or not map.floor_this_ptr then
        local ok, err = map.init_floor_function()
        if not ok then return nil, err end
    end

    -- Read the pointer to g_pTsZoneMap
    local this_ptr_val = mem.read_uint32(mem.read_uint32(map.floor_this_ptr))
    if this_ptr_val == 0 then
        return nil, 'g_pTsZoneMap is null'
    end

    -- Cast the pointer value to void* for the thiscall
    local this_obj = ffi.cast('void*', this_ptr_val)
    if this_obj == nil then
        return nil, 'g_pTsZoneMap object is null'
    end

    -- Y and Z are flipped
    local floor_id = map.floor_func(this_obj, x, z, y)
    return floor_id
end

-- Read a single map entry by zero-based index
function map.read_entry(index)
    if map.table_ptr == 0 then
        local ok, err = map.find_map_table()
        if not ok then return nil, err end
    end

    local base = map.table_ptr + (index * ENTRY_SIZE)
    local zone = mem.read_uint16(base + 0x00)
    local floorId = mem.read_uint8(base + 0x02)
    local floorIndex = mem.read_uint8(base + 0x03)
    local flags = mem.read_uint8(base + 0x04)
    -- Scale is signed in client logic (checks < 0)
    local scale_raw = mem.read_uint8(base + 0x05)
    local scale = (scale_raw >= 0x80) and (scale_raw - 0x100) or scale_raw
    -- KeyItemOffset treated as signed
    local keyoff_raw = mem.read_uint8(base + 0x06)
    local keyoff = (keyoff_raw >= 0x80) and (keyoff_raw - 0x100) or keyoff_raw
    local unknown = mem.read_uint8(base + 0x07)
    local mapDatOffset = mem.read_uint16(base + 0x08)
    -- OffsetX and OffsetY are signed 16-bit integers
    local offsetX_raw = mem.read_uint16(base + 0x0A)
    local offsetX = (offsetX_raw >= 0x8000) and (offsetX_raw - 0x10000) or offsetX_raw
    local offsetY_raw = mem.read_uint16(base + 0x0C)
    local offsetY = (offsetY_raw >= 0x8000) and (offsetY_raw - 0x10000) or offsetY_raw

    return {
        ZoneId = zone,
        FloorId = floorId,
        FloorIndex = floorIndex,
        Flags = flags,
        Scale = scale,
        KeyItemOffset = keyoff,
        Unknown0000 = unknown,
        MapDatOffset = mapDatOffset,
        OffsetX = offsetX,
        OffsetY = offsetY,
        _index = index,
        _base = base,
    }
end

function map.get_key_item_index(entry)
    local k = entry.KeyItemOffset

    if k < 0 then
        return 383
    end
    if k == 0 then
        return 384
    end

    local top = bit.band(entry.Flags, 0xF0)
    if top == 0x00 then
        return k + 384
    end
    if top == 0x10 then
        return k + 1855
    end
    if top == 0x20 then
        return k + 2301
    end

    return 384
end

function map.get_dat_index(entry)
    local low = bit.band(entry.Flags, 0x0F)

    if low == 0 then return entry.MapDatOffset + 5312 end
    if low == 1 then return entry.MapDatOffset + 53295 end
    if low == 2 then return entry.MapDatOffset + 54295 end
    return 5522
end

function map.find_entries_by_zone(zoneid)
    local results = {}
    local max_scan = 3000
    local zero_streak = 0
    for i = 0, max_scan - 1 do
        local e = map.read_entry(i)
        if not e then break end
        if e.ZoneId == zoneid then
            table.insert(results, e)
        end
        if e.ZoneId == 0 then
            zero_streak = zero_streak + 1
            if zero_streak > 16 then break end
        else
            zero_streak = 0
        end
    end
    return results
end

-- Find a single entry by zone + floorid
function map.find_entry_by_floor(zoneid, floorid)
    local entries = map.find_entries_by_zone(zoneid)
    for _, e in ipairs(entries) do
        if e.FloorId == floorid then
            return e
        end
    end
    return nil
end

-- Get current player zone ID
function map.get_player_zone()
    local party = AshitaCore:GetMemoryManager():GetParty()
    if party then
        return party:GetMemberZone(0)
    end
    return nil
end

-- Get current player position (X, Y, Z)
function map.get_player_position()
    local entity = GetPlayerEntity()
    if entity then
        return entity.Movement.LocalPosition.X, entity.Movement.LocalPosition.Y, entity.Movement.LocalPosition.Z
    end
    return nil, nil, nil
end

-- Get the current map entry for the player
function map.get_current_map()
    local zoneId = map.get_player_zone()
    if not zoneId then return nil, 'no zone' end

    local x, y, z = map.get_player_position()
    if not x then return nil, 'no position' end

    -- Get floor ID from game function
    local floorId, err = map.get_floor_id(x, y, z)
    if not floorId then
        return nil, 'floor detection failed'
    end

    -- Find the entry matching zone + floor
    local entry = map.find_entry_by_floor(zoneId, floorId)
    if entry then
        return entry, nil
    else
        return nil, 'no map entry found for floor'
    end
end

-- Get the DAT file path for a map entry
function map.get_dat_file_path(entry)
    if not entry then return nil, 'no entry' end

    local datIndex = map.get_dat_index(entry)
    if not datIndex then return nil, 'no dat index' end

    local resourceMgr = AshitaCore:GetResourceManager()
    if not resourceMgr then
        return nil, 'failed to get ResourceManager'
    end

    local filePath = resourceMgr:GetFilePath(datIndex)
    if not filePath or filePath == '' then
        return nil, 'failed to get DAT path for index: ' .. datIndex
    end

    return filePath
end

-- Load map DAT file
function map.load_map_dat(entry)
    local filePath, err = map.get_dat_file_path(entry)
    if not filePath then
        return nil, err
    end

    local SEEK_END = 2
    local SEEK_SET = 0

    -- Open file using fopen_s (XIPivot compatible)
    local filePtr = ffi.new('FILE*[1]')
    local result = ffi.C.fopen_s(filePtr, filePath, 'rb')

    if result ~= 0 or filePtr[0] == nil then
        -- Clean up if fopen_s set a handle but failed
        if filePtr[0] ~= nil then
            ffi.C.fclose(filePtr[0])
        end
        return nil, 'failed to open DAT file: ' .. filePath
    end

    local file = filePtr[0]

    -- Get file size
    if ffi.C.fseek(file, 0, SEEK_END) ~= 0 then
        ffi.C.fclose(file)
        return nil, 'failed to seek to end of DAT file'
    end

    local size = ffi.C.ftell(file)
    if size <= 0 then
        ffi.C.fclose(file)
        return nil, 'failed to determine DAT file size'
    end

    if ffi.C.fseek(file, 0, SEEK_SET) ~= 0 then
        ffi.C.fclose(file)
        return nil, 'failed to rewind DAT file'
    end

    -- Read file data
    local buffer = ffi.new('uint8_t[?]', size)
    local bytesRead = ffi.C.fread(buffer, 1, size, file)
    ffi.C.fclose(file)

    if bytesRead ~= size then
        return nil, 'failed to read complete DAT file'
    end

    -- Convert to Lua string
    local data = ffi.string(buffer, size)

    return data, nil
end

-- Load and cache the current map's DAT data
function map.load_current_map_dat()
    local entry, err = map.get_current_map()
    if not entry then
        return nil, err
    end

    local datPath, err = map.get_dat_file_path(entry)
    if not datPath then
        return nil, err
    end

    map.current_map_data = {
        entry = entry,
        datIndex = map.get_dat_index(entry),
        keyItemIndex = map.get_key_item_index(entry),
        datPath = datPath
    }

    return map.current_map_data, nil
end

-- Clear cached map data (call on zone change)
function map.clear_map_cache()
    map.current_map_data = nil
end

-- Calculate the map scaling divisor (2560.0 / Scale)
function map.get_divisor(entry)
    local scale = math.abs(entry.Scale)
    if scale == 0 then
        return 0.0
    end
    return 2560.0 / scale
end

-- Convert 3D world coords to 2D map pixel coords
function map.world_to_map_coords(entry, worldX, worldY, worldZ)
    local divisor = map.get_divisor(entry)
    if divisor == 0 then
        return nil, nil
    end

    -- Map coordinates = world * (1/divisor) * 512, rounded
    local v5 = 1.0 / divisor
    local mapX = math.floor(worldX * v5 * 512.0 + 0.5)
    local mapY_unsigned = math.floor(worldY * v5 * 512.0 + 0.5)
    local mapY = -mapY_unsigned -- Y is negated in map space

    -- Convert to signed 16-bit
    mapX = bit.band(mapX, 0xFFFF)
    if mapX >= 0x8000 then mapX = mapX - 0x10000 end
    mapY = bit.band(mapY, 0xFFFF)
    if mapY >= 0x8000 then mapY = mapY - 0x10000 end

    return mapX, mapY
end

-- Convert map pixel coords to grid position
function map.map_to_grid_coords(entry, mapX, mapY)
    -- (mapX - OffsetX - 16) / 32 + 'A'
    -- (mapY - OffsetY - 16) / 32 + 1
    local gridX = math.floor((mapX - entry.OffsetX - 16) / 32)
    local gridY = math.floor((mapY - entry.OffsetY - 16) / 32) + 1

    -- Convert X to letter (0=A, 1=B, etc)
    local gridXLetter = string.char(string.byte('A') + gridX)

    return gridXLetter, gridY
end

-- Get grid position for current player position
function map.get_player_grid_position()
    if not map.current_map_data then
        return nil, nil, 'no map data'
    end

    local x, y, z = map.get_player_position()
    if not x then
        return nil, nil, 'no player position'
    end

    local entry = map.current_map_data.entry
    local mapX, mapY = map.world_to_map_coords(entry, x, y, z)
    if not mapX then
        return nil, nil, 'invalid scale'
    end

    local gridX, gridY = map.map_to_grid_coords(entry, mapX, mapY)
    return gridX, gridY, nil
end

return map
