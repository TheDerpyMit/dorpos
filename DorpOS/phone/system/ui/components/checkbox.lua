--[[  DorpOS :: system/ui/components/checkbox.lua
    Checkbox — tick/untick.

    Props:
        x, y      number
        value     boolean
        onChange  function  Called with (newValue)
        label     string?

    Visual: [x] My Option   or  [ ] My Option
]]
local M = {}
local Theme = require("system.theme.theme")

function M.draw(props)
    local t   = Theme.get()
    local x   = props.x or 1
    local y   = props.y or 1
    local val = props.value

    term.setCursorPos(x, y)
    term.setBackgroundColor(t.bg)
    term.setTextColor(val and t.accent or t.textMuted)
    term.write(val and "[x]" or "[ ]")

    if props.label then
        term.setTextColor(t.text)
        term.write(" " .. props.label)
    end

    return {
        hit = function(mx, my) return my == y and mx >= x and mx < x + 3 end,
        activate = function()
            if props.onChange then props.onChange(not val) end
        end,
    }
end

return M
