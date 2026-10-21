local libPath = (...):match("(.+)%.[^%.]+$") .. "."

local ffi = require ("ffi")
local lume = require (libPath .. "libs.lume")
local Auto2DArray = require (libPath .. "libs.Auto2DArray")
local mapToScale = require (libPath .. "libs.mapToScale")
local cubeData = require (libPath .. "mapDefs") -- Defines the c data structures used in the map data and returns the cubeData structure

local UINT8_PTR_TYPEOF = ffi.typeof('uint8_t*')
local g3d
local tweenFuncs
local lightingShader -- Load using g3d's built-in vertex shader + the custom frag shader
local blockDefs
local blockAtlas

-- Local/private functions are defined here so they can be used freely throughout the methods if need be
local vertexAO, calcVertexAO, addFace, getTilesInExpoRadius,
    calcLightColor, updateLighting, writeLightMapTargets,
    placeSkySource, removeSkySource, calcSkyExposure, updateSkyExposure,
    canReceiveExposure, neighborTileOffsets, updateExposureAtAndNeighbors

-- TODO: Use cdata for as many things as possible, especially for the grid
local mapMan = {
    grid = {}, -- Holds tables of values including block id and light level
    cgrid = {}, -- Holds info about each chunk
    size = {
        w = 0,
        h = 0,
        d = 3,
        cw = 50,
        ch = 50,
    }, -- The size of the map in blocks
    maxLightLevel = 15,
    maxExposure = 5,
    dayLength = 120, -- Length of a full day in seconds
    timeOfDay = 0, -- Current time of day from 0.0-1.0
    skyColorTimeline = {
        {
            color = {1.0,  0.95, 0.8},
            timestamp = 0.0,
            interFunc = "linear",
        },
        {
            color = {1.0,  0.95, 0.8},
            timestamp = 1.0,
            interFunc = "linear",
        },
    },
    debug = {
        
    },

    gfx = {
        aoMulti = 1,
        smoothLighting = true,
        sideShading = true,
        minBrightness = 0.0,
        brightnessMulti = 1.0,
    },
}

function mapMan:init (config)
    assert (config ~= nil and type(config) == "table", "mapMan:init requires a config table")
    assert (config.g3d ~= nil, "mapMan:init requires a g3d instance")
    assert (config.tweenFuncs ~= nil, "mapMan:init requires a tweenFuncs instance")
    assert (config.blockAtlas ~= nil, "mapMan:init requires a blockAtlas (RTA) instance")
    assert (type (config.blockDefs) == "table", "mapMan:init requires a blockDefs instance")
    assert (config.blockDefs.air ~= nil, "mapMan:init requires a blockDefs.air definition")

    g3d = config.g3d
    tweenFuncs = config.tweenFuncs
    blockAtlas = config.blockAtlas
    blockDefs = config.blockDefs

    self.maxLightLevel = config.maxLightLevel or self.maxLightLevel
    self.maxExposure = config.maxExposure or self.maxExposure
    self.dayLength = config.dayLength or self.dayLength
    self.size.cw = config.chunkWidth or self.size.cw
    self.size.ch = config.chunkHeight or self.size.ch

    lightingShader = love.graphics.newShader(g3d.shaderpath, libPath:gsub("%.", "/") .. "block.frag")
end

function mapMan:resetMap (mapW, mapH, mapD)
    local grid = {}
    local cgrid = {}
    self.grid = grid
    self.cgrid = cgrid
    self.size.w = mapW
    self.size.h = mapH
    self.size.d = mapD

    -- Initialize the tiles
    for i = 1, mapW do
        local firstPart = {}
        grid[i] = firstPart

        for j = 1, mapH do
            local newGridItem = {
                dirty = false, -- Indicates whether the tile's lighting needs to be recalculated
                lights = {},
                layers = {},
                exposure = self.maxExposure,
                expoClaims = getTilesInExpoRadius (j),
            }
            firstPart[j] = newGridItem

            for k = 1, self.size.d do
                newGridItem.layers[k] = {
                    def = blockDefs.air,
                    activeFaces = nil,
                }
            end
        end
    end

    -- Initialize the chunks
    for i = 1, math.ceil (mapW / self.size.cw) do
        local firstPart = {}
        cgrid[i] = firstPart

        for j = 1, math.ceil (mapH / self.size.ch) do
            -- The light map is padded with a 1px border on every side (a texel "apron").
            -- That border holds a copy of the neighboring chunk's nearest edge/corner pixels,
            -- so bilinear sampling near a chunk boundary blends across chunks instead of
            -- clamping to this chunk's own edge -- see calcLightColor / writeLightMapTargets.
            local lightImageData = love.image.newImageData (self.size.cw + 2, self.size.ch + 2)
            local imageDataPtr = UINT8_PTR_TYPEOF(lightImageData:getFFIPointer())

            -- Set all pixels in the imagedata to {0, 0, 0, 1}
            local pixelIndex = 0
            for x = 0, self.size.cw + 1 do
                for y = 0, self.size.ch + 1 do
                    local a = 255

                    -- Ensure that the borders have no exposure
                    if x == 0 or x == self.size.cw + 1 or y == 0 or y == self.size.ch + 1 then
                        a = 0
                    end


                    imageDataPtr[pixelIndex + 0] = 0 -- R
                    imageDataPtr[pixelIndex + 1] = 0 -- G
                    imageDataPtr[pixelIndex + 2] = 0 -- B
                    imageDataPtr[pixelIndex + 3] = a -- A
                    pixelIndex = pixelIndex + 4
                end
            end

            local lightMap = love.graphics.newImage (lightImageData)
            lightMap:setFilter("linear", "linear")
            lightMap:setWrap("clamp", "clamp")


            local newChunk = {
                dirty = true, -- needs a full remesh (geometry + texture upload)
                lightMapDirty = true, -- needs lightMap:replacePixels, independent of a full remesh
                model = g3d.newModel ({{}}),
                lightImageData = lightImageData,
                imageDataPtr = imageDataPtr,
                lightMap = lightMap,
            }
            firstPart[j] = newChunk
        end
    end

    -- Reset camera
    g3d.camera.fov = math.pi / 4
    g3d.camera.up = {0, 1, 0}
    g3d.camera.lookAt (0, 0, 10, 0, 0, 0)
    g3d.camera.updateProjectionMatrix()
end

function mapMan:placeBlock (tileX, tileY, layer, blockId)
    if not self:inBounds (tileX, tileY) or not self:isEmpty(tileX, tileY, layer) then
        return false
    end

    assert (blockDefs[blockId] ~= nil, "mapMan:placeBlock requires a valid blockId")

    local grid = self.grid
    local dirtyLight = layer == 1
    local wasSky = self:isSky (tileX, tileY)

    if grid[tileX][tileY].lightSource ~= nil then
        self:removeLight (tileX, tileY)
        dirtyLight = true
    end

    grid[tileX][tileY].layers[layer].def = blockDefs[blockId]
    self:calcFaces (tileX, tileY, layer)

    local chunkX, chunkY = self:tileToChunk (tileX, tileY)
    self.cgrid[chunkX][chunkY].dirty = true

    -- Updates the faces of adjacent blocks
    if tileX > 1 and self:isEmpty(tileX - 1, tileY, layer) == false then
        grid[tileX - 1][tileY].layers[layer].activeFaces.right = false

        local chunkX, chunkY = self:tileToChunk (tileX - 1, tileY)
        self.cgrid[chunkX][chunkY].dirty = true
    end

    if tileX < self.size.w and self:isEmpty(tileX + 1, tileY, layer) == false then
        grid[tileX + 1][tileY].layers[layer].activeFaces.left = false

        local chunkX, chunkY = self:tileToChunk (tileX + 1, tileY)
        self.cgrid[chunkX][chunkY].dirty = true
    end

    if tileY > 1 and self:isEmpty(tileX, tileY - 1, layer) == false then
        grid[tileX][tileY - 1].layers[layer].activeFaces.top = false

        local chunkX, chunkY = self:tileToChunk (tileX, tileY - 1)
        self.cgrid[chunkX][chunkY].dirty = true
    end

    if tileY < self.size.h and self:isEmpty(tileX, tileY + 1, layer) == false then
        grid[tileX][tileY + 1].layers[layer].activeFaces.bottom = false

        local chunkX, chunkY = self:tileToChunk (tileX, tileY + 1)
        self.cgrid[chunkX][chunkY].dirty = true
    end
    
    if dirtyLight == true then
        updateLighting (tileX, tileY)
    end

    if wasSky == true and self:isSky (tileX, tileY) == false then
        removeSkySource (tileX, tileY)
    elseif layer == 1 then
        updateExposureAtAndNeighbors (tileX, tileY)
    end

    return true
