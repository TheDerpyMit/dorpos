--[[  DorpOS :: system/ui/components/label.lua  ]]
local M = {}
local Theme = require("system.theme.theme")
local utils = require("system.utils.utils")

--[[
    Props:
        x, y    number
        text    string
        fg      number?  (default theme.text)
        bg      number?  (default theme.bg)
        align   string?  "left"|"center"|"right" (default "left")
        width   number?  Used for alignment
        muted   boolean? Uses textMuted colour
]]
function M.draw(props)
    local t   = Theme.get()
    local txt = tostring(props.text or "")
    local fg  = props.fg or (props.muted and t.textMuted or t.text)
    local bg  = props.bg or t.bg
    local w   = props.width

    local out
    if w then
        if props.align == "center" then
            out = utils.centre(txt, w)
        elseif props.align == "right" then
            out = utils.padLeft(txt, w)
        else
            out = utils.padRight(txt, w)
        end
    else
        out = txt
    end

    term.setCursorPos(props.x or 1, props.y or 1)
    term.setTextColor(fg)
    term.setBackgroundColor(bg)
    term.write(out)
end

return M
