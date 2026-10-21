-- Sets the random seed
math.randomseed(os.time())

-- Sets the image filter and line style so the graphics aren't blurry since we're using pixel art
love.graphics.setDefaultFilter ("nearest", "nearest")
love.graphics.setLineStyle ("rough")

-- Import the required modules and libraries
local g3d = require ("libs.g3d")
local bnt = require ("bnt")
local delayedDraw = require ("libs.delayedDraw")
local tux = require ("libs.tux")
local flux = require ("libs.flux")
local printTable = require ("libs.printTable")
local rta = require ("libs.rta")
local blockDefs = require ("blockDefs")
local tweenFuncs = require ("tweenFuncs")

local showLightMapMode = "off" -- off, bw, color
local showExpoMapMode = "off" -- off, gradient
local renderAtlas = false
local atlasPos = {10, 10}
local atlasMoveStep = 100

tux.callbacks.load () -- Sets up Tux for UI rendering

-- Creates some variables used for stateful Tux UI elements
local timeSliderData = {value = 0, enabled = false}
local aoSliderData = {value = 0, enabled = false}

-- Creates some reusable UI colors for Tux
local tuxColors = {
    red = tux.style.expandColor ({1, 0, 0}, {0.5, 0, 0}),
    white = tux.style.expandColor ({1, 1, 1}, {0.5, 0.5, 0.5}),
}

-- Programmatically defines a cursor texture used to highlight blocks, which is drawn in the love.draw function
-- You could just use a simple rectangle texture loaded from a file instead if you wanted
local cursorEntity
delayedDraw:register (16, 16, function ()
    love.graphics.setColor (1, 1, 1, 1)
    love.graphics.setLineWidth (1)
    love.graphics.rectangle ("line", 1, 1, 15, 15)
    
    -- Create cursor entity
    cursorEntity = bnt.content:newEntity (love.graphics.getCanvas (), 1)
end)

-- Create and set up the block texture atlas, which will be used by BnT
local blockAtlas = rta.newDynamicSize (0, 2, 1)
blockAtlas:setFilter ("nearest")

-- Add the textures used by the blockdefs to the atlas
blockAtlas:add (love.graphics.newImage (love.image.newImageData (1, 1)), "blank")
blockAtlas:add (love.graphics.newImage ("basicBlock.png"), "basicBlock")

-- Hard bake the atlas so it can be used by BnT
blockAtlas:hardBake ()

-- Inits the BnT module with the required config values
bnt:init ({
    g3d = g3d,
    blockAtlas = blockAtlas,
    blockDefs = blockDefs,
    tweenFuncs = tweenFuncs,
    chunkWidth = 25,
    chunkHeight = 25,
})

-- Create the initial map as a 50x25 grid of tiles with 3 layers
-- Note that the map starts out empty
bnt.map:resetMap (50, 25, 3)

-- Fills the map with blocks
-- This can be a bit slow for larger maps because each block update requires skylight/block light data updates
local startGenerationTimestamp = love.timer.getTime ()
local blocksPerChunk = bnt.map.size.cw * bnt.map.size.ch * bnt.map.size.d
local blocksPlaced = 0
local chunksFinished = 0
local startChunkTimestamp = love.timer.getTime ()
for i = 1, bnt.map.size.w do
    for j = 1, bnt.map.size.h do
        for k = 1, bnt.map.size.d do
            bnt.map:placeBlock (i, j, k, "basic")
            blocksPlaced = blocksPlaced + 1
            if blocksPlaced == blocksPerChunk then
                chunksFinished = chunksFinished + 1
                blocksPlaced = 0
                print ("Chunk #" .. chunksFinished .. " finished generating in " .. (love.timer.getTime() - startChunkTimestamp) .. " seconds")
                startChunkTimestamp = love.timer.getTime()
            end
        end
    end
end
print ("Map generation finished in " .. (love.timer.getTime() - startGenerationTimestamp) .. " seconds")

-- Declares / initializes the local variables
local moveStep = 5
local zoomStep = 5

