# Blocks N Things

Blocks N Things is a module that allows you to create voxel worlds with ease for 2D games. It works with G3D to efficently render chunks of blocks to the screen.


**Main Features**
- Easily create and render voxel worlds for your games.
- Supports colored lights, sky lights, and custom daylight cycles.
- Maps are split into chunks for better performance. Only chunks on the screen are rendered and chunks are only remeshed when needed.
- Works with G3D, making it very easy to add custom 3D models to a voxel world.
- Provides a utility for creating billboarded 2D entities.


**Limitations:**
- This module is optimized for 2D games. While there is no limit of the depth of the world (aka the number of layers in the 3rd dimension), the module is optimized strictly for 2D performance. Thus, your mileage may vary if you use a large world depth.
- The module does not handle collisions, hitboxes, or animations. You must create and hook up those systems yourself.