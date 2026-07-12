--[[  DorpOS :: system/ui/components/textbox.lua
    Single-line text input with cursor, optional password masking.

    Props:
        x, y        number
        width       number
        value       string   Current text value
        placeholder string?  Shown when value is empty
        password    boolean? Masks characters with *
        focused     boolean? Shows cursor when true
        fg, bg      number?

    Returns a draw result table (not interactive — caller manages input).
    To capture keyboard input use the on-screen keyboard component or
    handle char/key events in the app's event loop.
]]
local M = {}
local Theme = require("system.theme.theme")
local utils = require("system.utils.utils")

function M.draw(props)
    local t   = Theme.get()
    local x   = props.x     or 1
    local y   = props.y     or 1
    local w   = props.width or 16
    local val = props.value or ""
    local fg  = props.fg or t.text
    local bg  = props.bg or t.bgInput

    -- Trim display to fit width (right-align cursor into view)
    local display
    if props.password then
        display = string.rep("*", #val)
    else
        display = val
    end
    -- Only show last (w-1) chars so cursor fits
    if #display >= w then
        display = display:sub(#display - w + 2)
    end

    term.setCursorPos(x, y)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    term.write(utils.padRight(display, w))

    -- Placeholder
    if #val == 0 and props.placeholder then
        term.setCursorPos(x, y)
        term.setTextColor(t.textMuted)
        term.write(utils.padRight(props.placeholder, w))
    end

    -- Cursor
    if props.focused then
        local cx = x + math.min(#display, w - 1)
        term.setCursorPos(cx, y)
        term.setCursorBlink(true)
    else
        term.setCursorBlink(false)
    end
end

return M
