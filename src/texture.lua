local ffi = require('ffi')
local d3d8 = require('d3d8')

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

-- Parse DXT texel block (DxtParser.ReadTexelBlock)
local function read_dxt_texel_block(data, offset, imageType)
    local texelOffset = offset
    local alphaBlock_low, alphaBlock_high = 0, 0

    -- Read alpha block for DXT2-5
    if imageType >= IMAGE_TYPE.DXT2 and imageType <= IMAGE_TYPE.DXT5 then
        alphaBlock_low, alphaBlock_high = read_u64(data, texelOffset)
        texelOffset = texelOffset + 8
    end

    -- Read color data
    local c0 = read_u16(data, texelOffset)
    local c1 = read_u16(data, texelOffset + 2)
    texelOffset = texelOffset + 4

    local colors = {}
    colors[0] = { decode_rgb565(c0) }
    colors[1] = { decode_rgb565(c1) }

    -- Calculate interpolated colors
    if c0 > c1 or imageType ~= IMAGE_TYPE.DXT1 then
        -- Opaque, 4-color
        colors[2] = {
            math.floor((2 * colors[0][1] + colors[1][1] + 1) / 3),
            math.floor((2 * colors[0][2] + colors[1][2] + 1) / 3),
            math.floor((2 * colors[0][3] + colors[1][3] + 1) / 3)
        }
        colors[3] = {
            math.floor((2 * colors[1][1] + colors[0][1] + 1) / 3),
            math.floor((2 * colors[1][2] + colors[0][2] + 1) / 3),
            math.floor((2 * colors[1][3] + colors[0][3] + 1) / 3)
        }
    else
        -- 1-bit alpha, 3-color
        colors[2] = {
            math.floor((colors[0][1] + colors[1][1]) / 2),
            math.floor((colors[0][2] + colors[1][2]) / 2),
            math.floor((colors[0][3] + colors[1][3]) / 2)
        }
        colors[3] = { 0, 0, 0 } -- Transparent
    end

    -- Read compressed color indices
    local compressedColor = read_u32(data, texelOffset)
    texelOffset = texelOffset + 4

    -- Decode 16 pixels
    local decodedColors = {}
    for i = 0, 15 do
        local colorIndex = bit.band(compressedColor, 0x3)
        compressedColor = bit.rshift(compressedColor, 2)

        local r, g, b = colors[colorIndex][1], colors[colorIndex][2], colors[colorIndex][3]
        local a = 255

        -- Handle alpha for DXT2-5
        if imageType >= IMAGE_TYPE.DXT2 and imageType <= IMAGE_TYPE.DXT5 then
            if imageType == IMAGE_TYPE.DXT2 or imageType == IMAGE_TYPE.DXT3 then
                -- 4-bit alpha
                local alpha_shift = i * 4
                local alpha_val
                if alpha_shift < 32 then
                    alpha_val = bit.band(bit.rshift(alphaBlock_low, alpha_shift), 0xF)
                else
                    alpha_val = bit.band(bit.rshift(alphaBlock_high, alpha_shift - 32), 0xF)
                end
                a = (alpha_val >= 8) and 0xFF or (alpha_val * 32)
            else
                -- Interpolated alpha (DXT4/DXT5)
                local alphas = {}
                alphas[0] = bit.band(alphaBlock_low, 0xFF)
                alphas[1] = bit.band(bit.rshift(alphaBlock_low, 8), 0xFF)

                if alphas[0] > alphas[1] then
                    alphas[2] = math.floor((alphas[0] * 6 + alphas[1] * 1 + 3) / 7)
                    alphas[3] = math.floor((alphas[0] * 5 + alphas[1] * 2 + 3) / 7)
                    alphas[4] = math.floor((alphas[0] * 4 + alphas[1] * 3 + 3) / 7)
                    alphas[5] = math.floor((alphas[0] * 3 + alphas[1] * 4 + 3) / 7)
                    alphas[6] = math.floor((alphas[0] * 2 + alphas[1] * 5 + 3) / 7)
                    alphas[7] = math.floor((alphas[0] * 1 + alphas[1] * 6 + 3) / 7)
                else
                    alphas[2] = math.floor((alphas[0] * 4 + alphas[1] * 1 + 2) / 5)
                    alphas[3] = math.floor((alphas[0] * 3 + alphas[1] * 2 + 2) / 5)
                    alphas[4] = math.floor((alphas[0] * 2 + alphas[1] * 3 + 2) / 5)
                    alphas[5] = math.floor((alphas[0] * 1 + alphas[1] * 4 + 2) / 5)
                    alphas[6] = 0
                    alphas[7] = 255
                end

                -- Extract 48-bit alpha matrix (bits 16-63 of alphaBlock)
                local alphaMatrix_low = bit.rshift(alphaBlock_low, 16)
                local alphaMatrix_high = alphaBlock_high

                -- Get 3-bit index for this pixel
                local bitOffset = i * 3
                local alphaIndex
                if bitOffset < 16 then
                    alphaIndex = bit.band(bit.rshift(alphaMatrix_low, bitOffset), 0x7)
                elseif bitOffset < 32 then
                    -- Spans alphaMatrix_low high bits
                    alphaIndex = bit.band(bit.rshift(alphaMatrix_low, bitOffset), 0x7)
                else
                    -- In alphaMatrix_high
                    alphaIndex = bit.band(bit.rshift(alphaMatrix_high, bitOffset - 32), 0x7)
                end

                a = alphas[alphaIndex]
            end
        end

        decodedColors[i] = { r = r, g = g, b = b, a = a }
    end

    return decodedColors, texelOffset
