local delayedDraw = {
    drawCalls = {}
}

function delayedDraw:register (x, y, drawFunc)
    table.insert (self.drawCalls, {
        draw = drawFunc,
        canvas = love.graphics.newCanvas (x, y)
    })
end

function delayedDraw:draw ()
    local origCanvas = love.graphics.getCanvas ()

    for _, drawCall in ipairs (self.drawCalls) do
        love.graphics.setCanvas (drawCall.canvas)
        love.graphics.clear ()
        drawCall.draw ()
    end

    love.graphics.setCanvas (origCanvas)

    self.drawCalls = {}
end

return delayedDraw