end

function mapMan:removeBlock (tileX, tileY, layer)
    if not self:inBounds (tileX, tileY) or self:isEmpty(tileX, tileY, layer) then
        return false
    end

    local grid = self.grid
    local tile = grid[tileX][tileY]
    local dirtyLight = layer == 1
    local wasSky = self:isSky (tileX, tileY)
    
    if grid[tileX][tileY].lightSource ~= nil then
        self:removeLight (tileX, tileY)
        dirtyLight = true
    end
    
    tile.layers[layer].def = blockDefs.air

    local chunkX, chunkY = self:tileToChunk (tileX, tileY)
    self.cgrid[chunkX][chunkY].dirty = true

    if layer + 1 <= self.size.d and self:isEmpty (tileX, tileY, layer + 1) ~= true then
        tile.layers[layer + 1].activeFaces.front = true
    end

    if tileX > 1 and self:isEmpty(tileX - 1, tileY, layer) == false then
        grid[tileX - 1][tileY].layers[layer].activeFaces.right = true

        local chunkX, chunkY = self:tileToChunk (tileX - 1, tileY)
        self.cgrid[chunkX][chunkY].dirty = true
    end

    if tileX < self.size.w and self:isEmpty(tileX + 1, tileY, layer) == false then
        grid[tileX + 1][tileY].layers[layer].activeFaces.left = true

        local chunkX, chunkY = self:tileToChunk (tileX + 1, tileY)
        self.cgrid[chunkX][chunkY].dirty = true
    end

    if tileY > 1 and self:isEmpty(tileX, tileY - 1, layer) == false then
        grid[tileX][tileY - 1].layers[layer].activeFaces.top = true

        local chunkX, chunkY = self:tileToChunk (tileX, tileY - 1)
        self.cgrid[chunkX][chunkY].dirty = true
    end

    if tileY < self.size.h and self:isEmpty(tileX, tileY + 1, layer) == false then
        grid[tileX][tileY + 1].layers[layer].activeFaces.bottom = true

        local chunkX, chunkY = self:tileToChunk (tileX, tileY + 1)
        self.cgrid[chunkX][chunkY].dirty = true
    end

    -- Updates the lighting
    if dirtyLight == true then
        updateLighting (tileX, tileY)
    end

    if wasSky == false and self:isSky (tileX, tileY) == true then
        placeSkySource (tileX, tileY)
    elseif layer == 1 then
        updateExposureAtAndNeighbors (tileX, tileY)
    end

    return true
end

local exposureSeedPool = {
    {0, 0},
    {0, 0},
    {0, 0},
    {0, 0},
    {0, 0},
}
local exposureSeedQueue = {}

function updateExposureAtAndNeighbors (tileX, tileY)
    local count = 1
    exposureSeedPool[count][1], exposureSeedPool[count][2] = tileX, tileY
    exposureSeedQueue[count] = exposureSeedPool[count]

    for i = 1, #neighborTileOffsets do
        local offsets = neighborTileOffsets[i]
        local neighborX, neighborY = tileX + offsets[1], tileY + offsets[2]

        if mapMan:inBounds (neighborX, neighborY) then
            count = count + 1
            exposureSeedPool[count][1], exposureSeedPool[count][2] = neighborX, neighborY
            exposureSeedQueue[count] = exposureSeedPool[count]
        end
    end

    for i = count + 1, #exposureSeedPool do
        exposureSeedQueue[i] = nil
    end

    updateSkyExposure (exposureSeedQueue)
end

-- Determines whether a specific block space is empty (air block)
function mapMan:isEmpty (tileX, tileY, layer)
    if tileX < 1 or tileX > self.size.w or tileY < 1 or tileY > self.size.h then
        return true
    end

    return self.grid[tileX][tileY].layers[layer].def.id == "air"
end

function mapMan:isSky (tileX, tileY)
    if self:inBounds (tileX, tileY) == false then
        return true
    end

    for layer = 1, self.size.d do
        if self:isEmpty (tileX, tileY, layer) == false then
            return false
        end
    end

    return true
end

function mapMan:inBounds (tileX, tileY)
    return tileX >= 1 and tileX <= self.size.w and tileY >= 1 and tileY <= self.size.h
end

-- Returns true if the block at (tileX, tileY, layer) exists and is SOLID (used for AO).
-- Liquids and gases shouldn't cast/receive AO the way solid terrain does, so this checks
-- block.type rather than just "is it air". Add a `type = "liquid" | "gas" | "solid"` field
-- to block defs in blockDefs; defs that don't set one are treated as solid, which keeps
-- old behavior for every existing block def.
function mapMan:isSolidAt (tileX, tileY, layer)
    if layer < 1 or layer > self.size.d then
        return false
    end

    if tileX < 1 or tileX > self.size.w or tileY < 1 or tileY > self.size.h then
        return false
    end

    local blockDef = self.grid[tileX][tileY].layers[layer].def

    return blockDef.id ~= "air"
end

-- Classic "2 sides + corner" AO formula (same one Minecraft uses).
-- occluders is how many of the 3 relevant neighbor cells are solid (0-3).
-- If both edge-neighbors are solid the corner is always maximally dark, even if the
-- diagonal happens to be empty, since light can't wrap around a fully enclosed corner.
local aoLevels = {1.0, 0.75, 0.5, 0.3} -- tune to taste: [1 occluder=0, 2=1, 3=2, 4=3]
function vertexAO (side1, side2, corner)
    if side1 and side2 then
        return aoLevels[4]
    end

    local occluders = (side1 and 1 or 0) + (side2 and 1 or 0) + (corner and 1 or 0)
    return aoLevels[occluders + 1]
end

-- Computes the AO brightness (0-1) for a single vertex of a face, based on the two
-- grid-neighbors and the diagonal neighbor that touch that vertex's corner.
-- Crucially, these checks happen in the plane just OUTSIDE the face (offset along the face's
-- own normal), not in the solid block's own layer/position -- e.g. a front face's AO depends on
-- what's poking out in the layer *in front* of it, not on the block's own same-layer neighbors
-- (which are almost always solid and would otherwise darken nearly every exposed block).
-- vertData holds the vertex's local (x, y, z) offsets from cubeData, each 0 or -1/0/1.
function calcVertexAO (face, tileX, tileY, layer, vertData)
    local dx = vertData[0] == 0 and -1 or 1
    local dy = vertData[1] == 0 and -1 or 1
    -- z is 0 at the front boundary of this layer or -1 at the back boundary; used only by the
    -- side faces below to find the corner's offset along the layer (depth) axis
    local dLayerCorner = vertData[2] == 0 and -1 or 1

    if face == "front" then
        -- The open space this face looks out into is the layer in front of this block
        local refLayer = layer - 1
        local side1 = mapMan:isSolidAt (tileX + dx, tileY, refLayer)
        local side2 = mapMan:isSolidAt (tileX, tileY + dy, refLayer)
        local corner = mapMan:isSolidAt (tileX + dx, tileY + dy, refLayer)
        return vertexAO (side1, side2, corner)
    elseif face == "left" or face == "right" then
        -- The open space this face looks out into is the column beside this block
        local refX = face == "left" and tileX - 1 or tileX + 1
        local side1 = mapMan:isSolidAt (refX, tileY + dy, layer)
        local side2 = mapMan:isSolidAt (refX, tileY, layer + dLayerCorner)
        local corner = mapMan:isSolidAt (refX, tileY + dy, layer + dLayerCorner)
        return vertexAO (side1, side2, corner)
    else -- top / bottom
        -- The open space this face looks out into is the row above/below this block
        local refY = face == "top" and tileY + 1 or tileY - 1
        local side1 = mapMan:isSolidAt (tileX + dx, refY, layer)
        local side2 = mapMan:isSolidAt (tileX, refY, layer + dLayerCorner)
        local corner = mapMan:isSolidAt (tileX + dx, refY, layer + dLayerCorner)
        return vertexAO (side1, side2, corner)
    end
