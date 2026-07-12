--[[  DorpOS :: system/ui/components/popup.lua
    A non-blocking overlay panel (e.g. dropdown, context menu).

    Props:
        x, y          number
        width         number
        height        number
        drawContent   function  Called with the window handle
        bg            number?
]]
local M = {}
local Theme = require("system.theme.theme")

function M.draw(props)
    local t   = Theme.get()
    local x   = props.x      or 1
    local y   = props.y      or 1
    local w   = props.width  or 14
    local h   = props.height or 6
    local bg  = props.bg or t.bgCard

    local win = window.create(term.current(), x, y, w, h, true)
    win.setBackgroundColor(bg)
    win.clear()

    if props.drawContent then
        local saved = term.redirect(win)
        props.drawContent(win)
        term.redirect(saved)
    end

    return win
end

return M
