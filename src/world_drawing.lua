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

local d3d8dev = d3d.get_device()
if not d3d8dev then
    return drawing
end

local vertFormatMask = bit.bor(C.D3DFVF_XYZ, C.D3DFVF_DIFFUSE)
local vertFormat = ffi.new('struct VertFormatXYZD')

local function begin_draw(options)
    local opts = options or {}
    local oldWorld = select(2, d3d8dev:GetTransform(C.D3DTS_WORLD))
    if not oldWorld then
        oldWorld = ffi.new('D3DMATRIX', {
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1
        })
    end

    local oldCull = ffi.new('uint32_t[1]')
    d3d8dev:GetRenderState(C.D3DRS_CULLMODE, oldCull)

    local oldShader = ffi.new('uint32_t[1]')
    d3d8dev:GetVertexShader(oldShader)

    local oldZWrite = ffi.new('uint32_t[1]')
    d3d8dev:GetRenderState(C.D3DRS_ZWRITEENABLE, oldZWrite)

    local oldAlpha = ffi.new('uint32_t[1]')
    d3d8dev:GetRenderState(C.D3DRS_ALPHABLENDENABLE, oldAlpha)

    local oldSrcBlend = ffi.new('uint32_t[1]')
    d3d8dev:GetRenderState(C.D3DRS_SRCBLEND, oldSrcBlend)

    local oldDestBlend = ffi.new('uint32_t[1]')
    d3d8dev:GetRenderState(C.D3DRS_DESTBLEND, oldDestBlend)

    local identity = ffi.new('D3DMATRIX', {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    })

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
    if opts.disableDepthWrite then
        d3d8dev:SetRenderState(C.D3DRS_ZWRITEENABLE, 0)
    end
    d3d8dev:SetVertexShader(vertFormatMask)

    return function ()
        d3d8dev:SetVertexShader(oldShader[1])
        d3d8dev:SetRenderState(C.D3DRS_ALPHABLENDENABLE, oldAlpha[1])
        d3d8dev:SetRenderState(C.D3DRS_SRCBLEND, oldSrcBlend[1])
        d3d8dev:SetRenderState(C.D3DRS_DESTBLEND, oldDestBlend[1])
        d3d8dev:SetRenderState(C.D3DRS_CULLMODE, oldCull[1])
        d3d8dev:SetRenderState(C.D3DRS_ZWRITEENABLE, oldZWrite[1])
        d3d8dev:SetTransform(C.D3DTS_WORLD, oldWorld)
    end
end

local function make_vertex(x, y, z, color)
    return { x, z, y, color }
end

function drawing.DrawLine(self, origin, destination, color)
    local vertices = ffi.new('struct VertFormatXYZD[2]', {
        make_vertex(origin.X, origin.Y, origin.Z, color),
        make_vertex(destination.X, destination.Y, destination.Z, color)
    })

    local restore = begin_draw()
    d3d8dev:DrawPrimitiveUP(C.D3DPT_LINELIST, 1, vertices, ffi.sizeof(vertFormat))
    restore()
end

function drawing.DrawBox(self, minX, minY, minZ, maxX, maxY, maxZ, colors)
    local cMinY = colors and colors.minY or 0xFFFFFFFF
    local cMaxY = colors and colors.maxY or 0xFFFFFFFF
    local cMinX = colors and colors.minX or 0xFFFFFFFF
    local cMaxX = colors and colors.maxX or 0xFFFFFFFF
    local cMinZ = colors and colors.minZ or 0xFFFFFFFF
    local cMaxZ = colors and colors.maxZ or 0xFFFFFFFF

    local p000 = { minX, minY, minZ }
    local p100 = { maxX, minY, minZ }
    local p110 = { maxX, maxY, minZ }
    local p010 = { minX, maxY, minZ }
    local p001 = { minX, minY, maxZ }
    local p101 = { maxX, minY, maxZ }
    local p111 = { maxX, maxY, maxZ }
    local p011 = { minX, maxY, maxZ }

    local verts = {
        -- minY face
        make_vertex(p000[1], p000[2], p000[3], cMinY),
        make_vertex(p100[1], p100[2], p100[3], cMinY),
        make_vertex(p101[1], p101[2], p101[3], cMinY),
        make_vertex(p000[1], p000[2], p000[3], cMinY),
        make_vertex(p101[1], p101[2], p101[3], cMinY),
        make_vertex(p001[1], p001[2], p001[3], cMinY),

        -- maxY face
        make_vertex(p010[1], p010[2], p010[3], cMaxY),
        make_vertex(p111[1], p111[2], p111[3], cMaxY),
        make_vertex(p110[1], p110[2], p110[3], cMaxY),
        make_vertex(p010[1], p010[2], p010[3], cMaxY),
        make_vertex(p011[1], p011[2], p011[3], cMaxY),
        make_vertex(p111[1], p111[2], p111[3], cMaxY),

        -- minX face
        make_vertex(p000[1], p000[2], p000[3], cMinX),
        make_vertex(p001[1], p001[2], p001[3], cMinX),
        make_vertex(p011[1], p011[2], p011[3], cMinX),
        make_vertex(p000[1], p000[2], p000[3], cMinX),
        make_vertex(p011[1], p011[2], p011[3], cMinX),
        make_vertex(p010[1], p010[2], p010[3], cMinX),

        -- maxX face
        make_vertex(p100[1], p100[2], p100[3], cMaxX),
        make_vertex(p110[1], p110[2], p110[3], cMaxX),
        make_vertex(p111[1], p111[2], p111[3], cMaxX),
        make_vertex(p100[1], p100[2], p100[3], cMaxX),
        make_vertex(p111[1], p111[2], p111[3], cMaxX),
        make_vertex(p101[1], p101[2], p101[3], cMaxX),

        -- minZ face
        make_vertex(p000[1], p000[2], p000[3], cMinZ),
        make_vertex(p010[1], p010[2], p010[3], cMinZ),
        make_vertex(p110[1], p110[2], p110[3], cMinZ),
        make_vertex(p000[1], p000[2], p000[3], cMinZ),
        make_vertex(p110[1], p110[2], p110[3], cMinZ),
        make_vertex(p100[1], p100[2], p100[3], cMinZ),

        -- maxZ face
        make_vertex(p001[1], p001[2], p001[3], cMaxZ),
        make_vertex(p101[1], p101[2], p101[3], cMaxZ),
        make_vertex(p111[1], p111[2], p111[3], cMaxZ),
        make_vertex(p001[1], p001[2], p001[3], cMaxZ),
        make_vertex(p111[1], p111[2], p111[3], cMaxZ),
        make_vertex(p011[1], p011[2], p011[3], cMaxZ)
    }

    local vertices = ffi.new('struct VertFormatXYZD[?]', #verts)
    for i = 1, #verts do
        vertices[i - 1] = ffi.new('struct VertFormatXYZD', verts[i])
    end

    local restore = begin_draw({ disableDepthWrite = true })
    d3d8dev:DrawPrimitiveUP(C.D3DPT_TRIANGLELIST, #verts / 3, vertices, ffi.sizeof(vertFormat))
    restore()
end

return drawing
