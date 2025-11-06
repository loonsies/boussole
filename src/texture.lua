local ffi = require('ffi')
local d3d8 = require('d3d8')
local map = require('src.map')

local C = ffi.C;
local texture = {}

-- Image header structure (48 bytes)
ffi.cdef [[
    typedef struct {
        uint32_t structLength;
        int32_t width;
        int32_t height;
        uint16_t planes;
        uint16_t bitCount;
        uint32_t compression;
        uint32_t imageSize;
        uint32_t horizontalResolution;
        uint32_t verticalResolution;
        uint32_t usedColors;
        uint32_t importantColors;
        uint32_t type;
    } ImageHeader;

    typedef struct {
        uint8_t b, g, r, a;
    } Color;
]]

-- Image types
local IMAGE_TYPE = {
    UNKNOWN = 0,
    BITMAP = 0x0000000A,
    DXT1 = 0x44585431,
    DXT2 = 0x44585432,
    DXT3 = 0x44585433,
    DXT4 = 0x44585434,
    DXT5 = 0x44585435,
}

local function get_image_type_name(type_id)
    if type_id == IMAGE_TYPE.DXT1 then
        return 'DXT1'
    elseif type_id == IMAGE_TYPE.DXT2 then
        return 'DXT2'
    elseif type_id == IMAGE_TYPE.DXT3 then
        return 'DXT3'
    elseif type_id == IMAGE_TYPE.DXT4 then
        return 'DXT4'
    elseif type_id == IMAGE_TYPE.DXT5 then
        return 'DXT5'
    elseif type_id == IMAGE_TYPE.BITMAP then
        return 'BITMAP'
    else
        return 'UNKNOWN'
    end
end

-- Helper: read uint8 from data
local function read_u8(data, offset)
    return string.byte(data, offset + 1)
end

-- Helper: read uint16 LE from data
local function read_u16(data, offset)
    return read_u8(data, offset) + read_u8(data, offset + 1) * 256
end

-- Helper: read uint32 LE from data
local function read_u32(data, offset)
    return read_u8(data, offset) +
        read_u8(data, offset + 1) * 256 +
        read_u8(data, offset + 2) * 65536 +
        read_u8(data, offset + 3) * 16777216
end

-- Helper: read uint64 LE from data
local function read_u64(data, offset)
    local low = read_u32(data, offset)
    local high = read_u32(data, offset + 4)

    return low, high
end

-- Decode RGB565 color
local function decode_rgb565(rgb565)
    local r = math.floor(bit.band(bit.rshift(rgb565, 11), 0x1F) * 255 / 31)
    local g = math.floor(bit.band(bit.rshift(rgb565, 5), 0x3F) * 255 / 63)
    local b = math.floor(bit.band(rgb565, 0x1F) * 255 / 31)
    return r, g, b
end

-- Read color based on bit depth (BitmapParser.ReadColor)
local function read_color(data, offset, bitDepth)
    if bitDepth == 8 then
        local gray = read_u8(data, offset)
        return gray, gray, gray, 255, 1
    elseif bitDepth == 16 then
        local rgb565 = read_u16(data, offset)
        local r, g, b = decode_rgb565(rgb565)
        return r, g, b, 255, 2
    elseif bitDepth == 24 then
        local b = read_u8(data, offset)
        local g = read_u8(data, offset + 1)
        local r = read_u8(data, offset + 2)
        return r, g, b, 255, 3
    elseif bitDepth == 32 then
        local b = read_u8(data, offset)
        local g = read_u8(data, offset + 1)
        local r = read_u8(data, offset + 2)
        local a = read_u8(data, offset + 3)
        -- Alpha: nonzero becomes 255, zero stays 0
        a = (a > 0) and 255 or 0
        return r, g, b, a, 4
    else
        return 255, 0, 255, 255, 0 -- Hot pink for unknown
    end
end

-- Parse ImageHeader at given offset
function texture.parse_image_header(data, offset)
    if #data < offset + ffi.sizeof('ImageHeader') then
        return nil, 'Data too small for ImageHeader'
    end

    local header = ffi.cast('ImageHeader*', ffi.cast('uint8_t*', ffi.cast('const char*', data)) + offset)[0]

    return {
        structLength = header.structLength,
        width = header.width,
        height = header.height,
        planes = header.planes,
        bitCount = header.bitCount,
        compression = header.compression,
        imageSize = header.imageSize,
        horizontalResolution = header.horizontalResolution,
        verticalResolution = header.verticalResolution,
        usedColors = header.usedColors,
        importantColors = header.importantColors,
        type = header.type,
        typeName = get_image_type_name(header.type),
    }
end

