local Auto2DArray = {}

function Auto2DArray:new (defaultValue)
    local newArr = {}

    setmetatable (newArr, {
        __index = function (tbl, key)
            local innerTbl = {}
            rawset (tbl, key, innerTbl)

            return innerTbl
        end,
    })

    return newArr
end

return Auto2DArray