end

-- Parse DXT compressed image (DxtParser.Parse)
function texture.parse_dxt(data, header, dataOffset, ignoreAlpha)
    ignoreAlpha = ignoreAlpha or false

    local pixels = {}
    local texelBlockCount = header.width * header.height / 16 -- 4x4 blocks
    local offset = dataOffset

    for texel = 0, texelBlockCount - 1 do
        local texelBlock, newOffset = read_dxt_texel_block(data, offset, header.type)
        offset = newOffset

        -- Calculate pixel position for this 4x4 block
        local pixelOffsetX = 4 * (texel % (header.width / 4))
        local pixelOffsetY = 4 * math.floor(texel / (header.width / 4))

        -- Write 4x4 block to output
        for y = 0, 3 do
            for x = 0, 3 do
                local lookup = x + 4 * y
                local color = texelBlock[lookup]
                local destX = pixelOffsetX + x
                local destY = pixelOffsetY + y
                local destIndex = (destY * header.width + destX) * 4

                pixels[destIndex + 1] = color.r
                pixels[destIndex + 2] = color.g
                pixels[destIndex + 3] = color.b
                pixels[destIndex + 4] = ignoreAlpha and 255 or color.a
            end
        end
    end

    return pixels
end

-- Parse bitmap image (BitmapParser.Parse)
function texture.parse_bitmap(data, header, dataOffset, ignoreAlpha)
    ignoreAlpha = ignoreAlpha or false

    local pixels = {}
    local palette = nil
    local offset = dataOffset

    -- Read palette for 8-bit images
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
        -- Read palette indices
        for pixelIdx = 0, pixelCount - 1 do
            local paletteIdx = read_u8(data, offset)
            offset = offset + 1

            local color = palette[paletteIdx]
            if color then
                -- Flip Y coordinate (bitmaps are stored upside down)
                local x = pixelIdx % header.width
                local y = math.floor(pixelIdx / header.width)
                local flippedY = header.height - 1 - y
                local destIdx = (flippedY * header.width + x) * 4

                pixels[destIdx + 1] = color.r
                pixels[destIdx + 2] = color.g
                pixels[destIdx + 3] = color.b
                pixels[destIdx + 4] = ignoreAlpha and 255 or color.a
            end
        end
    else
        -- Read direct color
        for pixelIdx = 0, pixelCount - 1 do
            local r, g, b, a, bytesRead = read_color(data, offset, header.bitCount)
            offset = offset + bytesRead

            -- Flip Y coordinate (bitmaps are stored upside down)
            local x = pixelIdx % header.width
            local y = math.floor(pixelIdx / header.width)
            local flippedY = header.height - 1 - y
            local destIdx = (flippedY * header.width + x) * 4

            pixels[destIdx + 1] = r
            pixels[destIdx + 2] = g
            pixels[destIdx + 3] = b
            pixels[destIdx + 4] = ignoreAlpha and 255 or a
        end
    end

    return pixels
end

-- Main parse function (ImageParser.Parse)
function texture.parse(data, ignoreAlpha)
    ignoreAlpha = ignoreAlpha or false

    -- Read flag at 0x30
    local flag = read_u8(data, 0x30)

    -- Read ImageHeader at 0x41
    local header, err = texture.parse_image_header(data, 0x41)
    if not header then
        return nil, err
    end

    local pixels
    local dataOffset = 0x41 + ffi.sizeof('ImageHeader')

    -- Check image type and parse accordingly
    if header.type >= IMAGE_TYPE.DXT1 and header.type <= IMAGE_TYPE.DXT5 then
        -- DXT compressed - skip 8 unknown bytes
        dataOffset = dataOffset + 8
        pixels = texture.parse_dxt(data, header, dataOffset, ignoreAlpha)
    elseif header.type == IMAGE_TYPE.BITMAP then
        pixels = texture.parse_bitmap(data, header, dataOffset, ignoreAlpha)
    else
        return nil, string.format('Unsupported image type: %s (0x%08X)', header.typeName, header.type)
    end

    return {
        width = header.width,
        height = header.height,
        type = header.typeName,
        pixels = pixels,
    }