-- Copy bitmap data to texture
function texture.copy_bitmap(data, d3d8dev, header, dataOffset, ignoreAlpha)
    local result, dx_texture = d3d8dev:CreateTexture(
        header.width,
        header.height,
        1,
        0,
        C.D3DFMT_A8R8G8B8,
        C.D3DPOOL_MANAGED
    )

    if result ~= C.S_OK or not dx_texture then
        return nil, nil, string.format('Failed to create texture: 0x%08X', result)
    end

    local lockResult, lockedRect = dx_texture:LockRect(0, nil, 0)
    if lockResult ~= C.S_OK or not lockedRect then
        dx_texture:Release()
        return nil, nil, string.format('Failed to lock texture: 0x%08X', lockResult)
    end

    if lockedRect.pBits == nil then
        dx_texture:UnlockRect(0)
        dx_texture:Release()
        return nil, nil, 'Texture lock returned null surface pointer'
    end

    local dest = ffi.cast('uint8_t*', lockedRect.pBits)
    local pitch = lockedRect.Pitch
    local palette = nil
    local offset = dataOffset

    if header.bitCount == 8 then
        palette = {}
        for i = 0, 255 do
            local r, g, b, a = read_color(data, offset, 32)
            palette[i] = { r = r, g = g, b = b, a = a }
            offset = offset + 4
        end
    end

    local pixelCount = header.width * header.height

    if header.bitCount == 8 then
        for pixelIdx = 0, pixelCount - 1 do
            local paletteIdx = read_u8(data, offset)
            offset = offset + 1

            local color = palette[paletteIdx]
            if color then
                -- Flip Y coordinate (bitmaps are stored upside down)
                local x = pixelIdx % header.width
                local y = math.floor(pixelIdx / header.width)
                local flippedY = header.height - 1 - y

                local surfaceOffset = flippedY * pitch + x * 4
                dest[surfaceOffset + 0] = color.b
                dest[surfaceOffset + 1] = color.g
                dest[surfaceOffset + 2] = color.r
                dest[surfaceOffset + 3] = ignoreAlpha and 255 or color.a
            end
        end
    else
        for pixelIdx = 0, pixelCount - 1 do
            local r, g, b, a, bytesRead = read_color(data, offset, header.bitCount)
            offset = offset + bytesRead

            -- Flip Y coordinate (bitmaps are stored upside down)
            local x = pixelIdx % header.width
            local y = math.floor(pixelIdx / header.width)
            local flippedY = header.height - 1 - y

            local surfaceOffset = flippedY * pitch + x * 4
            dest[surfaceOffset + 0] = b
            dest[surfaceOffset + 1] = g
            dest[surfaceOffset + 2] = r
            dest[surfaceOffset + 3] = ignoreAlpha and 255 or a
        end
    end

    -- Unlock the texture
    dx_texture:UnlockRect(0)

    local d3d8 = require('d3d8')
    local gcTexture = d3d8.gc_safe_release(ffi.cast('IDirect3DBaseTexture8*', dx_texture))

    local result_data = {
        width = header.width,
        height = header.height,
        type = header.typeName
    }

    return gcTexture, result_data, nil
end

-- Copy DXT data to texture
function texture.copy_dxt(data, d3d8dev, header, offset, d3dFormat)
    local result, dx_texture = d3d8dev:CreateTexture(
        header.width,
        header.height,
        1, -- mipLevels
        0, -- usage
        d3dFormat,
        C.D3DPOOL_MANAGED
    )

    if result ~= C.S_OK or not dx_texture then
        return nil, nil, string.format('Failed to create texture: 0x%08X', result)
    end

    local lockResult, lockedRect = dx_texture:LockRect(0, nil, 0)

    if lockResult ~= C.S_OK or not lockedRect then
        dx_texture:Release()
        return nil, nil, string.format('Failed to lock texture: 0x%08X', lockResult)
    end

    if lockedRect.pBits == nil then
        dx_texture:UnlockRect(0)
        dx_texture:Release()
        return nil, nil, 'Texture lock returned null surface pointer'
    end

    -- Calculate compressed data size
    local compressedSize
    if header.type == IMAGE_TYPE.DXT1 then
        -- DXT1: 8 bytes per 4x4 block
        compressedSize = math.max(1, header.width / 4) * math.max(1, header.height / 4) * 8
    else -- DXT2, DXT3, DXT4, DXT5: 16 bytes per 4x4 block
        compressedSize = math.max(1, header.width / 4) * math.max(1, header.height / 4) * 16
    end

    local src = ffi.cast('const uint8_t*', ffi.cast('const char*', data)) + offset
    local dest = ffi.cast('uint8_t*', lockedRect.pBits)
    ffi.copy(dest, src, compressedSize)

    dx_texture:UnlockRect(0)

    local gcTexture = d3d8.gc_safe_release(ffi.cast('IDirect3DBaseTexture8*', dx_texture))

    local result_data = {
        width = header.width,
        height = header.height,
        type = header.typeName
    }

    return gcTexture, result_data, nil
end

