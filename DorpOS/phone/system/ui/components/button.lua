--[[  DorpOS :: system/ui/components/button.lua  ]]
local M = {}
local Theme = require("system.theme.theme")
local C     = require("shared.constants")

--[[
    Props:
        x, y        number   Position
        width       number   Width (default: #label + 2)
        label       string   Button text
        onClick     function Called on click (no args)
        disabled    boolean  Grays out and ignores clicks
        style       string   "primary"|"danger"|"ghost" (default "primary")
        icon        string?  Single char prepended to label
]]
function M.draw(props)
    local t   = Theme.get()
    local lbl = (props.icon and props.icon .. " " or "") .. (props.label or "")
    local w   = props.width or (#lbl + 2)
    local x   = props.x or 1
    local y   = props.y or 1

    -- Colour selection
    local bg, fg
    if props.disabled then
        bg = t.bgCard; fg = t.textMuted
    elseif props.style == "danger" then
        bg = t.danger; fg = t.textOnAccent
    elseif props.style == "ghost" then
        bg = t.bg; fg = t.accent
    else
        bg = t.accent; fg = t.textOnAccent
    end

    -- Draw
    term.setCursorPos(x, y)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    -- Centred label with padding
    local pad   = w - #lbl
    local lpad  = math.floor(pad / 2)
    local rpad  = pad - lpad
    term.write(string.rep(" ", lpad) .. lbl .. string.rep(" ", rpad))

    -- Return hit-test info for input handling
    return {
        x = x, y = y, w = w, h = 1,
        hit = function(mx, my)
            return not props.disabled
                and mx >= x and mx < x + w
                and my == y
        end,
        activate = props.onClick,
    }
end

return M
