# Blocks N Things

Blocks N Things (BnT) is a module that allows you to create voxel worlds with ease for 2D games. It works with G3D to efficently render chunks of blocks to the screen.

You can sample the module by downloading this repo and running the project from main.lua. If you'd like to use BnT in your own project, you can follow main.lua as a rough guide for setting up and using the module. If you prefer straight documentation, that will be provided later in this README.


## Main Features
- Easily create and render voxel worlds for your games.
- Supports colored lights, sky lighting, and custom daylight cycles.
- Maps are split into chunks for better performance. Only chunks on the screen are rendered and chunks are only remeshed when needed.
- Works with G3D, making it very easy to add custom 3D models to a voxel world.
- Provides a utility for creating billboarded 2D entities.


## Limitations:
- This module is optimized for 2D games. While there is no limit on the depth of the world (aka the number of layers in the 3rd dimension), the module is optimized strictly for 2D performance. Thus, your mileage may vary if you use a large world depth.
- The module does not handle collisions, hitboxes, or animations. You must create and hook up those systems yourself.
- Block defs are not validated by the module. You will need to design systems to create and validate these defs yourself. The block def spec can be found later in this README.
- You will need to understand how to use the required libraries and modules in order to use BnT.


## Required Libraries and Modules
BnT requires the following libraries and modules to function. You must install and set these up yourself.
- [Runtime-TextureAtlas (RTA)](https://github.com/EngineerSmith/Runtime-TextureAtlas) (Texture Atlas used for blocks in chunks)
- [g3d](https://github.com/groverburger/g3d) (Used for 3D rendering)

[flux](https://github.com/rxi/flux) is also recommended, as it provides tweening functions that are helpful for defining custom daylight cycles.


## Block Def Spec
- **id:** A unique identifier for the block
- **name:** A human-friendly name for the block
- **desc:** A short description of the block
- **textureIds:** A dictionary of RTA IDs keyed by the block faces (required keys are "front", "back", "left", "right", "top", and "bottom")

### Notes About Block Defs
- You MUST include a def for a block with id = "air"

## API
*COMING SOON*

# Credits
Aside from the required libraries and modules, BnT also includes the following items as part of the module itself:
- [lume](https://github.com/rxi/lume)
- Auto2DArray
- mapToScale