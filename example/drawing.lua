local d3d     = require('d3d8');
local d3d8dev = d3d.get_device()
local ffi     = require('ffi')
local C       = ffi.C
ffi.cdef [[
    #pragma pack(1)
    struct VertFormatFFFFUFF {
        float x;
        float y;
        float z;
        float rhw;
        unsigned int diffuse;
        float u;
        float v;
    };
]]
local width, height;
do
    local _, viewport = d3d8dev:GetViewport();
    width = viewport.Width;
    height = viewport.Height;
end
local texture_ptr = ffi.new('IDirect3DTexture8*[1]');
if (C.D3DXCreateTextureFromFileA(d3d8dev, string.format('%s/assets/qtip.png', addon.path), texture_ptr) == C.S_OK) then
    texture_ptr = d3d.gc_safe_release(ffi.cast('IDirect3DBaseTexture8*', texture_ptr[0]));
end
local vertFormatMask  = bit.bor(C.D3DFVF_XYZRHW, C.D3DFVF_DIFFUSE, C.D3DFVF_TEX1)
local vertFormat      = ffi.new('struct VertFormatFFFFUFF')
local _, vertexBuffer = d3d8dev:CreateVertexBuffer(
    4 * ffi.sizeof(vertFormat),
    C.D3DUSAGE_WRITEONLY,
    vertFormatMask,
    C.D3DPOOL_MANAGED);

local function MatrixMultiply(m1, m2)
    return ffi.new('D3DXMATRIX', {
        --
        m1._11 * m2._11 + m1._12 * m2._21 + m1._13 * m2._31 + m1._14 * m2._41,
        m1._11 * m2._12 + m1._12 * m2._22 + m1._13 * m2._32 + m1._14 * m2._42,
        m1._11 * m2._13 + m1._12 * m2._23 + m1._13 * m2._33 + m1._14 * m2._43,
        m1._11 * m2._14 + m1._12 * m2._24 + m1._13 * m2._34 + m1._14 * m2._44,
        --
        m1._21 * m2._11 + m1._22 * m2._21 + m1._23 * m2._31 + m1._24 * m2._41,
        m1._21 * m2._12 + m1._22 * m2._22 + m1._23 * m2._32 + m1._24 * m2._42,
        m1._21 * m2._13 + m1._22 * m2._23 + m1._23 * m2._33 + m1._24 * m2._43,
        m1._21 * m2._14 + m1._22 * m2._24 + m1._23 * m2._34 + m1._24 * m2._44,
        --
        m1._31 * m2._11 + m1._32 * m2._21 + m1._33 * m2._31 + m1._34 * m2._41,
        m1._31 * m2._12 + m1._32 * m2._22 + m1._33 * m2._32 + m1._34 * m2._42,
        m1._31 * m2._13 + m1._32 * m2._23 + m1._33 * m2._33 + m1._34 * m2._43,
        m1._31 * m2._14 + m1._32 * m2._24 + m1._33 * m2._34 + m1._34 * m2._44,
        --
        m1._41 * m2._11 + m1._42 * m2._21 + m1._43 * m2._31 + m1._44 * m2._41,
        m1._41 * m2._12 + m1._42 * m2._22 + m1._43 * m2._32 + m1._44 * m2._42,
        m1._41 * m2._13 + m1._42 * m2._23 + m1._43 * m2._33 + m1._44 * m2._43,
        m1._41 * m2._14 + m1._42 * m2._24 + m1._43 * m2._34 + m1._44 * m2._44,
    });
end
local function Vec4Transform(v, m)
    return ffi.new('D3DXVECTOR4', {
        m._11 * v.x + m._21 * v.y + m._31 * v.z + m._41 * v.w,
        m._12 * v.x + m._22 * v.y + m._32 * v.z + m._42 * v.w,
        m._13 * v.x + m._23 * v.y + m._33 * v.z + m._43 * v.w,
        m._14 * v.x + m._24 * v.y + m._34 * v.z + m._44 * v.w,
    });
end
local function WorldToScreen(point, viewProj)
    local vPoint = ffi.new('D3DXVECTOR4', { point.X, point.Z, point.Y, 1 });

    local pCamera = Vec4Transform(vPoint, viewProj);

    local rhw = 1 / pCamera.w;

    local pNDC = ffi.new('D3DXVECTOR3', { pCamera.x * rhw, pCamera.y * rhw, pCamera.z * rhw })
    if pCamera.w < 0 then
        pNDC.x = -pNDC.x
        pNDC.y = -pNDC.y
    end

    local pRaster = ffi.new('D3DXVECTOR2');
    pRaster.x = math.floor((pNDC.x + 1) * 0.5 * width);
    pRaster.y = math.floor((1 - pNDC.y) * 0.5 * height);

    return { x = pRaster.x, y = pRaster.y, z = pNDC.z }
end

local function DrawLine(self, origin, destination, color)
    local _, view = d3d8dev:GetTransform(C.D3DTS_VIEW)
    local _, projection = d3d8dev:GetTransform(C.D3DTS_PROJECTION)
    local viewProj = MatrixMultiply(view, projection);
    local p1 = WorldToScreen(origin, viewProj);
    local p2 = WorldToScreen(destination, viewProj);

    if not p1 or not p2 then
        return;
    end

    local lineWidth = 10;
    local dx = p2.y - p1.y
    local dy = p1.x - p2.x
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then return end

    dx = dx / len * lineWidth
    dy = dy / len * lineWidth

    local vertices = {
        { p1.x + dx, p1.y + dy, p1.z, 1, color, 0, 0 },
        { p1.x - dx, p1.y - dy, p1.z, 1, color, 0, 1 },
        { p2.x + dx, p2.y + dy, p2.z, 1, color, 1, 0 },
        { p2.x - dx, p2.y - dy, p2.z, 1, color, 1, 1 },
    };

    local _, ptr = vertexBuffer:Lock(0, 0, 0)
    local vdata = ffi.cast('struct VertFormatFFFFUFF*', ptr)
    for i = 0, 3 do
        vdata[i] = ffi.new('struct VertFormatFFFFUFF', vertices[i + 1])
    end
    vertexBuffer:Unlock()

    d3d8dev:SetStreamSource(0, vertexBuffer, ffi.sizeof(vertFormat))
    d3d8dev:SetTexture(0, texture_ptr)

    d3d8dev:SetTextureStageState(0, C.D3DTSS_COLOROP, C.D3DTOP_MODULATE)
    d3d8dev:SetTextureStageState(0, C.D3DTSS_COLORARG1, C.D3DTA_TEXTURE)
    d3d8dev:SetTextureStageState(0, C.D3DTSS_COLORARG2, C.D3DTA_DIFFUSE)
    d3d8dev:SetTextureStageState(0, C.D3DTSS_ALPHAOP, C.D3DTOP_SELECTARG1)
    d3d8dev:SetTextureStageState(0, C.D3DTSS_ALPHAARG1, C.D3DTA_TEXTURE)

    d3d8dev:SetRenderState(C.D3DRS_ZENABLE, 0)
    d3d8dev:SetRenderState(C.D3DRS_ALPHABLENDENABLE, 1)
    d3d8dev:SetRenderState(C.D3DRS_SRCBLEND, C.D3DBLEND_SRCALPHA)
    d3d8dev:SetRenderState(C.D3DRS_DESTBLEND, C.D3DBLEND_INVSRCALPHA)

    d3d8dev:SetVertexShader(vertFormatMask)
    d3d8dev:DrawPrimitive(C.D3DPT_TRIANGLESTRIP, 0, 2)
end

local exports = {
    DrawLine = DrawLine,
};
return exports;
