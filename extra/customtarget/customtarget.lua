addon.name    = 'customtarget'
addon.author  = 'Jyouya'
addon.version = '0.6'
addon.desc    = 'Display a custom target cursor over your target'

require('common')

local d3d               = require('d3d8')
local d3d8dev           = d3d.get_device()
local ffi               = require('ffi')
local C                 = ffi.C

-- * Edit this part to match your custom cursor * --
local filepathForCursor = 'edit/cursor.png'
local filepathForCursorSub = 'edit/subcursor.png'
local cursorWidth       = 30 -- Width of the image
local cursorHeight      = 20 -- Height of the image
-- * ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ * --

local cursorRect        = ffi.new('RECT', { 0, 0, cursorWidth, cursorHeight })
local white             = d3d.D3DCOLOR_ARGB(255, 255, 255, 255)
local cursorPos         = ffi.new('D3DXVECTOR2', { 0, 0 })
local cursorPosSub      = ffi.new('D3DXVECTOR2', { 0, 0 })
local cursorScale       = ffi.new('D3DXVECTOR2', { 1.0, 1.0 })

local cursorTex
local cursorTexSub

local _, viewport = d3d8dev:GetViewport()
local width       = viewport.Width
local height      = viewport.Height

local function matrixMultiply(m1, m2)
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
    })
end

local function vec4Transform(v, m)
    return ffi.new('D3DXVECTOR4', {
        m._11 * v.x + m._21 * v.y + m._31 * v.z + m._41 * v.w,
        m._12 * v.x + m._22 * v.y + m._32 * v.z + m._42 * v.w,
        m._13 * v.x + m._23 * v.y + m._33 * v.z + m._43 * v.w,
        m._14 * v.x + m._24 * v.y + m._34 * v.z + m._44 * v.w,
    })
end

local function worldToScreen(x, y, z, view, projection)
    local vplayer = ffi.new('D3DXVECTOR4', { x, y, z, 1 })

    local viewProj = matrixMultiply(view, projection)

    local pCamera = vec4Transform(vplayer, viewProj)

    local rhw = 1 / pCamera.w

    local pNDC = ffi.new('D3DXVECTOR3', { pCamera.x * rhw, pCamera.y * rhw, pCamera.z * rhw })

    local pRaster = ffi.new('D3DXVECTOR2')
    pRaster.x = math.floor((pNDC.x + 1) * 0.5 * width)
    pRaster.y = math.floor((1 - pNDC.y) * 0.5 * height)

    return pRaster.x, pRaster.y, pNDC.z
end

local function getBone(actorPointer, bone)
    local x = ashita.memory.read_float(actorPointer + 0x678)
    local y = ashita.memory.read_float(actorPointer + 0x680)
    local z = ashita.memory.read_float(actorPointer + 0x67C)

    local skeletonBaseAddress = ashita.memory.read_uint32(actorPointer + 0x6B8)

    local skeletonOffsetAddress = ashita.memory.read_uint32(skeletonBaseAddress + 0x0C)

    local skeletonAddress = ashita.memory.read_uint32(skeletonOffsetAddress)

    local boneCount = ashita.memory.read_uint16(skeletonAddress + 0x32)
    -- print(boneCount)

    local bufferPointer = skeletonAddress + 0x30
    local skeletonSize = 0x04
    local boneSize = 0x1E

    local generatorsAddress = bufferPointer + skeletonSize + boneSize * boneCount + 4

    return x + ashita.memory.read_float(generatorsAddress + (bone * 0x1A) + 0x0E + 0x0),
        y + ashita.memory.read_float(generatorsAddress + (bone * 0x1A) + 0x0E + 0x8),
        z + ashita.memory.read_float(generatorsAddress + (bone * 0x1A) + 0x0E + 0x4)
end

local function loadCursorTex(filepath)
    if (not filepath) then
        return nil
    end

    local texture_ptr = ffi.new('IDirect3DTexture8*[1]')
    if (C.D3DXCreateTextureFromFileA(d3d8dev, addon.path .. filepath, texture_ptr) ~= C.S_OK) then
        return nil
    end

    return d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', texture_ptr[0]))
end

