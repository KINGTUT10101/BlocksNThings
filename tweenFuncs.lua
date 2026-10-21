local flux = require ("libs.flux")

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function resolveInterFunc(interFunc)
    if type(interFunc) == "function" then
        return interFunc
    end
    if type(interFunc) == "string" and flux.easing[interFunc] then
        local ease = flux.easing[interFunc]
        return function(a, b, t)
            local eased = ease(t)
            return lerp(a, b, eased)
        end
    end
    return lerp
end

local tweenFuncs = {
    linear = resolveInterFunc("linear"),
    easeInExpo = resolveInterFunc("easeInExpo"),
    easeOutExpo = resolveInterFunc("easeOutExpo"),
}

return tweenFuncs