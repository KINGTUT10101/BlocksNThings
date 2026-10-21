--- Recursively prints a table, including its data types, keys, and values.
--- Handles nested tables and avoids printing keys listed in a blacklist.
--- @param key any The key associated with the provided value. Defaults to the value itself if not provided.
--- @param value any The value associated with the provided key. Can be of any Lua type, including tables.
--- @param blacklist table<any, boolean|table>? A table containing keys to exclude from printing. Keys can map to:
--- - `boolean`: Exclude the key entirely when set to true.
--- - `table`: Sub-blacklist for recursive filtering.
local function printTable(key, value, blacklist, prefix)
    key = key or value
    blacklist = blacklist or {}
    prefix = prefix or ""

    -- If this exact key is blacklisted (true), skip printing entirely
    local blEntry = blacklist[key]
    if blEntry == true then return end

    if type(value) == "table" then
        -- Print the current table node
        print(prefix .. type(value), key, value)

        -- Determine the blacklist to use for children:
        -- - If there's a sub-blacklist at this key, prefer those entries but fall back to the current blacklist
        -- - Otherwise, pass the same blacklist down so top-level filters still apply at any depth
        local childBlacklist
        if type(blEntry) == "table" then
            local subBlacklist = blEntry
            childBlacklist = setmetatable({}, {
                __index = function(_, k)
                    local v = subBlacklist[k]
                    if v ~= nil then return v end
                    return blacklist[k]
                end,
            })
        else
            childBlacklist = blacklist
        end

        for childKey, childValue in pairs(value) do
            printTable(childKey, childValue, childBlacklist, prefix .. "  ")
        end
    else
        print(prefix .. type(value), key, value)
    end
end

return printTable
