# Blocks N Things

Blocks N Things (BnT) is a module that allows you to create voxel worlds with ease for 2.5D games. It works with G3D to efficently render chunks of blocks to the screen.

You can sample the module by downloading this repo and running the project from main.lua. If you'd like to use BnT in your own project, you can follow main.lua as a rough guide for setting up and using the module. If you prefer straight documentation, that will be provided later in this README.


## Main Features
- Easily create and render voxel worlds for your games.
- Supports colored lights, sky lighting, and custom daylight cycles.
- Uses a custom lighting algorithm which ensures that light cannot "leak" through walls into other rooms.
- Maps are split into chunks for better performance. Only chunks on the screen are rendered and chunks are only remeshed when needed.
- Works with G3D, making it very easy to add custom 3D models to a voxel world.
- Provides a utility for creating billboarded 2D entities.


## Limitations:
- This module is optimized for 2D games. While there is no limit on the depth of the world (aka the number of layers in the 3rd dimension), the module is optimized strictly for 2D performance. Thus, your mileage may vary if you use a large world depth.
- The module does not handle collisions, hitboxes, or animations. You must create and hook up those systems yourself.
- Block defs are not validated by the module. You will need to design systems to create and validate these defs yourself. The block def spec can be found later in this README.
- You will need to understand how to use the required libraries and modules in order to use BnT.

## Upcoming Features
- API docs.
- An open-source environment editor where you can easily create environments with custom blocks and entities.


## Required Libraries and Modules
BnT requires the following libraries and modules to function. You must install and set these up yourself.
- [Runtime-TextureAtlas (RTA)](https://github.com/EngineerSmith/Runtime-TextureAtlas) (Texture atlas used for blocks in chunks)
- [g3d](https://github.com/groverburger/g3d) (Used for 3D rendering)

[flux](https://github.com/rxi/flux) is also recommended, as it provides tweening functions that are helpful for defining custom daylight cycles.


## Setting Up BnT
The following is a rough description of how you should set up BnT.

Start by copying the "bnt" folder into your LOVE2D project. Then import BnT and the required packages like so:
```lua
local bnt = require ("bnt")
local g3d = require ("g3d")
local rta = require ("rta")
```
After that, you should create an RTA like so and add your block textures to it:
```lua
local blockAtlas = rta.newDynamicSize (0, 2, 1) -- Dynamic mode is not required, but is recommended for ease of use
blockAtlas:setFilter ("nearest") -- Recommended if your textures are pixel art

-- Add the textures used by the blockdefs to the atlas (we're adding 2 in this example)
-- Used by air block
blockAtlas:add (love.graphics.newImage (love.image.newImageData (1, 1)), "blank")
-- Used by basic block
blockAtlas:add (love.graphics.newImage ("basicBlock.png"), "basicBlock")

-- Hard bake the atlas so it can be used by BnT
blockAtlas:hardBake ()
```
Next, you need to define your block defs like so. Note that you are required to have at least one block def with id = "air".
```lua
local blockDefs = {
    air = {
        id = "air",
        name = "Air",
        desc = "An empty space.",
        textureIds = {
            front = "blank",
            top = "blank",
            bottom = "blank",
            left = "blank",
            right = "blank",
        },
    },
    basic = {
        id = "basic",
        name = "Basic Block",
        desc = "A basic block for testing.",
        textureIds = {
            front = "basicBlock",
            top = "basicBlock",
            bottom = "basicBlock",
            left = "basicBlock",
            right = "basicBlock",
        },
    },
}
```
We also need to provide some tweening functions. The default sky color timeline requires you to at least define one function called "linear". These should be stored in a dictionary.

It is recommended that you use flux or another tweening library for this. View the file named "tweenFuncs.lua" for an example of how you can generate a tweenFuncs table from flux that is compatible with BnT.
```lua
-- This is a simple example of a tweenFuncs table
local tweenFuncs = {}
tweenFuncs.linear = function (start, target, alpha)
    return start + (target - start) * alpha
end
```
Now we can finally initialize the bnt module:
```lua
bnt:init ({
    -- REQUIRED
    g3d = g3d, -- Ref to the g3d module
    blockAtlas = blockAtlas, -- Ref to the block atlas that stores our block textures
    blockDefs = blockDefs, -- Ref to the table that stores our block definitions
    tweenFuncs = tweenFuncs, -- Ref to the dict containing the tweening funcs

    -- OPTIONAL
    chunkWidth = 50, -- Width of each chunk
    chunkHeight = 50, -- Height of each chunk
    maxLightLevel = 15, -- Max block light level
    maxExposure = 5, -- Max sky light level
    dayLength = 120, -- Length of an in-game day in seconds
})
```
Note that BnT does not prevent you from modifying the blockAtlas, blockDefs, or tweenFuncs after their references have been handed over. However, you should do this with great caution, as careless modifications to any of those items may trigger a crash unless the modifications are properly handled.

Anyway, now that BnT is set up, you should create a map before you try to place/remove any blocks.
```lua
local mapWidth, mapHeight, mapDepth = 50, 25, 3
bnt.map:resetMap (mapWidth, mapHeight, mapDepth)
```
Finally, you will need to add the callbacks for BnT.
```lua
function love.update (dt)
    -- Other code goes here

    bnt.map:update (dt)

    -- Other code goes here
end

function love.draw ()
    -- Other code goes here

    bnt.map:draw ()

    -- Other code goes here
end
```
This is enough to get your project started. If you follow this guide, you will have a blank map filled with air blocks (aka the screen will be blank). If you'd like to do things like control the camera, add blocks when you click, generate maps, show a cursor, and other such things, please refer to the API and the example code in main.lua.


## Block Def Spec
- **id (any):** A unique identifier for the block
- **name (string):** A human-friendly name for the block
- **desc (string):** A short description of the block
- **transparent (boolean):** Determines whether the block is considered transparent which changes how it is rendered
- **textureIds:** A dictionary of RTA IDs keyed by the block faces (required keys are "front", "back", "left", "right", "top", and "bottom")


### Notes About Block Defs
- You MUST include a def for a block with id = "air"


## API
*COMING SOON*


## Credits
Aside from the required libraries and modules, BnT also includes the following items as part of the module itself:
- [lume](https://github.com/rxi/lume)
- Auto2DArray
- mapToScale