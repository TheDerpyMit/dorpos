--[[  DorpOS :: system/ui/components/toast.lua
    Inline toast banner — drawn statically at a given row.
    For the animated version see animation.lua:toast().

    Props:
        text    string
        type    string  "info"|"success"|"warning"|"error"  (default "info")
        y       number  Row to draw on (default 1)
        width   number  (default SCREEN_WIDTH)
]]
local M = {}
local Theme = require("system.theme.theme")
local utils = require("system.utils.utils")
local C     = require("shared.constants")

local TYPE_COLORS = {
    info    = function(t) return t.info,    t.textOnAccent end,
    success = function(t) return t.success, t.textOnAccent end,
    warning = function(t) return t.warning, colors.black   end,
    error   = function(t) return t.danger,  t.textOnAccent end,
}

local TYPE_ICONS = {
    info    = "i",
    success = "\4",   -- diamond = ✓ substitute in CC font
    warning = "!",
    error   = "x",
}

function M.draw(props)
    local t    = Theme.get()
    local kind = props.type or "info"
    local y    = props.y    or 1
    local w    = props.width or C.SCREEN_WIDTH
    local fn   = TYPE_COLORS[kind] or TYPE_COLORS.info
    local bg, fg = fn(t)

    local icon = TYPE_ICONS[kind] or "i"
    local msg  = "[" .. icon .. "] " .. (props.text or "")
    local line = utils.padRight(msg, w)

    term.setCursorPos(1, y)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    term.write(line)
end

return M
