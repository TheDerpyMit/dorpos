--[[  DorpOS :: system/ui/components/dialog.lua
    Blocking modal dialog with title, message and action buttons.

    Props:
        title    string
        message  string
        buttons  table   Array of { label, style, value }
                         style = "primary"|"danger"|"ghost"
                         value = returned to onResult
        onResult function  Called with the button's value when clicked

    Returns: the clicked button's value (also calls onResult).
]]
local M = {}
local Theme = require("system.theme.theme")
local utils = require("system.utils.utils")
local C     = require("shared.constants")

function M.draw(props)
    local t   = Theme.get()
    local W   = C.SCREEN_WIDTH
    local H   = C.SCREEN_HEIGHT
    local dw  = math.min(W - 4, 22)
    local dx  = math.floor((W - dw) / 2) + 1

    -- Measure message height
    local wrapped = utils.wrap(props.message or "", dw - 2)
    local dh = 2 + #wrapped + 1 + 2  -- title + lines + gap + buttons
    local dy = math.floor((H - dh) / 2) + 1

    -- Darken backdrop
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.gray)
    for row = 1, H do
        term.setCursorPos(1, row)
        term.write(string.rep(" ", W))
    end

    -- Panel
    term.setBackgroundColor(t.bgCard)
    for row = dy, dy + dh - 1 do
        term.setCursorPos(dx, row)
        term.write(string.rep(" ", dw))
    end

    -- Title bar
    term.setCursorPos(dx, dy)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" " .. (props.title or ""), dw))

    -- Message lines
    for i, line in ipairs(wrapped) do
        term.setCursorPos(dx + 1, dy + 1 + i - 1)
        term.setBackgroundColor(t.bgCard)
        term.setTextColor(t.text)
        term.write(utils.padRight(line, dw - 2))
    end

    -- Buttons row
    local buttons = props.buttons or { { label = "OK", value = true } }
    local by      = dy + dh - 2
    local bw      = math.floor((dw - 2) / #buttons)
    local hits    = {}

    for i, btn in ipairs(buttons) do
        local bx  = dx + 1 + (i - 1) * bw
        local lbl = utils.truncate(btn.label or "OK", bw)
        local pad = bw - #lbl
        local lp  = math.floor(pad / 2)
        local rp  = pad - lp
        local bbg, bfg
        if btn.style == "danger" then
            bbg = t.danger; bfg = t.textOnAccent
        elseif btn.style == "ghost" then
            bbg = t.bg; bfg = t.accent
        else
            bbg = t.accent; bfg = t.textOnAccent
        end
        term.setCursorPos(bx, by)
        term.setBackgroundColor(bbg)
        term.setTextColor(bfg)
        term.write(string.rep(" ", lp) .. lbl .. string.rep(" ", rp))

        local bv = btn.value
        local bx1, bx2 = bx, bx + bw - 1
        table.insert(hits, {
            hit = function(mx, my) return my == by and mx >= bx1 and mx <= bx2 end,
            value = bv,
        })
    end

    -- Wait for click on a button
    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        for _, h in ipairs(hits) do
            if h.hit(mx, my) then
                if props.onResult then props.onResult(h.value) end
                return h.value
            end
        end
    end
end

return M