end

function addFace (vertices, index, face, textureIds, x, y, z, layer)
    local faceVertData = cubeData[face]
    local tx, ty, tw, th = blockAtlas:getViewport (textureIds[face])
    local atlasW, atlasH = blockAtlas.image:getDimensions()

    local pixelX = (x - 1) % mapMan.size.cw
    local pixelY = (y - 1) % mapMan.size.ch

    for i = 0, 5 do
        local vertData = faceVertData.verts[i]

        -- Write vertex
        vertices[index].x = x + vertData[0]
        vertices[index].y = y + vertData[1]
        vertices[index].z = z + vertData[2]
        vertices[index].u = (tx + vertData[3] * tw) / atlasW
        vertices[index].v = (ty + vertData[4] * th) / atlasH

        -- Sample the light map exactly at this vertex's tile CORNER, not the tile center.
        -- Combined with the light map's linear filtering, this makes the GPU blend the light
        -- of the tiles that share this corner automatically -- this is what gives us smooth
        -- lighting, instead of one flat light value per face.
        -- +1 / (cw+2) accounts for the 1px apron border added around each chunk's light map
        -- (see resetMap / writeLightMapTargets), so sampling stays correct right up to chunk edges.
        local cornerX = pixelX + vertData[0]
        local cornerY = pixelY + vertData[1]
        vertices[index].nx = (cornerX + 1) / (mapMan.size.cw + 2)
        vertices[index].ny = (cornerY + 1) / (mapMan.size.ch + 2)
        vertices[index].nz = faceVertData.colorMulti -- Face color multiplier
        vertices[index].r = 0 -- unused / reserved
        vertices[index].g = 0 -- unused / reserved
        vertices[index].b = 0 -- unused / reserved
        vertices[index].a = math.floor (calcVertexAO (face, x, y, layer, vertData) * 255 + 0.5) -- baked AO

        index = index + 1
    end

    return index
end

function mapMan:remeshChunk (chunkX, chunkY)
    -- TEMP: Tracks the time tacken to complete
    local startTime = love.timer.getTime()

    local grid = self.grid
    local faceCount = 0
    local chunk = self.cgrid[chunkX][chunkY]

    local startX, startY = (chunkX - 1) * self.size.cw + 1, (chunkY - 1) * self.size.ch + 1
    local endX, endY = startX + self.size.cw - 1, startY + self.size.ch - 1
    endX, endY = math.min (endX, self.size.w), math.min (endY, self.size.h)

    -- Count the number of active faces
    for i = startX, endX do
        local firstPart = grid[i]

        for j = startY, endY do
            local tile = firstPart[j]

            if tile.dirty == true then
                calcLightColor (i, j)
                calcSkyExposure (i, j)
                tile.dirty = false
            end

            for layerIndex = 1, self.size.d do
                local block = tile.layers[layerIndex]

                if block.def.id ~= "air" then
                    if block.activeFaces == nil then
                        self:calcFaces (i, j, layerIndex)
                    end

                    for face, enabled in pairs (block.activeFaces) do
                        if enabled == true then
                            faceCount = faceCount + 1
                        end
                    end
                end
            end
        end
    end

    -- print ("Faces: " .. faceCount)

    -- Generate the data for storing the vertices
    if faceCount > 0 then
        local vertexCount = faceCount * 6  -- 6 vertices per face (2 triangles) * number of active faces in all blocks
        local vertexData = love.data.newByteData(vertexCount * ffi.sizeof("Vertex")) -- creates byte array of verts containing all active faces
        local vertices = ffi.cast("Vertex *", vertexData:getFFIPointer()) -- Tell lua how to cast the byte data so we can interact with it (array of vertex structs)
        local vertexIndex = 0

        -- Generate the vertex data for each face
        for i = startX, endX do
            local firstPart = grid[i]

            for j = startY, endY do
                local tile = firstPart[j]

                for layerIndex = 1, self.size.d do
                    local block = tile.layers[layerIndex]
                    local blockID = block.def.id

                    -- Do not add air blocks to the mesh
                    if blockID ~= "air" then
                        for face, enabled in pairs (block.activeFaces) do
                            if enabled == true then
                                vertexIndex = addFace (
                                    vertices, vertexIndex,
                                    face, block.def.textureIds,
                                    i, j, 1 - layerIndex, layerIndex
                                )
                            end
                        end
                    end
                end
            end
        end
        -- Create a new model from the mesh
        chunk.model = g3d.newModel(vertexData, blockAtlas.image)
    else
        -- Create empty model if there are no active faces in the chunk
        local vertexData = love.data.newByteData(ffi.sizeof("Vertex"))
        chunk.model = g3d.newModel(vertexData, blockAtlas.image)
    end


    -- Update the light map image
    chunk.lightMap:replacePixels (chunk.lightImageData)
    chunk.lightMapDirty = false

    -- TEMP: Print out the time taken to complete
    -- print ("Time taken to remesh chunk: ", love.timer.getTime() - startTime)
end

-- Determines which faces of a block should be rendered based on surrounding blocks
function mapMan:calcFaces (tileX, tileY, layer)
    local grid = self.grid
    local tile = grid[tileX][tileY]

    if tile.layers[layer].def.id == "air" then
        tile.layers[layer].activeFaces = nil

        return
    end

    local faces = {
        left = false,
        right = false,
        top = false,
        bottom = false,
        front = false,
        back = false,
    }

    -- A face is exposed to "front" whenever the layer immediately behind it is empty,
    -- or the block is on the outermost layer.
    if layer == 1 or (layer > 1 and tile.layers[layer - 1].def.id == "air") then
        faces.front = true
    end

    if tileX <= 1 or grid[tileX - 1][tileY].layers[layer].def.id == "air" then
        faces.left = true
    end

    if tileX >= self.size.w or grid[tileX + 1][tileY].layers[layer].def.id == "air" then
        faces.right = true
    end

    if tileY >= self.size.h or grid[tileX][tileY + 1].layers[layer].def.id == "air" then
        faces.top = true
    end

    if tileY <= 1 or grid[tileX][tileY - 1].layers[layer].def.id == "air" then
        faces.bottom = true
    end

    tile.layers[layer].activeFaces = faces
end

-- TODO: Precompute these values or memoize these
function getTilesInExpoRadius (tileY)
    local R = mapMan.maxExposure - 1
    local H = mapMan.size.h

    local topOverflow = math.max(0, R - (tileY - 1))
    local bottomOverflow = math.max(0, R - (H - tileY))

    -- Full diamond area minus the clipped triangles.
    return (2 * R * (R + 1) + 1)
         - topOverflow * topOverflow
         - bottomOverflow * bottomOverflow
end

-- TODO: Precompute a map of exposure to alpha values based on the tile's distance from the source
function calcSkyExposure (tileX, tileY)
    local tile = mapMan.grid[tileX][tileY]
    local exposure = tile.exposure
    local alpha = math.floor (mapToScale (exposure, 0, mapMan.maxExposure, 0, 255) + 0.5)
    writeLightMapTargets (tileX, tileY, nil, nil, nil, alpha)
end

