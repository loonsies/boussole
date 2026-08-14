local drawing = {}

local d3d = require('d3d8')
local ffi = require('ffi')
local C = ffi.C

ffi.cdef [[
    #pragma pack(1)
    struct VertFormatXYZD {
        float x;
        float y;
        float z;
        unsigned int diffuse;
    };
]]

local vertFormatMask = bit.bor(C.D3DFVF_XYZ, C.D3DFVF_DIFFUSE)
local vertFormat     = ffi.new('struct VertFormatXYZD')
local vertSize       = ffi.sizeof(vertFormat)

-- Pre-allocated reusable buffers
local oldCull        = ffi.new('uint32_t[1]')
local oldShader      = ffi.new('uint32_t[1]')
local oldZWrite      = ffi.new('uint32_t[1]')
local oldAlpha       = ffi.new('uint32_t[1]')
local oldSrcBlend    = ffi.new('uint32_t[1]')
local oldDestBlend   = ffi.new('uint32_t[1]')
local identity       = ffi.new('D3DMATRIX', {
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1
})
local fallbackWorld  = ffi.new('D3DMATRIX', {
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1
})

-- Pre-allocated vertex buffers
local lineVerts      = ffi.new('struct VertFormatXYZD[2]')
local boxVerts       = ffi.new('struct VertFormatXYZD[36]') -- 6 faces * 2 triangles * 3 verts

local function set_vertex(vert, x, y, z, color)
    vert.x = x
    vert.y = z -- swap Y and Z
    vert.z = y
    vert.diffuse = color
end

local function begin_draw_state(d3d8dev, disableDepthWrite)
    local oldWorld = select(2, d3d8dev:GetTransform(C.D3DTS_WORLD))

    if not oldWorld then
        oldWorld = fallbackWorld
    end

    d3d8dev:GetRenderState(C.D3DRS_CULLMODE, oldCull)
    d3d8dev:GetVertexShader(oldShader)
    d3d8dev:GetRenderState(C.D3DRS_ZWRITEENABLE, oldZWrite)
    d3d8dev:GetRenderState(C.D3DRS_ALPHABLENDENABLE, oldAlpha)
    d3d8dev:GetRenderState(C.D3DRS_SRCBLEND, oldSrcBlend)
    d3d8dev:GetRenderState(C.D3DRS_DESTBLEND, oldDestBlend)

    d3d8dev:SetTransform(C.D3DTS_WORLD, identity)
    d3d8dev:SetTexture(0, nil)
    d3d8dev:SetTextureStageState(0, C.D3DTSS_COLOROP, C.D3DTOP_SELECTARG2)
    d3d8dev:SetTextureStageState(0, C.D3DTSS_COLORARG2, C.D3DTA_DIFFUSE)
    d3d8dev:SetTextureStageState(0, C.D3DTSS_ALPHAOP, C.D3DTOP_SELECTARG2)
    d3d8dev:SetTextureStageState(0, C.D3DTSS_ALPHAARG2, C.D3DTA_DIFFUSE)
    d3d8dev:SetRenderState(C.D3DRS_CULLMODE, C.D3DCULL_NONE)
    d3d8dev:SetRenderState(C.D3DRS_ALPHABLENDENABLE, 1)
    d3d8dev:SetRenderState(C.D3DRS_SRCBLEND, C.D3DBLEND_SRCALPHA)
    d3d8dev:SetRenderState(C.D3DRS_DESTBLEND, C.D3DBLEND_INVSRCALPHA)
    d3d8dev:SetRenderState(C.D3DRS_LIGHTING, 0)
    if disableDepthWrite then
        d3d8dev:SetRenderState(C.D3DRS_ZWRITEENABLE, 0)
    end
    d3d8dev:SetVertexShader(vertFormatMask)

    return oldWorld
end

