--[[  DorpOS :: system/ui/components/switch.lua
    Toggle switch (on/off).

    Props:
        x, y      number
        value     boolean   Current state
        onChange  function  Called with (newValue)
        label     string?   Text to the right of the switch

    Returns hit area table.
    Visual:  [ON ] or [OFF]
]]
local M = {}
local Theme = require("system.theme.theme")

function M.draw(props)
    local t   = Theme.get()
    local x   = props.x or 1
    local y   = props.y or 1
    local val = props.value

    local bg = val and t.accent or t.bgCard
    local fg = val and t.textOnAccent or t.textMuted
    local lbl = val and "ON " or "OFF"

    term.setCursorPos(x, y)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    term.write("[" .. lbl .. "]")

    if props.label then
        term.setBackgroundColor(t.bg)
        term.setTextColor(t.text)
        term.write(" " .. props.label)
    end

    return {
        hit = function(mx, my) return my == y and mx >= x and mx < x + 5 end,
        activate = function()
            if props.onChange then props.onChange(not val) end
        end,
    }
end

return M
