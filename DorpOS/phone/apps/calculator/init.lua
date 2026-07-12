--[[  DorpOS :: phone/apps/calculator/init.lua
    Full calculator with standard + recent history.
    Supports: + - * / ^ % decimal and parentheses (via Lua's load).
]]
local C     = require("shared.constants")
local ui    = require("system.ui.ui")
local Theme = require("system.theme.theme")
local utils = require("system.utils.utils")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT

local expr    = ""
local result  = ""
local history = {}
local MAX_H   = 5

local BUTTONS = {
    {"7","8","9","/"},
    {"4","5","6","*"},
    {"1","2","3","-"},
    {"0",".","=","+"},
    {"(",")","%","^"},
    {"C","<","",""},
}

local function evalExpr(e)
    -- Replace ^ with ** for Lua exponentiation
    e = e:gsub("%^", "**")
    local fn, err = load("return " .. e)
    if not fn then return nil, err end
    local ok, val = pcall(fn)
    if not ok then return nil, tostring(val) end
    return tostring(val), nil
end

local _hits = {}

local function draw()
    local t = Theme.get()
    ui.clear()

    -- Header
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" Calculator", W))

    -- History
    local histY = 2
    for i = math.max(1, #history - MAX_H + 1), #history do
        local h = history[i]
        term.setCursorPos(1, histY)
        term.setBackgroundColor(t.bg)
        term.setTextColor(t.textMuted)
        term.write(utils.padRight(utils.truncate(h, W - 1), W))
        histY = histY + 1
    end

    -- Expression bar
    local exprY = 7
    term.setCursorPos(1, exprY)
    term.setBackgroundColor(t.bgInput)
    term.setTextColor(t.text)
    local disp = #expr > 0 and expr or "0"
    term.write(utils.padRight(utils.truncate(disp, W - 1), W))

    -- Result preview
    term.setCursorPos(1, exprY + 1)
    term.setBackgroundColor(t.bg)
    term.setTextColor(t.accent)
    term.write(utils.padRight(result, W))

    -- Divider
    ui.divider(exprY + 2)

    -- Buttons
    _hits = {}
    local bw  = math.floor(W / 4)
    local by  = exprY + 3
    for ri, row in ipairs(BUTTONS) do
        for ci, label in ipairs(row) do
            if label ~= "" then
                local bx = 1 + (ci - 1) * bw
                local isEq  = label == "="
                local isCl  = label == "C"
                local isBk  = label == "<"
                local bg = isEq and t.accent or (isCl and t.danger or t.bgCard)
                local fg = (isEq or isCl) and t.textOnAccent or t.text
                term.setCursorPos(bx, by + (ri - 1))
                term.setBackgroundColor(bg)
                term.setTextColor(fg)
                term.write(utils.centre(label, bw))
                local lbl = label
                table.insert(_hits, {
                    x1 = bx, x2 = bx + bw - 1, y1 = by + ri - 1, y2 = by + ri - 1,
                    label = lbl,
                })
            end
        end
    end

    -- Back button
    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
end

draw()

while true do
    local ev = { os.pullEvent() }
    local name = ev[1]

    if name == "mouse_click" then
        local mx, my = ev[3], ev[4]

        -- Back
        if my == H and mx <= 3 then return end

        for _, h in ipairs(_hits) do
            if mx >= h.x1 and mx <= h.x2 and my == h.y1 then
                local lbl = h.label
                if lbl == "C" then
                    expr = ""; result = ""
                elseif lbl == "<" then
                    if #expr > 0 then expr = expr:sub(1, -2) end
                elseif lbl == "=" then
                    if #expr > 0 then
                        local val, err = evalExpr(expr)
                        if val then
                            table.insert(history, expr .. " = " .. val)
                            expr = val; result = ""
                        else
                            result = "Error"
                        end
                    end
                else
                    expr = expr .. lbl
                    -- Live preview
                    local val = evalExpr(expr)
                    result = val or ""
                end
                draw()
                break
            end
        end

    elseif name == "char" then
        local ch = ev[2]
        if ch:match("[0-9%.%(%)%+%-%*/%%%^%.]") then
            expr = expr .. ch
            draw()
        end
    elseif name == "key" then
        local key = ev[2]
        if key == keys.enter then
            if #expr > 0 then
                local val, err = evalExpr(expr)
                if val then
                    table.insert(history, expr .. " = " .. val)
                    expr = val; result = ""
                else result = "Error" end
                draw()
            end
        elseif key == keys.backspace and #expr > 0 then
            expr = expr:sub(1, -2); draw()
        end
    end
end