local function end_draw_state(d3d8dev, oldWorld)
    d3d8dev:SetVertexShader(oldShader[1])
    d3d8dev:SetRenderState(C.D3DRS_ALPHABLENDENABLE, oldAlpha[1])
    d3d8dev:SetRenderState(C.D3DRS_SRCBLEND, oldSrcBlend[1])
    d3d8dev:SetRenderState(C.D3DRS_DESTBLEND, oldDestBlend[1])
    d3d8dev:SetRenderState(C.D3DRS_CULLMODE, oldCull[1])
    d3d8dev:SetRenderState(C.D3DRS_ZWRITEENABLE, oldZWrite[1])
    d3d8dev:SetTransform(C.D3DTS_WORLD, oldWorld)
end

function drawing:DrawLine(origin, destination, color)
    local d3d8dev = d3d.get_device()
    if not d3d8dev then return end

    set_vertex(lineVerts[0], origin.X, origin.Y, origin.Z, color)
    set_vertex(lineVerts[1], destination.X, destination.Y, destination.Z, color)

    local oldWorld = begin_draw_state(d3d8dev, false)
    d3d8dev:DrawPrimitiveUP(C.D3DPT_LINELIST, 1, lineVerts, vertSize)
    end_draw_state(d3d8dev, oldWorld)
end

function drawing:DrawBox(minX, minY, minZ, maxX, maxY, maxZ, colors)
    local d3d8dev = d3d.get_device()

    if not d3d8dev then return end

    local cMinY = colors and colors.minY or 0xFFFFFFFF
    local cMaxY = colors and colors.maxY or 0xFFFFFFFF
    local cMinX = colors and colors.minX or 0xFFFFFFFF
    local cMaxX = colors and colors.maxX or 0xFFFFFFFF
    local cMinZ = colors and colors.minZ or 0xFFFFFFFF
    local cMaxZ = colors and colors.maxZ or 0xFFFFFFFF

    local i = 0

    local function v(x, y, z, c)
        set_vertex(boxVerts[i], x, y, z, c)
        i = i + 1
    end

    -- minY face
    v(minX, minY, minZ, cMinY)
    v(maxX, minY, minZ, cMinY)
    v(maxX, minY, maxZ, cMinY)
    v(minX, minY, minZ, cMinY)
    v(maxX, minY, maxZ, cMinY)
    v(minX, minY, maxZ, cMinY)

    -- maxY face
    v(minX, maxY, minZ, cMaxY)
    v(maxX, maxY, maxZ, cMaxY)
    v(maxX, maxY, minZ, cMaxY)
    v(minX, maxY, minZ, cMaxY)
    v(minX, maxY, maxZ, cMaxY)
    v(maxX, maxY, maxZ, cMaxY)

    -- minX face
    v(minX, minY, minZ, cMinX)
    v(minX, minY, maxZ, cMinX)
    v(minX, maxY, maxZ, cMinX)
    v(minX, minY, minZ, cMinX)
    v(minX, maxY, maxZ, cMinX)
    v(minX, maxY, minZ, cMinX)

    -- maxX face
    v(maxX, minY, minZ, cMaxX)
    v(maxX, maxY, minZ, cMaxX)
    v(maxX, maxY, maxZ, cMaxX)
    v(maxX, minY, minZ, cMaxX)
    v(maxX, maxY, maxZ, cMaxX)
    v(maxX, minY, maxZ, cMaxX)

    -- minZ face
    v(minX, minY, minZ, cMinZ)
    v(minX, maxY, minZ, cMinZ)
    v(maxX, maxY, minZ, cMinZ)
    v(minX, minY, minZ, cMinZ)
    v(maxX, maxY, minZ, cMinZ)
    v(maxX, minY, minZ, cMinZ)

    -- maxZ face
    v(minX, minY, maxZ, cMaxZ)
    v(maxX, minY, maxZ, cMaxZ)
    v(maxX, maxY, maxZ, cMaxZ)
    v(minX, minY, maxZ, cMaxZ)
    v(maxX, maxY, maxZ, cMaxZ)
    v(minX, maxY, maxZ, cMaxZ)

    local oldWorld = begin_draw_state(d3d8dev, true)
    d3d8dev:DrawPrimitiveUP(C.D3DPT_TRIANGLELIST, 12, boxVerts, vertSize)
    end_draw_state(d3d8dev, oldWorld)
end

return drawing