-- Calculates the new sky exposure of a tile based on its valid neighbors
-- TODO: Use cdata arrays for the tilequeue
-- TODO: Precompute an array of offsets to use for neighbor lookups instead of doing it dynamically
neighborTileOffsets = {
    {-1, 0},
    {1, 0},
    {0, -1},
    {0, 1},
}
function updateSkyExposure (tileQueue)
    -- BFS to calculate the exposure of each tile in the queue
    -- Each tile's exposure is the max of its neighbors' exposure - 1, or 0 if it has no valid neighbors
    -- Valid neighbors are tiles with a value greater than the current tile's and are not fully solid if the current tile is air
    local queuedTiles = Auto2DArray:new ()
    local grid = mapMan.grid
    local inBounds = mapMan.inBounds
    local isSky = mapMan.isSky
    local maxExposure = mapMan.maxExposure

    local function enqueueTile (tileX, tileY, budget)
        if inBounds (mapMan, tileX, tileY) ~= true then
            return
        end

        local lastBudget = queuedTiles[tileX][tileY]
        if lastBudget == nil or budget > lastBudget then
            queuedTiles[tileX][tileY] = budget
            table.insert (tileQueue, {tileX, tileY, budget})
        end
    end

    -- Seeds start with a full travel budget.
    local initialQueue = tileQueue
    tileQueue = {}
    for _, seed in ipairs (initialQueue) do
        enqueueTile (seed[1], seed[2], seed[3] or maxExposure)
    end

    local queueIndex = 1
    while queueIndex <= #tileQueue do
        local currentTile = tileQueue[queueIndex]
        queueIndex = queueIndex + 1
        local curX, curY, budget = currentTile[1], currentTile[2], currentTile[3]
        queuedTiles[curX][curY] = nil

        -- Every fully-sky tile is a skylight source; keep it pinned at full exposure.
        -- Without this anchor, repeated recomputes can ratchet source tiles downward.
        if isSky (mapMan, curX, curY) == true then
            local curExpo = grid[curX][curY].exposure
            if grid[curX][curY].exposure ~= maxExposure then
                grid[curX][curY].exposure = maxExposure
                grid[curX][curY].dirty = true
            end

            if budget > 0 and curExpo ~= maxExposure then
                for i = 1, #neighborTileOffsets do
                    local offsets = neighborTileOffsets[i]
                    enqueueTile (curX + offsets[1], curY + offsets[2], budget - 1)
                end
            end
        else
            local curExpo = grid[curX][curY].exposure

            local maxNeighborExpo = 0
            for i = 1, #neighborTileOffsets do
                local offsets = neighborTileOffsets[i]
                local neighborX, neighborY = curX + offsets[1], curY + offsets[2]

                if inBounds (mapMan, neighborX, neighborY) == true then
                    local neighborExpo = 0
                    if canReceiveExposure (curX, curY, neighborX, neighborY) == true then
                        neighborExpo = grid[neighborX][neighborY].exposure
                    end

                    maxNeighborExpo = math.max (maxNeighborExpo, neighborExpo)

                end
            end

            local newExpo = math.max (maxNeighborExpo - 1, 0)
            if curExpo ~= newExpo then
                grid[curX][curY].exposure = newExpo
                grid[curX][curY].dirty = true

                if budget > 0 then
                    for i = 1, #neighborTileOffsets do
                        local offsets = neighborTileOffsets[i]
                        enqueueTile (curX + offsets[1], curY + offsets[2], budget - 1)
                    end
                end
            end
        end
    end
end

function placeSkySource (tileX, tileY)
    local grid = mapMan.grid
    local tile = grid[tileX][tileY]
    tile.exposure = mapMan.maxExposure
    tile.dirty = true

    local tileQueue = {}

    -- Add the tile's neighbors to the queue
    if mapMan:inBounds (tileX - 1, tileY) then
        table.insert (tileQueue, {tileX - 1, tileY})
    end
    if mapMan:inBounds (tileX + 1, tileY) then
        table.insert (tileQueue, {tileX + 1, tileY})
    end
    if mapMan:inBounds (tileX, tileY - 1) then
        table.insert (tileQueue, {tileX, tileY - 1})
    end
    if mapMan:inBounds (tileX, tileY + 1) then
        table.insert (tileQueue, {tileX, tileY + 1})
    end

    -- Update exposure values
    updateSkyExposure (tileQueue)

    -- Increment claim value for ALL tiles in range using a BFS from the source
    local claimQueue = {{tileX, tileY, mapMan.maxExposure}}
    local visitedTiles = Auto2DArray:new ()
    visitedTiles[tileX][tileY] = true

    local claimHead = 1
    while claimHead <= #claimQueue do
        local currentTile = claimQueue[claimHead]
        claimHead = claimHead + 1
        local curX, curY, budget = currentTile[1], currentTile[2], currentTile[3]

        grid[curX][curY].expoClaims = grid[curX][curY].expoClaims + 1
        assert (grid[curX][curY].expoClaims <= getTilesInExpoRadius (curY), "expoClaims exceeded max for tile " .. curX .. ", " .. curY)

        for i = 1, #neighborTileOffsets do
            local offsets = neighborTileOffsets[i]
            local neighborX, neighborY = curX + offsets[1], curY + offsets[2]

            if mapMan:inBounds (neighborX, neighborY) == true and not visitedTiles[neighborX][neighborY] then
                if budget > 1 and not visitedTiles[neighborX][neighborY] then
                    visitedTiles[neighborX][neighborY] = true   -- mark on enqueue, not dequeue
                    table.insert (claimQueue, {neighborX, neighborY, budget - 1})
                end
            end
        end
    end
end

-- Determines whether `destX,destY` is allowed to receive exposure from `srcX,srcY`.
-- Same asymmetric gate used everywhere else: an air destination can receive from any
-- neighbor; a solid destination can only receive from a neighbor that's also solid.
function canReceiveExposure (destX, destY, srcX, srcY)
    local destIsFgSolid = mapMan:isSolidAt (destX, destY, 1)
    return mapMan:isEmpty (srcX, srcY, 1) == true or destIsFgSolid == true
end

