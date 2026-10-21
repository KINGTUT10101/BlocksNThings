local content = {}

local g3d

-- local validTypes = {
--     solid = true,
--     liquid = true,
--     gas = true,
-- }

-- local function initTextureDefs (textureIds)
--     assert (textureIds ~= nil, "Block textures must be provided!")

--     -- If textureIds is not a table, assume it's a single texture for all faces
--     if type (textureIds) == "string" then
--         return {
--             front = textureIds,
--             back = textureIds,
--             top = textureIds,
--             bottom = textureIds,
--             left = textureIds,
--             right = textureIds,
--         }

--     -- If textures is a table, create a copy of the table and use the front face as a default for any missing faces
--     else
--         assert (textureIds.front ~= nil, "Block textures must include a 'front' texture!")

--         -- Make sure all faces are defined
--         return {
--             front = textureIds.front,
--             back = textureIds.back or textureIds.front,
--             top = textureIds.top or textureIds.front,
--             bottom = textureIds.bottom or textureIds.front,
--             left = textureIds.left or textureIds.front,
--             right = textureIds.right or textureIds.front,
--         }
--     end
-- end

function content:init (config)
    assert (config.g3d ~= nil, "content:init requires a g3d instance")

    g3d = config.g3d
end

function content:newEntity (texture, blockScale, majorAxis)
    majorAxis = majorAxis or "x"

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

    local newEntityModel = g3d.newModel(verts, texture)

    return newEntityModel
end

-- function content:newBlockDef (blockData)
--     local newBlock = {
--         id = blockData.id,
--         name = blockData.name or "Unnamed Block",
--         desc = blockData.desc or "No description provided.",
--         textureIds = initTextureDefs (blockData.textureIds),
--         type = blockData.type,
--     }

--     assert (newBlock.id ~= nil, "Block data is missing required field 'id'")
--     assert (validTypes[newBlock.type] ~= nil, "Block data has invalid type '" .. tostring (newBlock.type) .. "'")

--     return newBlock
-- end

return content