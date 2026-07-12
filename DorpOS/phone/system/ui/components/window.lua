--[[  DorpOS :: system/ui/components/window.lua
    Draws a bordered panel / card with an optional title bar.

    Props:
        x, y    number
        width   number
        height  number
        title   string?   Shown in top bar; omit for borderless card
        bg      number?   Panel background (default theme.bgCard)
        titleBg number?   Title bar background (default theme.accent)
        titleFg number?   Title bar text (default theme.textOnAccent)
]]
local M = {}
local Theme = require("system.theme.theme")
local utils = require("system.utils.utils")

function M.draw(props)
    local t = Theme.get()
    local x  = props.x or 1
    local y  = props.y or 1
    local w  = props.width  or 20
    local h  = props.height or 10
    local bg = props.bg or t.bgCard

    -- Fill panel background
    term.setBackgroundColor(bg)
    for row = y, y + h - 1 do
        term.setCursorPos(x, row)
        term.write(string.rep(" ", w))
    end

    -- Optional title bar (row y)
    if props.title then
        local tbg = props.titleBg or t.accent
        local tfg = props.titleFg or t.textOnAccent
        term.setCursorPos(x, y)
        term.setBackgroundColor(tbg)
        term.setTextColor(tfg)
        term.write(utils.padRight(" " .. props.title, w))
    end
end

return M