local freeCam = false
local lastCamData = {
    position = g3d.camera.position,
    target = g3d.camera.target,
}

function love.update (dt)
    flux.update (dt)
    tux.callbacks.update (dt)

    local sliderX, sliderY = 15, 550
    local sliderW, sliderH = 350, 50
    tux.show.slider ({
        data = timeSliderData,
        colors = timeSliderData.enabled == false and tuxColors.red or nil,
    }, sliderX, sliderY, sliderW, sliderH)
    if timeSliderData.enabled == true then
        bnt.map.timeOfDay = timeSliderData.value
    else
        timeSliderData.value = bnt.map.timeOfDay
    end

    -- Show markers for the sky color timeline events on the slider
    for index, event in ipairs(bnt.map.skyColorTimeline) do
        local markerX = sliderX + event.timestamp * sliderW
        tux.show.label ({
            text = "",
            align = "center",
            valign = "center",
        }, markerX, sliderY, 2, sliderH)
    end

    local sliderX, sliderY = 15, 485
    local sliderW, sliderH = 150, 50
    aoSliderData.value = bnt.map:getAoMulti() -- Update the slider value to match the current AO multiplier
    tux.show.slider ({
        data = aoSliderData,
    }, sliderX, sliderY, sliderW, sliderH)
    bnt.map:setAoMulti(aoSliderData.value)

    -- Convert the time of day (0-1) to a string (HH:MMam/pm, 12hr) for display
    local hours = math.floor(bnt.map.timeOfDay * 24)
    local minutes = math.floor((bnt.map.timeOfDay * 24 - hours) * 60)
    local ampm = "am"
    if hours >= 12 then
        ampm = "pm"
        if hours > 12 then
            hours = hours - 12
        end
    elseif hours == 0 then
        hours = 12
    end
    local timeString = string.format("%02d:%02d%s", hours, minutes, ampm)
    tux.show.label ({
        text = timeString,
        align = "center",
        valign = "center",
        oalign = "right",
        voalign = "bottom",
    }, -75, -35, 65, 25)

    local moveMulti = 1
    if love.keyboard.isDown ("lshift") then
        moveMulti = 2
    elseif love.keyboard.isDown("lctrl") then
        moveMulti = 0.10
    end

    -- Camera
    if freeCam == true then
        g3d.camera.firstPersonMovement(dt)
    else
        if love.keyboard.isDown("w") then
            bnt.map:adjustCam(0, moveStep * moveMulti * dt, 0)
        end
        if love.keyboard.isDown("s") then
            bnt.map:adjustCam(0, -moveStep * moveMulti * dt, 0)
        end
            
        if love.keyboard.isDown("a") then
            bnt.map:adjustCam(-moveStep * moveMulti * dt, 0, 0)
        end
        if love.keyboard.isDown("d") then
            bnt.map:adjustCam(moveStep * moveMulti * dt, 0, 0)
        end

        if love.keyboard.isDown("e") then
            bnt.map:adjustCam(0, 0, -zoomStep * moveMulti * dt)
        end
        if love.keyboard.isDown("q") then
            bnt.map:adjustCam(0, 0, zoomStep * moveMulti * dt)
        end
    end

    -- Texture atlas movement
    local shiftHeld = love.keyboard.isDown("rshift")

    if love.keyboard.isDown ("n") then
        if shiftHeld then
            atlasPos[1] = atlasPos[1] + atlasMoveStep * moveMulti * dt
        else
            atlasPos[1] = atlasPos[1] - atlasMoveStep * moveMulti * dt
        end
    end
    
    if love.keyboard.isDown ("m") then
        if shiftHeld then
            atlasPos[2] = atlasPos[2] + atlasMoveStep * moveMulti * dt
        else
            atlasPos[2] = atlasPos[2] - atlasMoveStep * moveMulti * dt
        end
    end

    bnt.map:update (dt)
end

