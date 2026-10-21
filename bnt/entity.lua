local mapToScale = require ("libs.mapToScale")
local g3d = require ("libs.g3d")
local lume = require ("libs.lume")
local ffi = require ("ffi")

local Entity = {}

function Entity:new (texture, blockScale, majorAxis)
    majorAxis = majorAxis or "x"

    local newEntity = {
        model = nil,
        width = 0,
        height = 0,
    }

    local tw, th = texture:getDimensions ()
    local fw, fh

    if majorAxis == "x" then
        fw = blockScale
        fh = th / tw * blockScale

    elseif majorAxis == "y" then
        fw = tw / th * blockScale
        fh = blockScale
    else
        error ("Invalid majorAxis value: " .. tostring (majorAxis))
    end

    -- Build a vertical quad with bottom-center anchor
    local hw = fw / 2
    local h0 = 0
    local h1 = fh

    local verts = {
        { -hw, h0, 0, 0, 1, 0,0,1, 1,1,1,1 }, -- bottom-left
        {  hw, h0, 0, 1, 1, 0,0,1, 1,1,1,1 }, -- bottom-right
        {  hw, h1, 0, 1, 0, 0,0,1, 1,1,1,1 }, -- top-right

        { -hw, h0, 0, 0, 1, 0,0,1, 1,1,1,1 }, -- bottom-left
        {  hw, h1, 0, 1, 0, 0,0,1, 1,1,1,1 }, -- top-right
        { -hw, h1, 0, 0, 0, 0,0,1, 1,1,1,1 }, -- top-left
    }

    newEntity.width = fw
    newEntity.height = fh
    newEntity.model = g3d.newModel(verts, texture)

    -- Add the methods
    for k, v in pairs (Entity) do
        if k ~= "new" then
            newEntity[k] = v
        end
    end

    return newEntity
end

-- Assume that x, y represents the bottom-center of the texture
function Entity:draw (x, y, depth)
    -- Place the quad so (x,y) is its bottom-center
    self.model:setTransform({x, y, depth or 0}, nil, nil)
    self.model:draw()
end

-- Get the in-world dimensions of the entity
function Entity:getDimensions ()
    return self.width, self.height
end

function Entity:getWidth ()
    return self.width
end

function Entity:getHeight ()
    return self.height
end

return Entity