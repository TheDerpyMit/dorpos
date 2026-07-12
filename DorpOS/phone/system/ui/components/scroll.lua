--[[  DorpOS :: system/ui/components/scroll.lua
    Scroll container — renders a sub-window that clips content and
    shows a vertical scrollbar.

    Props:
        x, y          number
        width         number
        height        number   Visible height
        contentHeight number   Total content height (may be > height)
        scrollY       number   Pixels/rows scrolled (0 = top)
        drawContent   function Called with (offsetY) — draw starting at row 1 as if unclipped
        bg            number?
]]
local M = {}
local Theme = require("system.theme.theme")

function M.draw(props)
    local t   = Theme.get()
    local x   = props.x or 1
    local y   = props.y or 1
    local w   = props.width  or 24
    local h   = props.height or 10
    local ch  = props.contentHeight or h
    local sy  = props.scrollY or 0
    local bg  = props.bg or t.bg

    -- Clipping window
    local win   = window.create(term.current(), x, y, w, h, true)
    local saved = term.redirect(win)
    win.setBackgroundColor(bg)
    win.clear()

    if props.drawContent then
        props.drawContent(sy)
    end

    term.redirect(saved)

    -- Scrollbar (right edge, 1 char wide)
    if ch > h then
        local ratio  = h / ch
        local barH   = math.max(1, math.floor(h * ratio))
        local barY   = math.floor(sy / (ch - h) * (h - barH))
        term.setBackgroundColor(t.border)
        for r = 0, h - 1 do
            term.setCursorPos(x + w - 1, y + r)
            if r >= barY and r < barY + barH then
                term.setBackgroundColor(t.accent)
            else
                term.setBackgroundColor(t.bgCard)
            end
            term.write(" ")
        end
    end
end

return M