-- TEMP
local lightMapViewerShdr = [[
// Pixels with any non-alpha > 0 will be white, everything else is black
vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    vec4 texcolor = Texel(texture, texture_coords);
    // If the pixel is not transparent, override it with white
    if (texcolor.r > 0.0 || texcolor.g > 0.0 || texcolor.b > 0.0) {
        return vec4(1.0, 1.0, 1.0, 1.0) * color;
    }
    else {
        return vec4(0.0, 0.0, 0.0, 1.0) * color;
    }
}
]]
local lightMapViewerShader = love.graphics.newShader(lightMapViewerShdr)

local lightMapViewerShdrColored = [[
// Pixels are rendered as if alpha is always 1.0
vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    vec4 texcolor = Texel(texture, texture_coords);
    
    return vec4(texcolor.rgb, 1.0) * color;
}
]]
local lightMapViewerShaderColored = love.graphics.newShader(lightMapViewerShdrColored)

local expoMapViewerShader = love.graphics.newShader([[
    // Outputs intensity based on alpha
    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        vec4 texcolor = Texel(texture, texture_coords);
        
        // Convert the RGB values to a grayscale value based on the alpha channel (exposure)
        float exposure = texcolor.a;
        return vec4(exposure, exposure, exposure, 1.0);
    }
]])

function love.draw ()
    delayedDraw:draw ()
    tux.callbacks.draw ()

    love.graphics.setBackgroundColor ({0, 0, 1, 1})

    bnt.map:draw ()

    -- Renders the crosshair
    love.graphics.setColor (1, 1, 1, 1)
    love.graphics.line (290, 300, 310, 300)
    love.graphics.line (300, 290, 300, 310)

    -- Shows the FPS
    love.graphics.print("Current FPS: "..tostring(love.timer.getFPS( )), 10, 10)

    -- Shows the tile the cursor is over
    local mouseX, mouseY = love.mouse.getPosition ()
    local tileX, tileY, layer = bnt.map:autoScreenToTile (mouseX, mouseY)
    love.graphics.print("Tile under cursor: (" .. tostring (tileX) .. ", " .. tostring (tileY) .. ")", 10, 40)

    -- Show number of draw calls
    love.graphics.print("Draw calls: " .. tostring(love.graphics.getStats().drawcalls), 10, 60)

    -- Tile cursor
    if bnt.map:inBounds (tileX, tileY) then
        cursorEntity:setTransform ({tileX + 0.5, tileY, -layer + 1.0001})
        cursorEntity:draw ()
    end

    -- TEMP: Show a rectangle with the current sky color
    local skyColor = bnt.map:getExposureColor()
    love.graphics.setColor (skyColor)
    love.graphics.rectangle ("fill", 550, 0, 50, 50)

    -- Shows the render atlas
    if renderAtlas == true and blockAtlas ~= nil and blockAtlas.image ~= nil then
        love.graphics.draw (blockAtlas.image, atlasPos[1], atlasPos[2])
    end

    -- Shows the chunk lightmap
    if showLightMapMode ~= "off" and bnt.map:inBounds (tileX, tileY) == true then
        local chunkX, chunkY = bnt.map:tileToChunk (tileX, tileY)
        local chunk = bnt.map.cgrid[chunkX][chunkY]

        if showLightMapMode == "bw" then
            love.graphics.setShader (lightMapViewerShader)
        elseif showLightMapMode == "color" then
            love.graphics.setShader (lightMapViewerShaderColored)
        end
        love.graphics.setColor (1, 1, 1, 1)
        love.graphics.draw (chunk.lightMap, 0, chunk.lightMap:getHeight() * 5, nil, 5, -5)
        love.graphics.setShader()
    end

    -- Shows the chunk exposure map
    if showExpoMapMode ~= "off" and bnt.map:inBounds (tileX, tileY) == true then
        local chunkX, chunkY = bnt.map:tileToChunk (tileX, tileY)
        local chunk = bnt.map.cgrid[chunkX][chunkY]

        love.graphics.setShader(expoMapViewerShader)
        love.graphics.setColor (1, 1, 1, 1)
        love.graphics.draw (chunk.lightMap, 0, chunk.lightMap:getHeight() * 5, nil, 5, -5)
        love.graphics.setShader()
    end