-- Load from DAT and create texure
function texture.load_texture_to_d3d(datData, d3d8dev)
    local header, err = texture.parse_image_header(datData, 0x41)
    if not header then
        return nil, nil, err
    end

    -- Validate dimensions
    if header.width <= 0 or header.height <= 0 then
        return nil, nil, 'Invalid texture dimensions parsed from DAT'
    end

    local d3dFormat

    if header.type == IMAGE_TYPE.DXT1 then
        d3dFormat = C.D3DFMT_DXT1
    elseif header.type == IMAGE_TYPE.DXT2 then
        d3dFormat = C.D3DFMT_DXT2
    elseif header.type == IMAGE_TYPE.DXT3 then
        d3dFormat = C.D3DFMT_DXT3
    elseif header.type == IMAGE_TYPE.DXT4 then
        d3dFormat = C.D3DFMT_DXT4
    elseif header.type == IMAGE_TYPE.DXT5 then
        d3dFormat = C.D3DFMT_DXT5
    elseif header.type == IMAGE_TYPE.BITMAP then
        local dataOffset = 0x41 + ffi.sizeof('ImageHeader')
        return texture.copy_bitmap(datData, d3d8dev, header, dataOffset, false)
    else
        return nil, nil, string.format('Unsupported image type: %s (0x%08X)', header.typeName, header.type)
    end

    local offset = 0x41 + ffi.sizeof('ImageHeader') + 8 -- Unknown 8 bytes after header
    return texture.copy_dxt(datData, d3d8dev, header, offset, d3dFormat)
end

function texture.load_texture_from_file(filePath, d3d8dev)
    local texture_ptr = ffi.new('IDirect3DTexture8*[1]')
    local hr = C.D3DXCreateTextureFromFileA(d3d8dev, filePath, texture_ptr)

    if hr ~= C.S_OK or texture_ptr[0] == nil then
        return nil, nil, string.format('D3DXCreateTextureFromFileA failed: 0x%08X', hr)
    end

    local gcTexture = d3d8.gc_safe_release(ffi.cast('IDirect3DBaseTexture8*', texture_ptr[0]))

    -- Get texture dimensions
    local _, desc = ffi.cast('IDirect3DTexture8*', texture_ptr[0]):GetLevelDesc(0)

    -- Extract file extension for type
    local fileType = filePath:match('%.([^%.]+)$')
    if fileType then
        fileType = fileType:upper()
    else
        fileType = 'UNKNOWN'
    end

    local result = {
        width = desc.Width,
        height = desc.Height,
        type = fileType
    }

    return gcTexture, result, nil
end

-- Check if a custom map exists for the current zone and floor
function texture.get_custom_map_path(map_data)
    if not map_data then
        return nil
    end

    local entry = map_data.entry
    local zoneId = entry.ZoneId
    local floorId = entry.FloorId

    -- Try multiple image formats
    local formats = { 'png', 'bmp', 'jpg', 'jpeg', 'dds', 'tga' }

    for _, ext in ipairs(formats) do
        local customPath = string.format('%sconfig\\addons\\%s\\custom\\%d_%d.%s',
            AshitaCore:GetInstallPath(),
            addon.name,
            zoneId,
            floorId,
            ext)

        -- Check if file exists
        local file = io.open(customPath, 'r')
        if file then
            file:close()
            return customPath
        end
    end

    return nil
end

function texture.load_map_texture(map_data)
    local d3d8dev = d3d8.get_device()
    local gcTexture, texture_data, err

    -- Check for custom map if enabled
    if boussole.config.useCustomMaps[1] then
        local customPath = texture.get_custom_map_path(map_data)
        if customPath then
            gcTexture, texture_data, err = texture.load_texture_from_file(customPath, d3d8dev)
            if gcTexture then
                return gcTexture, texture_data, nil
            else
                -- Failed to load custom map, fall back to DAT
                err = string.format('Failed to load custom map, falling back to DAT: %s', err)
            end
        end
    end

    -- Fall back to DAT map
    local datData
    datData, err = map.load_map_dat(map_data.entry)
    if not datData then
        return nil, nil, string.format('Failed to load map DAT: %s', err)
    end

    -- Load texture using texture module
    gcTexture, texture_data, err = texture.load_texture_to_d3d(datData, d3d8dev)

    datData = nil

    if not gcTexture then
        return nil, nil, string.format('Failed to load texture: %s', err)
    end

    collectgarbage('collect')

    return gcTexture, texture_data, nil
end

function texture.load_nomap_texture()
    local d3d8dev = d3d8.get_device()
    local nomap_path = string.format('%saddons\\boussole\\assets\\nomap.png', AshitaCore:GetInstallPath())

    local gcTexture, texture_data, err = texture.load_texture_from_file(nomap_path, d3d8dev)

    if not gcTexture then
        return nil, nil, string.format('Failed to load nomap.png: %s', err)
    end

    collectgarbage('collect')

    return gcTexture, texture_data, nil
end

-- Load texture (map or nomap) and update UI state
-- If map_data is nil, loads nomap texture
function texture.load_and_set(ui_state, map_data, chat_module, addon_name)
    local gcTexture, texture_data, err

    if map_data then
        gcTexture, texture_data, err = texture.load_map_texture(map_data)
    else
        gcTexture, texture_data, err = texture.load_nomap_texture()
    end

    if gcTexture then
        ui_state.texture_id = gcTexture
        ui_state.map_texture = {
            width = texture_data.width,
            height = texture_data.height,
            type = texture_data.type
        }

        -- Restore normalized view state for the new texture size
        ui_state.restore_view_state()
        return true
    else
        if chat_module and addon_name then
            print(chat_module.header(addon_name):append(chat_module.error(err)))
        end
        return false
    end
end

return texture
