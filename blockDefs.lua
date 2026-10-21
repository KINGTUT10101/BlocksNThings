local function initTextureIds (textureIds)
    assert (textureIds ~= nil, "Block textures must be provided!")

    -- If textureIds is not a table, assume it's a single texture for all faces
    if type (textureIds) == "string" then
        return {
            front = textureIds,
            back = textureIds,
            top = textureIds,
            bottom = textureIds,
            left = textureIds,
            right = textureIds,
        }

    -- If textures is a table, create a copy of the table and use the front face as a default for any missing faces
    else
        assert (textureIds.front ~= nil, "Block textures must include a 'front' texture!")

        -- Make sure all faces are defined
        return {
            front = textureIds.front,
            back = textureIds.back or textureIds.front,
            top = textureIds.top or textureIds.front,
            bottom = textureIds.bottom or textureIds.front,
            left = textureIds.left or textureIds.front,
            right = textureIds.right or textureIds.front,
        }
    end
end

local blockDefs = {
    air = {
        id = "air",
        name = "Air",
        desc = "An empty space.",
        textureIds = initTextureIds ("blank"),
        type = "gas",
    },
    basic = {
        id = "basic",
        name = "Basic Block",
        desc = "A basic block for testing.",
        textureIds = initTextureIds ("basicBlock"),
        type = "solid",
    },
}

return blockDefs