end

function love.keypressed (key, scancode, isrepeat)
    tux.callbacks.keypressed (key, scancode, isrepeat)

    if key == "f1" then
        bnt.map.debug.drawHitboxes = not bnt.map.debug.drawHitboxes

    elseif key == "f2" then
        bnt.map.debug.drawLightValues = not bnt.map.debug.drawLightValues
    
    -- Toggles freecam
    elseif key == "f3" then
        freeCam = not freeCam

        if freeCam == true then
            lastCamData.position = {unpack(g3d.camera.position)}
            lastCamData.target = {unpack(g3d.camera.target)}

            print ("Freecam enabled")
        else
            g3d.camera.position = lastCamData.position
            g3d.camera.target = lastCamData.target
            g3d.camera.updateViewMatrix()
            g3d.camera.updateProjectionMatrix()

            print ("Freecam disabled")
        end
    
    -- Prints tile info
    elseif key == "f4" then
        local tileX, tileY = bnt.map:autoScreenToTile (love.mouse.getPosition())

        if bnt.map:inBounds (tileX, tileY) then
            local tile = bnt.map.grid[tileX][tileY]

            print ("Tile at (" .. tileX .. ", " .. tileY .. "):")
            -- print ("ID: " .. tile.fg.def.id)
            -- for face, enabled in pairs (tile.activeFaces) do
            --     print (face, enabled)
            -- end
            print ("Lighting color: " .. tile.combinedLightColor[1] .. ", " .. tile.combinedLightColor[2] .. ", " .. tile.combinedLightColor[3])
            print ("Sky exposure: " .. tile.combinedLightColor[4])

        else
            print ("Tile out of bounds")
        end
    
    -- Toggle texture atlas rendering
    elseif key == "f5" then
        renderAtlas = not renderAtlas
        atlasPos = {10, 10}

        if renderAtlas == false then
            print ("Texture atlas rendering disabled")
        else
            print ("Texture atlas rendering enabled")

            if blockAtlas == nil or blockAtlas.image == nil then
                print ("No texture atlas available")
            end
        end

    -- Toggle showing the light map for the chunk under the cursor
    elseif key == "f6" then
        if love.keyboard.isDown ("lshift", "rshift") then
            if showExpoMapMode == "off" then
                showExpoMapMode = "gradient"
                print ("Exposure map viewer enabled (gradient)")
            elseif showExpoMapMode == "gradient" then
                showExpoMapMode = "off"
                print ("Exposure map viewer disabled")
            end
        else
            if showLightMapMode == "off" then
                showLightMapMode = "bw"
                print ("Light map viewer enabled (black & white)")
            elseif showLightMapMode == "bw" then
                showLightMapMode = "color"
                print ("Light map viewer enabled (color)")
            else
                showLightMapMode = "off"
                print ("Light map viewer disabled")
            end
        end

    elseif key == "f7" then
        if love.keyboard.isDown ("lshift", "rshift") then
            print ("Enabling ambient occlusion...")
            bnt.map:setAoMulti (1)
        else
            print ("Disabling ambient occlusion...")
            bnt.map:setAoMulti (0)
        end

    elseif key == "f8" then
        if love.keyboard.isDown ("lshift", "rshift") then
            print ("Enabling smooth lighting...")
            bnt.map:toggleSmoothLighting (true)
        else
            print ("Disabling smooth lighting...")
            bnt.map:toggleSmoothLighting (false)
        end

    elseif key == "f9" then
        if love.keyboard.isDown ("lshift", "rshift") then
            print ("Enabling side shading...")
            bnt.map:toggleSideShading (true)
        else
            print ("Disabling side shading...")
            bnt.map:toggleSideShading (false)
        end

    elseif key == "p" then
        if timeSliderData.enabled == false then
            timeSliderData.enabled = true
            print ("Time slider enabled")
            timeSliderData.value = bnt.map.timeOfDay
        else
            timeSliderData.enabled = false
            print ("Time slider disabled")
        end
    end
