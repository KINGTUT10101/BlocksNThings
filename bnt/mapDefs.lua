local ffi = require ("ffi")

ffi.cdef([[
    typedef struct {
        float x, y, z;
        float u, v;
        float nx, ny, nz;
        uint8_t r, g, b, a;
    } Vertex;

    typedef struct {
        int pos[2];
        uint8_t radius;
        float color[3];
        double maxLevel;
    } LightSource;
]])


ffi.cdef ([[
    typedef struct {
        int index;
        float colorMulti;
        int verts[6][5];
    } Face;
    
    typedef struct {
        Face front;
        Face left;
        Face right;
        Face top;
        Face bottom;
    } CubeData;
]])

-- Each face contains data for 6 verts (since each face requires 2 tris and each tri requires 3 verts)
-- Each subtable contains an array of values corresponding to x, y, z, u, and v coordinates
local cubeData = ffi.new("CubeData", {
    front = {
        index = 0,
        colorMulti = 1.0,
        verts = {
            {0, 0, 0, 0, 1},
            {1, 0, 0, 1, 1},
            {0, 1, 0, 0, 0},
            {1, 1, 0, 1, 0},
            {1, 0, 0, 1, 1},
            {0, 1, 0, 0, 0},
        },
    },
    left = {
        index = 1,
        colorMulti = 0.6,
        verts = {
            {0, 0, -1, 0, 1},
            {0, 0, 0, 1, 1},
            {0, 1, -1, 0, 0},
            {0, 1, 0, 1, 0},
            {0, 0, 0, 1, 1},
            {0, 1, -1, 0, 0},
        },
    },
    right = {
        index = 2,
        colorMulti = 0.6,
        verts = {
            {1, 0, 0, 0, 1},
            {1, 0, -1, 1, 1},
            {1, 1, 0, 0, 0},
            {1, 1, -1, 1, 0},
            {1, 0, -1, 1, 1},
            {1, 1, 0, 0, 0},
        },
    },
    top = {
        index = 3,
        colorMulti = 0.8,
        verts = {
            {0, 1, -1, 0, 0},
            {1, 1, -1, 1, 0},
            {0, 1, 0, 0, 1},
            {1, 1, 0, 1, 1},
            {1, 1, -1, 1, 0},
            {0, 1, 0, 0, 1},
        },
    },
    bottom = {
        index = 4,
        colorMulti = 0.8,
        verts = {
            {0, 0, -1, 0, 1},
            {1, 0, -1, 1, 1},
            {0, 0, 0, 0, 0},
            {1, 0, 0, 1, 0},
            {1, 0, -1, 1, 1},
            {0, 0, 0, 0, 0},
        },
    },
})

return cubeData