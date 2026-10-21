--- Maps numbers from one scale to another.
--- @param input number The input value to be scaled.
--- @param inMin number The min value of the input value scale.
--- @param inMax number The max value of the input value scale.
--- @param outMin number The min value of the output value scale.
--- @param outMax number The max value of the output value scale.
--- @return number output The scaled output value.
local function mapToScale (input, inMin, inMax, outMin, outMax) 
    return (input - inMin) * (outMax - outMin) / (inMax - inMin) + outMin;
end

return mapToScale