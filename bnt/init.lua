local libPath = (...) .. "."
local mapMan = require (libPath .. "mapMan")
local contentUtils = require (libPath .. "contentUtils")

local bnt = {}

function bnt:init (config)
    mapMan:init (config)
    contentUtils:init (config)

    self.map = mapMan
    self.content = contentUtils
end

return bnt