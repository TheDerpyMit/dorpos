--[[  DorpOS :: system/ui/components/spinner.lua
    Animated loading spinner — single frame draw.
    Advance `frame` each tick from the animation engine.

    Props:
        x, y    number
        frame   number   Tick counter (mod FRAMES internally)
        fg      number?
        bg      number?
        label   string?  Optional text after spinner char
]]
local M = {}
local Theme = require("system.theme.theme")

local FRAMES = { "|", "/", "-", "\\" }

function M.draw(props)
    local t  = Theme.get()
    local fr = FRAMES[((props.frame or 0) % #FRAMES) + 1]
    local fg = props.fg or t.accent
    local bg = props.bg or t.bg

    term.setCursorPos(props.x or 1, props.y or 1)
    term.setTextColor(fg)
    term.setBackgroundColor(bg)
    term.write(fr .. (props.label and (" " .. props.label) or ""))
end

return M