local function loadSprite()
    local sprite_ptr = ffi.new('ID3DXSprite*[1]')
    if (C.D3DXCreateSprite(d3d8dev, sprite_ptr) ~= C.S_OK) then
        error('failed to make sprite obj')
    end

    return d3d.gc_safe_release(ffi.cast('ID3DXSprite*', sprite_ptr[0]))
end

local function getPos(targetIndex)
    local x = nil
    local y = nil
    local ndcZ = nil

    -- Save the entity manager for ease of use
    local entity = AshitaCore:GetMemoryManager():GetEntity()

    -- Determine if entity has a model
    local entityType = entity:GetType(targetIndex)

    local renderFlags = entity:GetRenderFlags0(targetIndex)

    local tx, ty, tz
    if (entityType == 3) then -- If target is a door or something similar
        tx = entity:GetLocalPositionX(targetIndex)
        ty = entity:GetLocalPositionY(targetIndex)
        tz = entity:GetLocalPositionZ(targetIndex)
    elseif (renderFlags == 0 and entityType == 0) then
        tx = entity:GetLastPositionX(targetIndex)
        ty = entity:GetLastPositionY(targetIndex)
        tz = entity:GetLastPositionZ(targetIndex)
    else
        -- Get the entity struct for our target
        local targetPointer = entity:GetActorPointer(targetIndex)

        -- Get the coordinates for target nameplate
        tx, ty, tz = getBone(targetPointer, 2)
    end

    -- Get the transformation matrices for the scene
    local _, view = d3d8dev:GetTransform(C.D3DTS_VIEW)
    local _, projection = d3d8dev:GetTransform(C.D3DTS_PROJECTION)

    -- Get screen coordinates for our nameplate
    x, y, ndcZ = worldToScreen(tx, tz, ty, view, projection)

    -- Adjust the coordinates so the cursor is in the right place
    x = x - cursorWidth / 2
    y = y - cursorHeight

    -- Add extra y padding for doors and stuff
    if (entityType == 3) then
        y = y - 8
    end

    return x, y, ndcZ
end

ashita.events.register('load', 'loac_cb', function()
    local sprite = loadSprite()

    ashita.events.register('d3d_present', 'present_cb', function()
        -- Save the target manager for ease of use
        local target = AshitaCore:GetMemoryManager():GetTarget()

        -- Determine if we are currently subtargetting
        local isSubTargetActive = target:GetIsSubTargetActive()

        -- Exit early if we don't have a target
        if (target:GetIsActive(isSubTargetActive) == 0) then
            return
        end

        -- Get the index of your current target or subtarget (if any)
        local targetIndex = target:GetTargetIndex(isSubTargetActive)
        local targetIndexSub = nil
        if (isSubTargetActive == 1) then
            targetIndexSub = target:GetTargetIndex(0)
        end

        -- Get/load the cursor textures
        cursorTex = cursorTex or loadCursorTex(filepathForCursor)
        cursorTexSub = cursorTexSub or loadCursorTex(filepathForCursorSub)

        -- Get target cursor position
        local ndcZ = nil
        cursorPos.x, cursorPos.y, ndcZ = getPos(targetIndex)

        -- Test if target cursor is in the viewing volume
        if (ndcZ >= 0 and ndcZ <= 1) then
            local flags = target:GetSubTargetFlags()

            -- Draw the target cursor
            if (flags == 512 or flags == 18 or flags == 525 and not targetIndexSub) then -- Hack to get items to display a blue target instead of a white one for items, stnpc, and stpc
                sprite:Draw(cursorTexSub, cursorRect, cursorScale, nil, 0.0, cursorPos, white)
            else
                sprite:Draw(cursorTex, cursorRect, cursorScale, nil, 0.0, cursorPos, white)
            end
        end

        if (targetIndexSub) then
		    -- Get subtarget cursor position
            local ndcZSub = nil
            cursorPosSub.x, cursorPosSub.y, ndcZSub = getPos(targetIndexSub)

            -- Pad subtarget
            cursorPosSub.y = cursorPosSub.y - 10

            -- Test if subtarget cursor is in the viewing volume
            if (ndcZSub >= 0 and ndcZSub <= 1) then
                -- Draw the subtarget cursor
                sprite:Draw(cursorTexSub, cursorRect, cursorScale, nil, 0.0, cursorPosSub, white)
            end

        end
    end)
end)
