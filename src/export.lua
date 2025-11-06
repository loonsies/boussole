local ffi = require('ffi')

local export = {}

ffi.cdef [[
    int __stdcall CreateDirectoryA(const char* lpPathName, void* lpSecurityAttributes);
    uint32_t __stdcall GetFileAttributesA(const char* lpFileName);

    enum {
        D3DX_FILTER_NONE = 1
    };
]]

local C = ffi.C
local FILE_ATTRIBUTE_DIRECTORY = 0x10
local INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF

-- Get the custom map folder path
function export.get_custom_folder()
    return string.format('%sconfig\\addons\\%s\\custom\\',
        AshitaCore:GetInstallPath(),
        addon.name)
end

-- Create directory recursively if it doesn't exist
function export.ensure_directory_exists(path)
    path = path:gsub('\\$', '')

    -- Check if directory already exists
    local attrs = C.GetFileAttributesA(path)
    if attrs ~= INVALID_FILE_ATTRIBUTES and bit.band(attrs, FILE_ATTRIBUTE_DIRECTORY) ~= 0 then
        return true
    end

    -- Get parent directory
    local parent = path:match('(.+)\\[^\\]+$')
    if parent then
        -- Recursively create parent
        export.ensure_directory_exists(parent)
    end

    C.CreateDirectoryA(path, nil)
    return true
end

-- Export the current map texture to BMP
function export.save_map(texture_id, map_data)
    if not texture_id then
        return false, 'No texture loaded'
    end

    if not map_data or not map_data.entry then
        return false, 'No map data available'
    end

    local entry = map_data.entry
    local zoneId = entry.ZoneId
    local floorId = entry.FloorId

    local folder = export.get_custom_folder()
    export.ensure_directory_exists(folder)

    local filename = string.format('%d_%d.bmp', zoneId, floorId)
    local filepath = folder .. filename

    filepath = filepath:gsub('\\', '/')

    local d3d8 = require('d3d8')
    local d3d8dev = d3d8.get_device()
    if not d3d8dev then
        return false, 'Failed to get D3D device'
    end

    local srcTexture = ffi.cast('IDirect3DTexture8*', texture_id)
    local hr, desc = srcTexture:GetLevelDesc(0)
    if hr ~= C.S_OK then
        return false, string.format('GetLevelDesc failed: 0x%08X', hr)
    end

    local baseTexture = ffi.cast('IDirect3DBaseTexture8*', srcTexture)
    hr = C.D3DXSaveTextureToFileA(filepath, C.D3DXIFF_BMP, baseTexture, nil)

    if hr ~= C.S_OK then
        return false, string.format('Failed to save texture: 0x%08X (path: %s)', hr, filepath)
    end

    return true, filepath
end

return export
