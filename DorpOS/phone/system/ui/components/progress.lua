--[[  DorpOS :: system/ui/components/progress.lua
    Horizontal progress bar.

    Props:
        x, y      number
        width     number
        value     number   Current value
        max       number   Maximum value (default 100)
        fg        number?  Filled bar colour
        bg        number?  Empty bar colour
        showText  boolean? Show "45%" text in the centre
]]
local M = {}
local Theme = require("system.theme.theme")

function M.draw(props)
    local t    = Theme.get()
    local x    = props.x     or 1
    local y    = props.y     or 1
    local w    = props.width or 20
    local val  = props.value or 0
    local max_ = props.max   or 100
    local fg   = props.fg    or t.accent
    local bg   = props.bg    or t.bgCard

    local frac = math.max(0, math.min(1, val / max_))
    local fill = math.floor(frac * w)

    term.setCursorPos(x, y)
    term.setBackgroundColor(fg)
    term.write(string.rep(" ", fill))
    term.setBackgroundColor(bg)
    term.write(string.rep(" ", w - fill))

    if props.showText then
        local pct = math.floor(frac * 100) .. "%"
        local tx  = x + math.floor((w - #pct) / 2)
        term.setCursorPos(tx, y)
        term.setBackgroundColor(fill >= math.floor(w / 2) and fg or bg)
        term.setTextColor(t.textOnAccent)
        term.write(pct)
    end
end

return M