function removeSkySource (tileX, tileY)
    local grid = mapMan.grid
    local inBounds = mapMan.inBounds
    local isSky = mapMan.isSky
    local maxExposure = mapMan.maxExposure
    local tile = grid[tileX][tileY]
    tile.exposure = 0
    tile.dirty = true

    -- Decrement claim value for ALL tiles in range using a BFS from the source
    local claimQueue = {{tileX, tileY, maxExposure}}
    local visitedTiles = Auto2DArray:new ()
    visitedTiles[tileX][tileY] = true

    local claimHead = 1
    while claimHead <= #claimQueue do
        local currentTile = claimQueue[claimHead]
        claimHead = claimHead + 1
        local curX, curY, budget = currentTile[1], currentTile[2], currentTile[3]
        grid[curX][curY].expoClaims = grid[curX][curY].expoClaims - 1
        assert (grid[curX][curY].expoClaims >= 0, "expoClaims went negative at " .. curX .. ", " .. curY)

        for i = 1, #neighborTileOffsets do
            local offsets = neighborTileOffsets[i]
            local neighborX, neighborY = curX + offsets[1], curY + offsets[2]

            if inBounds (mapMan, neighborX, neighborY) == true and not visitedTiles[neighborX][neighborY] then
                if budget > 1 and not visitedTiles[neighborX][neighborY] then
                    visitedTiles[neighborX][neighborY] = true   -- mark on enqueue, not dequeue
                    table.insert (claimQueue, {neighborX, neighborY, budget - 1})
                end
            end
        end
    end

    -- Update lighting values using a BFS
    -- Only tiles that are still claimed by other sources should retain their exposure; all others should be set to 0
    local tileQueue = {{tileX, tileY, maxExposure}}
    local queuedTiles = Auto2DArray:new ()

    local function enqueueTile (nextX, nextY, budget)
        if inBounds (mapMan, nextX, nextY) ~= true then
            return
        end

        local lastBudget = queuedTiles[nextX][nextY]
        if lastBudget == nil or budget > lastBudget then
            queuedTiles[nextX][nextY] = budget
            table.insert (tileQueue, {nextX, nextY, budget})
        end
    end

    queuedTiles[tileX][tileY] = maxExposure

    local queueIndex = 1
    while queueIndex <= #tileQueue do
        local currentTile = tileQueue[queueIndex]
        queueIndex = queueIndex + 1
        local curX, curY, budget = currentTile[1], currentTile[2], currentTile[3]
        queuedTiles[curX][curY] = nil

        -- Keep remaining sky sources pinned at full exposure during source removal updates.
        if isSky (mapMan, curX, curY) == true then
            local curExpo = grid[curX][curY].exposure
            if grid[curX][curY].exposure ~= maxExposure then
                grid[curX][curY].exposure = maxExposure
                grid[curX][curY].dirty = true
            end

            if budget > 0 and curExpo ~= maxExposure then
                for i = 1, #neighborTileOffsets do
                    local offsets = neighborTileOffsets[i]
                    enqueueTile (curX + offsets[1], curY + offsets[2], budget - 1)
                end
            end
        else
            local curExpo = grid[curX][curY].exposure

            local maxNeighborExpo = 0
            for i = 1, #neighborTileOffsets do
                local offsets = neighborTileOffsets[i]
                local neighborX, neighborY = curX + offsets[1], curY + offsets[2]

                if inBounds (mapMan, neighborX, neighborY) == true then
                    local neighborExpo = 0
                    if canReceiveExposure (curX, curY, neighborX, neighborY) == true then
                        neighborExpo = grid[neighborX][neighborY].exposure
                    end

                    if grid[neighborX][neighborY].expoClaims > 0 then
                        maxNeighborExpo = math.max (maxNeighborExpo, neighborExpo)
                    end

                end
            end

            local newExpo = math.max (maxNeighborExpo - 1, 0)
            if curExpo ~= newExpo then
                grid[curX][curY].exposure = newExpo
                grid[curX][curY].dirty = true

                if budget > 0 then
                    for i = 1, #neighborTileOffsets do
                        local offsets = neighborTileOffsets[i]
                        enqueueTile (curX + offsets[1], curY + offsets[2], budget - 1)
                    end
                end
            end
        end
    end
end

-- Writes one tile's RGB and/or alpha into its chunk interior texel plus any affected apron texels.
-- Pass nil for channels you don't want to modify (e.g. RGB-only or alpha-only updates).
function writeLightMapTargets (tileX, tileY, r, g, b, a)
    local cw, ch = mapMan.size.cw, mapMan.size.ch
    local chunkX, chunkY = mapMan:tileToChunk (tileX, tileY)
    local pixelX = (tileX - 1) % cw
    local pixelY = (tileY - 1) % ch
    local width = cw + 2
    local cgrid = mapMan.cgrid

    local function writeTarget (cx, cy, px, py)
        local col = cgrid[cx]
        local chunk = col and col[cy]
        if chunk == nil then
            return
        end

        local ptr = chunk.imageDataPtr
        local pixelIndex = (py * width + px) * 4

        if r ~= nil then
            ptr[pixelIndex] = r
            ptr[pixelIndex + 1] = g
            ptr[pixelIndex + 2] = b
        end

        if a ~= nil then
            ptr[pixelIndex + 3] = a
        end

        chunk.lightMapDirty = true
    end

    -- Own chunk's interior (offset by 1 to account for the apron border)
    writeTarget (chunkX, chunkY, pixelX + 1, pixelY + 1)

    local onLeftEdge   = pixelX == 0
    local onRightEdge  = pixelX == cw - 1
    local onBottomEdge = pixelY == 0
    local onTopEdge    = pixelY == ch - 1

    if onLeftEdge   then writeTarget (chunkX - 1, chunkY, cw + 1, pixelY + 1) end
    if onRightEdge  then writeTarget (chunkX + 1, chunkY, 0, pixelY + 1) end
    if onBottomEdge then writeTarget (chunkX, chunkY - 1, pixelX + 1, ch + 1) end
    if onTopEdge    then writeTarget (chunkX, chunkY + 1, pixelX + 1, 0) end

    if onLeftEdge  and onBottomEdge then writeTarget (chunkX - 1, chunkY - 1, cw + 1, ch + 1) end
    if onLeftEdge  and onTopEdge    then writeTarget (chunkX - 1, chunkY + 1, cw + 1, 0) end
    if onRightEdge and onBottomEdge then writeTarget (chunkX + 1, chunkY - 1, 0, ch + 1) end
    if onRightEdge and onTopEdge    then writeTarget (chunkX + 1, chunkY + 1, 0, 0) end
end

function calcLightColor (tileX, tileY)
    local tile = mapMan.grid[tileX][tileY]
    local newCombinedLightColor = {0, 0, 0}

    for lightRef, lightData in pairs(tile.lights) do
        if lightData.enabled == true then
            local dist = lightData.dist
            local lightMulti = ((-dist + lightRef.radius) / mapMan.maxLightLevel) * lightRef.maxLevel
            lightMulti = lume.clamp (lightMulti, 0, 1)

            newCombinedLightColor[1] = newCombinedLightColor[1] + lightRef.color[0] * lightMulti
            newCombinedLightColor[2] = newCombinedLightColor[2] + lightRef.color[1] * lightMulti
            newCombinedLightColor[3] = newCombinedLightColor[3] + lightRef.color[2] * lightMulti
        end
    end

    local r = math.floor (lume.clamp (newCombinedLightColor[1], 0, 1) * 255)
    local g = math.floor (lume.clamp (newCombinedLightColor[2], 0, 1) * 255)
    local b = math.floor (lume.clamp (newCombinedLightColor[3], 0, 1) * 255)

    writeLightMapTargets (tileX, tileY, r, g, b, nil)
end