end

-- Load texture from DAT data and create D3D8 texture
function texture.load_texture_to_d3d(datData, d3d8dev)
    local d3d8 = require('d3d8')
    local S_OK = 0

    -- Read header to get format and dimensions
    local header, err = texture.parse_image_header(datData, 0x41)
    if not header then
        return nil, nil, err
    end

    -- Validate dimensions
    if header.width <= 0 or header.height <= 0 then
        return nil, nil, 'Invalid texture dimensions parsed from DAT'
    end

    local d3dFormat
    local compressedDataOffset = 0x41 + ffi.sizeof('ImageHeader') + 8 -- Header + 8 unknown bytes

    if header.type == IMAGE_TYPE.DXT1 then
        d3dFormat = ffi.C.D3DFMT_DXT1
    elseif header.type == IMAGE_TYPE.DXT2 then
        d3dFormat = ffi.C.D3DFMT_DXT2
    elseif header.type == IMAGE_TYPE.DXT3 then
        d3dFormat = ffi.C.D3DFMT_DXT3
    elseif header.type == IMAGE_TYPE.DXT4 then
        d3dFormat = ffi.C.D3DFMT_DXT4
    elseif header.type == IMAGE_TYPE.DXT5 then
        d3dFormat = ffi.C.D3DFMT_DXT5
    elseif header.type == IMAGE_TYPE.BITMAP then
        -- For bitmaps, we need to decompress
        local texture_data, parseErr = texture.parse(datData, false)
        if not texture_data then
            return nil, nil, parseErr
        end
        return texture.load_uncompressed_texture(d3d8dev, texture_data)
    else
        return nil, nil, string.format('Unsupported image type: %s (0x%08X)', header.typeName, header.type)
    end

    -- Create DirectX texture with compressed format
    local result, dx_texture = d3d8dev:CreateTexture(
        header.width,
        header.height,
        1, -- mipLevels
        0, -- usage
        d3dFormat,
        ffi.C.D3DPOOL_MANAGED
    )

    if result ~= S_OK or not dx_texture then
        return nil, nil, string.format('Failed to create texture: 0x%08X', result)
    end

    -- Lock the texture to write compressed data
    local lockResult, lockedRect = dx_texture:LockRect(0, nil, 0)

    if lockResult ~= S_OK or not lockedRect then
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

    -- Copy compressed data directly from DAT to texture
    local src = ffi.cast('const uint8_t*', ffi.cast('const char*', datData)) + compressedDataOffset
    local dest = ffi.cast('uint8_t*', lockedRect.pBits)
    ffi.copy(dest, src, compressedSize)

    -- Unlock the texture
    dx_texture:UnlockRect(0)

    local gcTexture = d3d8.gc_safe_release(ffi.cast('IDirect3DBaseTexture8*', dx_texture))

    local result_data = {
        width = header.width,
        height = header.height,
        type = header.typeName
    }

    return gcTexture, result_data, nil
end

-- Helper function for uncompressed textures (bitmap format)
function texture.load_uncompressed_texture(d3d8dev, texture_data)
    local S_OK = 0

    local result, dx_texture = d3d8dev:CreateTexture(
        texture_data.width,
        texture_data.height,
        1,
        0,
        ffi.C.D3DFMT_A8R8G8B8,
        ffi.C.D3DPOOL_MANAGED
    )

    if result ~= S_OK or not dx_texture then
        return nil, nil, string.format('Failed to create texture: 0x%08X', result)
    end

    local lockResult, lockedRect = dx_texture:LockRect(0, nil, 0)
    if lockResult ~= S_OK or not lockedRect then
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

    for y = 0, texture_data.height - 1 do
        local rowOffset = y * pitch
        for x = 0, texture_data.width - 1 do
            local pixelIndex = (y * texture_data.width + x) * 4
            local r = texture_data.pixels[pixelIndex + 1]
            local g = texture_data.pixels[pixelIndex + 2]
            local b = texture_data.pixels[pixelIndex + 3]
            local a = texture_data.pixels[pixelIndex + 4]

            if not r or not g or not b or not a then
                dx_texture:UnlockRect(0)
                dx_texture:Release()
                return nil, nil, string.format('Incomplete pixel data at (%d, %d)', x, y)
            end

            local offset = rowOffset + x * 4
            dest[offset + 0] = b
            dest[offset + 1] = g
            dest[offset + 2] = r
            dest[offset + 3] = a
        end
    end

    dx_texture:UnlockRect(0)

    local gcTexture = d3d8.gc_safe_release(ffi.cast('IDirect3DBaseTexture8*', dx_texture))

    local result = {
        width = texture_data.width,
        height = texture_data.height,
        type = texture_data.type
    }

    -- Clear pixel data
    texture_data.pixels = nil
    texture_data = nil

    return gcTexture, result, nil
end

return texture