end

function love.mousepressed (x, y, button)
    if button == 1 then -- Left mouse button
        if tux.utils.itemHovered () == false then
            local tileX, tileY = bnt.map:autoScreenToTile (x, y)
            local layer = bnt.map:getTopmostLayer (tileX, tileY) or 4
            layer = layer - 1

            if layer > 0 then
                if love.keyboard.isDown("lshift") then
                    if bnt.map:inBounds (tileX, tileY) then
                        local lightColor = {math.random (), math.random (), math.random ()}
                        -- local lightColor = {1, 1, 1}
                        print ("Placed light: ", bnt.map:placeLight (tileX, tileY, 5, lightColor, 15))
                        print ("Light color: ", lightColor[1], lightColor[2], lightColor[3])
                    end

                elseif love.keyboard.isDown("lctrl") then
                    if bnt.map:inBounds (tileX, tileY) then
                        -- Set sky exposure to 1.0
                        local tile = bnt.map.grid[tileX][tileY]
                        tile.skyExposure = 1.0
                        print ("Set sky exposure to 1.0 for tile: ", tileX, tileY)
                    end

                else
                    print ("Placed block: ", bnt.map:placeBlock (tileX, tileY, layer, "basic"))
                end
            end
        end

    elseif button == 2 then -- Right mouse button
        if tux.utils.itemHovered () == false then
            local tileX, tileY = bnt.map:autoScreenToTile (x, y)
            local layer = bnt.map:getTopmostLayer (tileX, tileY) or 3

            if love.keyboard.isDown("lshift") then
                if bnt.map:inBounds (tileX, tileY) then
                    print ("Removed light: ", bnt.map:removeLight (tileX, tileY))
                end

            elseif love.keyboard.isDown("lctrl") then
                    if bnt.map:inBounds (tileX, tileY) then
                        -- Set sky exposure to 0.0
                        local tile = bnt.map.grid[tileX][tileY]
                        tile.skyExposure = 0.0
                        print ("Set sky exposure to 0.0 for tile: ", tileX, tileY)
                    end

            else
                print ("Removed block: ", bnt.map:removeBlock (tileX, tileY, layer))
            end
        end

    elseif button == 3 then
        local tileX, tileY = bnt.map:autoScreenToTile (x, y)
        
        if love.keyboard.isDown ("lshift", "rshift") then
            -- TEMP: Manually change a lightmap color to red with max sky exposure
            -- Get the chunk coordinates for the tile
            local chunkX, chunkY = bnt.map:tileToChunk (tileX, tileY)
            local chunk = bnt.map.cgrid[chunkX][chunkY]
            local lightImageData = chunk.lightImageData

            -- Set the pixel at the tile's position in the chunk. Keep in mind that it starts at 0, 0
            lightImageData:setPixel ((tileX - 1) % bnt.map.size.cw, (tileY - 1) % bnt.map.size.ch, 255, 0, 0, 128)
            chunk.dirty = true

        elseif love.keyboard.isDown ("lctrl", "rctrl") then
            print ("Lighting data for tile at (" .. tileX .. ", " .. tileY .. "):")
            local color = bnt.map:getLightColor (tileX, tileY)
            local exposure = bnt.map:getSkyExposure (tileX, tileY)
            print ("Combined Light Color: ", color[1], color[2], color[3])
            print ("Sky Exposure: ", exposure)
            print ()
        else
            if bnt.map:inBounds (tileX, tileY) then
                printTable ("Tile at (" .. tileX .. ", " .. tileY .. ")", bnt.map.grid[tileX][tileY], {
                    blockDef = true,
                    blockObj = true,
                    def = true,
                })
            end
        end
    end
end

function love.textinput (text)
    tux.callbacks.textinput (text)
end