-- Places a light at the center of a block
function mapMan:placeLight (tileX, tileY, radius, color, intensity)
    radius = lume.clamp (radius, 1, self.maxLightLevel)
    intensity = lume.clamp (intensity or radius, 1, self.maxLightLevel)

    if self:inBounds (tileX, tileY) == false then
        return false
    end

    local grid = self.grid

    if grid[tileX][tileY].lightSource ~= nil then
        return false
    end

    assert (radius ~= nil, "Light radius must be specified when placing a light")
    assert (color ~= nil, "Light color must be specified when placing a light")

    local lightRef = ffi.new ("LightSource", {
        pos = {tileX, tileY},
        radius = radius,
        color = color,
        maxLevel = intensity / radius,
    })
    grid[tileX][tileY].dirty = true
    grid[tileX][tileY].lightSource = lightRef -- Designate the block as a light source and store light data
    grid[tileX][tileY].lights[lightRef] = {
        enabled = true,
        dist = 0,
    }
    local chunkX, chunkY = self:tileToChunk (tileX , tileY)
    self.cgrid[chunkX][chunkY].dirty = true

    -- Add light reference to all blocks within radius using BFS with decay
    -- table.insert (grid[tileX][tileY].lights, lightRef) -- Add light reference to block's light list
    -- grid[tileX][tileY].dirty = true

    local visitedTiles = Auto2DArray:new ()
    local queue = {}

    visitedTiles[tileX][tileY] = true

    if self:inBounds (tileX - 1, tileY) and not visitedTiles[tileX - 1][tileY] then
        table.insert (queue, {tileX - 1, tileY, radius - 1})
        visitedTiles[tileX - 1][tileY] = true  -- Mark as visited when adding to queue
    end
    if self:inBounds (tileX + 1, tileY) and not visitedTiles[tileX + 1][tileY] then
        table.insert (queue, {tileX + 1, tileY, radius - 1})
        visitedTiles[tileX + 1][tileY] = true  -- Mark as visited when adding to queue
    end
    if self:inBounds (tileX, tileY - 1) and not visitedTiles[tileX][tileY - 1] then
        table.insert (queue, {tileX, tileY - 1, radius - 1})
        visitedTiles[tileX][tileY - 1] = true  -- Mark as visited when adding to queue
    end
    if self:inBounds (tileX, tileY + 1) and not visitedTiles[tileX][tileY + 1] then
        table.insert (queue, {tileX, tileY + 1, radius - 1})
        visitedTiles[tileX][tileY + 1] = true  -- Mark as visited when adding to queue
    end

    local queueHead = 1
    while queueHead <= #queue do
        local currentTile = queue[queueHead]
        queueHead = queueHead + 1
        local curX, curY, count = currentTile[1], currentTile[2], currentTile[3]

        local isAir = self:isEmpty (curX, curY, 1)
        local dist = lume.distance (lightRef.pos[0], lightRef.pos[1], curX, curY)

        -- Looks for adjacent tiles with a shorter distance that have light enabled
        local lightEnabled = false

        if self:inBounds (curX - 1, curY) == true then
            local leftTileLightRef = grid[curX - 1][curY].lights[lightRef]
            if leftTileLightRef and (leftTileLightRef.dist or math.huge) < dist and leftTileLightRef.enabled == true then
                if self:isEmpty (curX - 1, curY, 1) == true or isAir == false then
                    lightEnabled = true
                end
            end
        end
        if self:inBounds (curX + 1, curY) == true then
            local rightTileLightRef = grid[curX + 1][curY].lights[lightRef]
            if rightTileLightRef and (rightTileLightRef.dist or math.huge) < dist and rightTileLightRef.enabled == true then
                if self:isEmpty (curX + 1, curY, 1) == true or isAir == false then
                    lightEnabled = true
                end
            end
        end
        if self:inBounds (curX, curY - 1) == true then
            local topTileLightRef = grid[curX][curY - 1].lights[lightRef]
            if topTileLightRef and (topTileLightRef.dist or math.huge) < dist and topTileLightRef.enabled == true then
                if self:isEmpty (curX, curY - 1, 1) == true or isAir == false then
                    lightEnabled = true
                end
            end
        end
        if self:inBounds (curX, curY + 1) == true then
            local bottomTileLightRef = grid[curX][curY + 1].lights[lightRef]
            if bottomTileLightRef and self:inBounds (curX, curY + 1) and (bottomTileLightRef.dist or math.huge) < dist and bottomTileLightRef.enabled == true then
                if self:isEmpty (curX, curY + 1, 1) == true or isAir == false then
                    lightEnabled = true
                end
            end
        end

        grid[curX][curY].dirty = true
        grid[curX][curY].lights[lightRef] = {
            enabled = lightEnabled,
            dist = dist,
        }
        local chunkX, chunkY = self:tileToChunk (curX , curY)
        self.cgrid[chunkX][chunkY].dirty = true

        -- Add neighbors to queue
        if count - 1 > 0 then
            if self:inBounds (curX - 1, curY) and not visitedTiles[curX - 1][curY] then
                table.insert (queue, {curX - 1, curY, count - 1})
                visitedTiles[curX - 1][curY] = true  -- Mark as visited when adding to queue
            end
            if self:inBounds (curX + 1, curY) and not visitedTiles[curX + 1][curY] then
                table.insert (queue, {curX + 1, curY, count - 1})
                visitedTiles[curX + 1][curY] = true  -- Mark as visited when adding to queue
            end
            if self:inBounds (curX, curY - 1) and not visitedTiles[curX][curY - 1] then
                table.insert (queue, {curX, curY - 1, count - 1})
                visitedTiles[curX][curY - 1] = true  -- Mark as visited when adding to queue
            end
            if self:inBounds (curX, curY + 1) and not visitedTiles[curX][curY + 1] then
                table.insert (queue, {curX, curY + 1, count - 1})
                visitedTiles[curX][curY + 1] = true  -- Mark as visited when adding to queue
            end
        end
    end

    return true
end

function mapMan:removeLight (tileX, tileY)
    if self:inBounds (tileX, tileY) == false then
        return false
    end

    local grid = self.grid

    if grid[tileX][tileY].lightSource == nil then
        return false
    end

    -- Remove light reference from all blocks within the old light reference's radius using BFS with decay
    local oldLightRef = grid[tileX][tileY].lightSource
    
    grid[tileX][tileY].lightSource = nil
    grid[tileX][tileY].dirty = true
    local chunkX, chunkY = self:tileToChunk (tileX , tileY)
    self.cgrid[chunkX][chunkY].dirty = true

    local visitedTiles = Auto2DArray:new ()
    local queue = {}

    table.insert (queue, {tileX, tileY, oldLightRef.radius})
    visitedTiles[tileX][tileY] = true

    local queueHead = 1
    while queueHead <= #queue do
        local currentTile = queue[queueHead]
        queueHead = queueHead + 1
        local curX, curY, count = currentTile[1], currentTile[2], currentTile[3]

        grid[curX][curY].dirty = true
        grid[curX][curY].lights[oldLightRef] = nil -- Remove light ref from table
        local chunkX, chunkY = self:tileToChunk (curX , curY)
        self.cgrid[chunkX][chunkY].dirty = true

        -- Add neighbors to queue
        if count - 1 > 0 then
            if self:inBounds (curX - 1, curY) and not visitedTiles[curX - 1][curY] then
                table.insert (queue, {curX - 1, curY, count - 1})
                visitedTiles[curX - 1][curY] = true  -- Mark as visited when adding to queue
            end
            if self:inBounds (curX + 1, curY) and not visitedTiles[curX + 1][curY] then
                table.insert (queue, {curX + 1, curY, count - 1})
                visitedTiles[curX + 1][curY] = true  -- Mark as visited when adding to queue
            end
            if self:inBounds (curX, curY - 1) and not visitedTiles[curX][curY - 1] then
                table.insert (queue, {curX, curY - 1, count - 1})
                visitedTiles[curX][curY - 1] = true  -- Mark as visited when adding to queue
            end
            if self:inBounds (curX, curY + 1) and not visitedTiles[curX][curY + 1] then
                table.insert (queue, {curX, curY + 1, count - 1})
                visitedTiles[curX][curY + 1] = true  -- Mark as visited when adding to queue
            end
        end
    end

    return true
end

function updateLighting (tileX, tileY)
    local grid = mapMan.grid

    -- Update the lighting for all light references in the tile's light table
    for lightRef, _ in pairs(mapMan.grid[tileX][tileY].lights) do
        local visitedTiles = Auto2DArray:new ()
        local queue = {}

        table.insert (queue, {tileX, tileY, true})
        visitedTiles[tileX][tileY] = true

        -- BFS to update the lighting for all tiles affected by this light reference
        local queueHead = 1
        while queueHead <= #queue do
            local currentTilePos = queue[queueHead]
            queueHead = queueHead + 1
            local curX, curY, isSeed = currentTilePos[1], currentTilePos[2], currentTilePos[3]
            local currentTileLights = grid[curX][curY].lights[lightRef]
            local dist = currentTileLights.dist
            local lastLightState = currentTileLights.enabled
            local isAir = mapMan:isEmpty (curX, curY, 1)

            -- Looks for adjacent tiles with a shorter distance that have light enabled
            local lightEnabled = false

            if mapMan:inBounds (curX - 1, curY) == true then
                local leftTileLightRef = grid[curX - 1][curY].lights[lightRef]
                if leftTileLightRef and (leftTileLightRef.dist or math.huge) < dist and leftTileLightRef.enabled == true then
                    if mapMan:isEmpty (curX - 1, curY, 1) == true or isAir == false then
                        lightEnabled = true
                    end
                end
            end
            if mapMan:inBounds (curX + 1, curY) == true then
                local rightTileLightRef = grid[curX + 1][curY].lights[lightRef]
                if rightTileLightRef and (rightTileLightRef.dist or math.huge) < dist and rightTileLightRef.enabled == true then
                    if mapMan:isEmpty (curX + 1, curY, 1) == true or isAir == false then
                        lightEnabled = true
                    end
                end
            end
            if mapMan:inBounds (curX, curY - 1) == true then
                local topTileLightRef = grid[curX][curY - 1].lights[lightRef]
                if topTileLightRef and (topTileLightRef.dist or math.huge) < dist and topTileLightRef.enabled == true then
                    if mapMan:isEmpty (curX, curY - 1, 1) == true or isAir == false then
                        lightEnabled = true
                    end
                end
            end
            if mapMan:inBounds (curX, curY + 1) == true then
                local bottomTileLightRef = grid[curX][curY + 1].lights[lightRef]
                if bottomTileLightRef and mapMan:inBounds (curX, curY + 1) and (bottomTileLightRef.dist or math.huge) < dist and bottomTileLightRef.enabled == true then
                    if mapMan:isEmpty (curX, curY + 1, 1) == true or isAir == false then
                        lightEnabled = true
                    end
                end
            end
            
            currentTileLights.enabled = lightEnabled

            -- Add neighbors to queue
            if lastLightState ~= lightEnabled or isSeed == true then
                grid[curX][curY].dirty = true
                if mapMan:inBounds (curX - 1, curY) and not visitedTiles[curX - 1][curY] and grid[curX - 1][curY].lights[lightRef] and grid[curX - 1][curY].lights[lightRef].dist > dist then
                    table.insert (queue, {curX - 1, curY, false})
                    visitedTiles[curX - 1][curY] = true  -- Mark as visited when adding to queue
                end
                if mapMan:inBounds (curX + 1, curY) and not visitedTiles[curX + 1][curY] and grid[curX + 1][curY].lights[lightRef] and grid[curX + 1][curY].lights[lightRef].dist > dist then
                    table.insert (queue, {curX + 1, curY, false})
                    visitedTiles[curX + 1][curY] = true  -- Mark as visited when adding to queue
                end
                if mapMan:inBounds (curX, curY - 1) and not visitedTiles[curX][curY - 1] and grid[curX][curY - 1].lights[lightRef] and grid[curX][curY - 1].lights[lightRef].dist > dist then
                    table.insert (queue, {curX, curY - 1, false})
                    visitedTiles[curX][curY - 1] = true  -- Mark as visited when adding to queue
                end
                if mapMan:inBounds (curX, curY + 1) and not visitedTiles[curX][curY + 1] and grid[curX][curY + 1].lights[lightRef] and grid[curX][curY + 1].lights[lightRef].dist > dist then
                    table.insert (queue, {curX, curY + 1, false})
                    visitedTiles[curX][curY + 1] = true  -- Mark as visited when adding to queue
                end
            end
        end
    end
end

function mapMan:getLightColor (tileX, tileY)
    local chunkX, chunkY = self:tileToChunk (tileX, tileY)
    local chunk = self.cgrid[chunkX][chunkY]
    local lightImageData = chunk.lightImageData

    local chunkX, chunkY = self:tileToChunk (tileX, tileY)
    local chunk = self.cgrid[chunkX][chunkY]
    local lightImageData = chunk.lightImageData

    local pixelX = (tileX - 1) % mapMan.size.cw + 1
    local pixelY = (tileY - 1) % mapMan.size.ch + 1

    -- TODO: Use a pointer for this later
    local r, g, b = lightImageData:getPixel (pixelX, pixelY)

    return {r, g, b}
end

function mapMan:getSkyExposure (tileX, tileY)
    local chunkX, chunkY = self:tileToChunk (tileX, tileY)
    local chunk = self.cgrid[chunkX][chunkY]
    local lightImageData = chunk.lightImageData

    local pixelX = (tileX - 1) % mapMan.size.cw + 1
    local pixelY = (tileY - 1) % mapMan.size.ch + 1

    -- TODO: Use a pointer for this later
    local _, _, _, a = lightImageData:getPixel (pixelX, pixelY)

    return lume.round (a * self.maxExposure)
end

function mapMan:adjustCam (dx, dy, dzoom)
    g3d.camera.target[1] = g3d.camera.target[1] + dx
    g3d.camera.position[1] = g3d.camera.position[1] + dx

    g3d.camera.target[2] = g3d.camera.target[2] + dy
    g3d.camera.position[2] = g3d.camera.position[2] + dy

    g3d.camera.position[3] = g3d.camera.position[3] + dzoom

    g3d.camera.updateViewMatrix()
end

function mapMan:setCam (x, y, zoom)
    g3d.camera.target[1] = x
    g3d.camera.position[1] = x

    g3d.camera.target[2] = y
    g3d.camera.position[2] = y

    g3d.camera.position[3] = zoom

    g3d.camera.updateViewMatrix()
end

function mapMan:getCam ()
    return unpack (g3d.camera.position)
end

function mapMan:screenToTile (screenX, screenY, targetLayer)
    local width, height = love.graphics.getDimensions()
    local planeZ = 1 - targetLayer
    
    -- Convert screen coordinates to normalized device coordinates (-1 to 1)
    local ndcX = (2.0 * screenX) / width - 1.0
    local ndcY = 1.0 - (2.0 * screenY) / height
    
    -- Get camera properties
    local camPos = g3d.camera.position
    local camTarget = g3d.camera.target
    local camUp = g3d.camera.up
    
    -- Calculate forward vector (view direction)
    local forwardX = camTarget[1] - camPos[1]
    local forwardY = camTarget[2] - camPos[2]
    local forwardZ = camTarget[3] - camPos[3]
    local forwardLen = math.sqrt(forwardX*forwardX + forwardY*forwardY + forwardZ*forwardZ)
    forwardX, forwardY, forwardZ = forwardX/forwardLen, forwardY/forwardLen, forwardZ/forwardLen
    
    -- Calculate right vector (cross product of forward and up)
    local rightX = forwardY * camUp[3] - forwardZ * camUp[2]
    local rightY = forwardZ * camUp[1] - forwardX * camUp[3]
    local rightZ = forwardX * camUp[2] - forwardY * camUp[1]
    local rightLen = math.sqrt(rightX*rightX + rightY*rightY + rightZ*rightZ)
    rightX, rightY, rightZ = rightX/rightLen, rightY/rightLen, rightZ/rightLen
    
    -- Calculate actual up vector (cross product of right and forward)
    local upX = rightY * forwardZ - rightZ * forwardY
    local upY = rightZ * forwardX - rightX * forwardZ
    local upZ = rightX * forwardY - rightY * forwardX
    
    -- Calculate ray direction using FOV and aspect ratio
    local aspectRatio = width / height
    local fovY = g3d.camera.fov
    local halfHeight = math.tan(fovY / 2)
    local halfWidth = halfHeight * aspectRatio
    
    -- Build ray direction
    local rayDirX = forwardX + rightX * ndcX * halfWidth + upX * ndcY * halfHeight
    local rayDirY = forwardY + rightY * ndcX * halfWidth + upY * ndcY * halfHeight
    local rayDirZ = forwardZ + rightZ * ndcX * halfWidth + upZ * ndcY * halfHeight
    
    -- Normalize ray direction
    local rayLen = math.sqrt(rayDirX*rayDirX + rayDirY*rayDirY + rayDirZ*rayDirZ)
    rayDirX, rayDirY, rayDirZ = rayDirX/rayLen, rayDirY/rayLen, rayDirZ/rayLen
    
    -- Intersect with the requested layer plane
    if math.abs(rayDirZ) < 0.0001 then
        return 0, 0
    end
    
    local t = (planeZ - camPos[3]) / rayDirZ
    
    if t < 0 then
        return 0, 0
    end
    
    -- Calculate world intersection point
    local worldX = camPos[1] + t * rayDirX
    local worldY = camPos[2] + t * rayDirY
    
    -- Convert to tile coordinates (blocks now start at integer corners)
    local tileX = math.floor(worldX)
    local tileY = math.floor(worldY)
    
    return tileX, tileY
end

function mapMan:tileToScreen (tileX, tileY, targetLayer)
    local width, height = love.graphics.getDimensions()
    local worldZ = 1 - targetLayer

    -- World position (center of tile on requested layer plane)
    local worldX, worldY = tileX, tileY
    
    -- Apply view matrix transformation
    local viewMatrix = g3d.camera.viewMatrix
    local viewX = viewMatrix[1] * worldX + viewMatrix[2] * worldY + viewMatrix[3] * worldZ + viewMatrix[4]
    local viewY = viewMatrix[5] * worldX + viewMatrix[6] * worldY + viewMatrix[7] * worldZ + viewMatrix[8]
    local viewZ = viewMatrix[9] * worldX + viewMatrix[10] * worldY + viewMatrix[11] * worldZ + viewMatrix[12]
    local viewW = viewMatrix[13] * worldX + viewMatrix[14] * worldY + viewMatrix[15] * worldZ + viewMatrix[16]
    
    -- Apply projection matrix
    local projMatrix = g3d.camera.projectionMatrix
    local clipX = projMatrix[1] * viewX + projMatrix[2] * viewY + projMatrix[3] * viewZ + projMatrix[4] * viewW
    local clipY = projMatrix[5] * viewX + projMatrix[6] * viewY + projMatrix[7] * viewZ + projMatrix[8] * viewW
    local clipW = projMatrix[13] * viewX + projMatrix[14] * viewY + projMatrix[15] * viewZ + projMatrix[16] * viewW
    
    if clipW <= 0 then
        return 0, 0
    end
    
    -- Perspective divide to get NDC
    local ndcX = clipX / clipW
    local ndcY = clipY / clipW
    
    -- Convert NDC to screen coordinates
    local screenX = (ndcX + 1.0) * width / 2.0
    local screenY = (1.0 - ndcY) * height / 2.0
    
    return screenX, screenY
end

function mapMan:autoScreenToTile (screenX, screenY)
    for i = 1, self.size.d do
        local tileX, tileY = self:screenToTile (screenX, screenY, i)

        if self:isEmpty (tileX, tileY, i) == false then
            return tileX, tileY, i
        end
    end

    local tileX, tileY = self:screenToTile (screenX, screenY, self.size.d)

    return tileX, tileY, self.size.d
end

function mapMan:autoTileToScreen (tileX, tileY)
    local layer = self:getTopmostLayer (tileX, tileY) or self.size.d
    
    return self:tileToScreen (tileX, tileY, layer)
end

function mapMan:tileToChunk (tileX, tileY)
    return math.ceil (tileX / self.size.cw), math.ceil (tileY / self.size.ch)
end

function mapMan:getTopmostLayer (tileX, tileY)
    for i = 1, self.size.d do
        if self:isEmpty (tileX, tileY, i) == false then
            return i
        end
    end
end

function mapMan:getExposureColor ()
    local timeOfDay = self.timeOfDay

    -- Search through self.skyColorTimeline and find the current and next timeline items
    local currEvent, nextEvent
    for i = #self.skyColorTimeline, 1, -1 do
        local selectedEvent = self.skyColorTimeline[i]

        if selectedEvent.timestamp <= timeOfDay then
            currEvent = selectedEvent

            if i == #self.skyColorTimeline then
                nextEvent = self.skyColorTimeline[1]
            else
                nextEvent = self.skyColorTimeline[i+1]
            end
            break
        end
    end

    -- Calulcate progress between the two events (accounting for wrapping around the timeline)
    local progress
    if nextEvent.timestamp < currEvent.timestamp then
        progress = (timeOfDay - currEvent.timestamp) / (1.0 - currEvent.timestamp + nextEvent.timestamp)
    else
        progress = (timeOfDay - currEvent.timestamp) / (nextEvent.timestamp - currEvent.timestamp)
    end

    -- print ("Time: " .. timeOfDay, "Progress: " .. progress, "Curr: " .. currEvent.timestamp, "Next: " .. nextEvent.timestamp)

    -- Interpolate between the events to get the sky color
    return {
        tweenFuncs[currEvent.interFunc] (currEvent.color[1], nextEvent.color[1], progress),
        tweenFuncs[currEvent.interFunc] (currEvent.color[2], nextEvent.color[2], progress),
        tweenFuncs[currEvent.interFunc] (currEvent.color[3], nextEvent.color[3], progress)
    }
end

function mapMan:update(dt)
    mapMan.timeOfDay = (mapMan.timeOfDay + dt / mapMan.dayLength) % 1.0
end

function mapMan:toggleSideShading (v)
    assert (type(v) == "boolean", "toggleSideShading expects a boolean value")

    if v ~= self.gfx.sideShading then
        lightingShader:send("sideShadingEnabled", v)
        self.gfx.sideShading = v
    end
end

function mapMan:getAoMulti ()
    return self.gfx.aoMulti
end

function mapMan:setAoMulti (v)
    assert (type(v) == "number" and v >= 0 and v <= 1, "toggleAo expects a number value between 0 and 1")

    if v ~= self.gfx.aoMulti then
        lightingShader:send("aoMulti", v)
        self.gfx.aoMulti = v
    end
end

function mapMan:toggleSmoothLighting (v)
    assert (type(v) == "boolean", "toggleSmoothLighting expects a boolean value")
    
    if v ~= self.gfx.smoothLighting then
        -- Iterate over every chunk and change its filter to nearest or linear based on the smooth lighting setting
        for i = 1, #self.cgrid do
            for j = 1, #self.cgrid[i] do
                local chunk = self.cgrid[i][j]
                if v == true then
                    chunk.lightMap:setFilter("linear", "linear")
                else
                    chunk.lightMap:setFilter("nearest", "nearest")
                end
            end
        end

        self.gfx.smoothLighting = v
    end
end

function mapMan:setMinBrightness (v)
    assert (type(v) == "number", "setMinBrightness expects a number value")
    assert (v >= 0 and v <= 1, "setMinBrightness expects a value between 0 and 1")

    if v ~= self.gfx.minBrightness then
        lightingShader:send("minBrightness", v)
        self.gfx.minBrightness = v
    end
end

function mapMan:setBrightnessMulti (v)
    assert (type(v) == "number", "setBrightnessMulti expects a number value")
    assert (v >= 0, "setBrightnessMulti expects a value greater than or equal to 0")

    if v ~= self.gfx.brightnessMulti then
        lightingShader:send("brightnessMulti", v)
        self.gfx.brightnessMulti = v
    end
end

function mapMan:draw ()
    local cgrid = self.cgrid

    -- Draw any chunks currently on the screen
    local chunksW, chunksH = math.ceil (self.size.w / self.size.cw), math.ceil (self.size.h / self.size.ch)

    local startX, startY = self:tileToChunk (self:screenToTile (0, 0, 1))
    local endX, endY = self:tileToChunk (self:screenToTile (love.graphics.getWidth(), love.graphics.getHeight (), 1))

    startX, startY = lume.clamp (startX, 1, chunksW), lume.clamp (startY, 1, chunksH)
    endX, endY = lume.clamp (endX, 1, chunksW), lume.clamp (endY, 1, chunksH)

    lightingShader:send("skylightColor", self:getExposureColor())

    for i = startX, endX do
        local firstPart = cgrid[i]

        for j = startY, endY, -1 do
            local chunk = firstPart[j]

            if chunk.dirty == true then
                self:remeshChunk (i, j)
                chunk.dirty = false
            elseif chunk.lightMapDirty == true then
                -- A neighboring chunk wrote into this chunk's apron border; no geometry
                -- changed, so just re-upload the light texture instead of a full remesh.
                chunk.lightMap:replacePixels (chunk.lightImageData)
                chunk.lightMapDirty = false
            end

            lightingShader:send("lightMap", chunk.lightMap)
            chunk.model:draw (lightingShader)
        end
    end
end

function mapMan:getDebug ()
    local debugCopy = {}
    for configKey, configValue in pairs (self.debug) do
        debugCopy[configKey] = configValue
    end

    return debugCopy
end

function mapMan:setDebug (config)
    if type (config) == "table" then
        for configKey, configValue in pairs (config) do
            if self.debug[configKey] ~= nil then
                self.debug[configKey] = configValue
            end
        end
    end
end

return mapMan