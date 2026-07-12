--[[  DorpOS :: system/ui/components/keyboard.lua
    On-screen QWERTY keyboard optimised for Advanced Pocket Computer
    (26 cols × 20 rows).  Occupies the bottom 7 rows of the screen.

    Props:
        y         number    Top row of keyboard (default 14 on 20-row screen)
        shifted   boolean   Show uppercase / symbols
        value     string    Current input value (for display above keyboard)
        onChar    function  Called with (char) when a key is pressed
        onBack    function  Called when backspace is pressed
        onEnter   function  Called when enter/return is pressed
        onShift   function  Called when shift is toggled (no arg)
        onClose   function  Called when the keyboard dismiss key is pressed

    Returns hit table so the caller can route mouse_click events.
]]
local M = {}
local Theme = require("system.theme.theme")

-- Keyboard layout: 3 rows + a bottom row
-- Each entry: string char, or a special action string starting with "__"
local ROWS_LOWER = {
    { "q","w","e","r","t","y","u","i","o","p" },
    { "a","s","d","f","g","h","j","k","l" },
    { "__SHIFT__","z","x","c","v","b","n","m","__BACK__" },
    { "__CLOSE__","__SPACE__","__ENTER__" },
}
local ROWS_UPPER = {
    { "Q","W","E","R","T","Y","U","I","O","P" },
    { "A","S","D","F","G","H","J","K","L" },
    { "__SHIFT__","Z","X","C","V","B","N","M","__BACK__" },
    { "__CLOSE__","__SPACE__","__ENTER__" },
}

local function drawKey(x, y, w, label, bg, fg)
    term.setCursorPos(x, y)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    -- Centre label in key width
    local lbl = tostring(label)
    if #lbl > w then lbl = lbl:sub(1, w) end
    local pad = w - #lbl
    local lp  = math.floor(pad / 2)
    local rp  = pad - lp
    term.write(string.rep(" ", lp) .. lbl .. string.rep(" ", rp))
end

function M.draw(props)
    local t       = Theme.get()
    local baseY   = props.y or 14
    local shifted = props.shifted or false
    local rows    = shifted and ROWS_UPPER or ROWS_LOWER

    local kbg = t.keyboardBg
    local kfg = t.keyboardText
    local spc = t.keyboardSpecial
    local kk  = t.keyboardKey

    -- Clear keyboard area
    term.setBackgroundColor(kbg)
    for r = baseY, baseY + 6 do
        term.setCursorPos(1, r)
        term.write(string.rep(" ", 26))
    end

    local hits = {}

    -- Row widths and x-offsets
    local rowConfig = {
        -- { keys, startX, keyWidth, keySpacing }
        { keys = rows[1], startX = 1,  keyW = 2, gap = 0 },  -- 10 keys × 2+1 = 26
        { keys = rows[2], startX = 2,  keyW = 2, gap = 0 },  -- 9 keys
        { keys = rows[3], startX = 1,  keyW = 2, gap = 0 },  -- special + 7 + special
        { keys = rows[4], startX = 1,  keyW = 0, gap = 0 },  -- bottom row
    }

    local function addHit(x, y, w, action)
        table.insert(hits, {
            x1 = x, x2 = x + w - 1, y1 = y, y2 = y,
            action = action,
        })
    end

    -- Row 1 (y = baseY)
    do
        local ky = baseY
        local row = rows[1]
        local kw = 2
        local x = 1
        for _, key in ipairs(row) do
            drawKey(x, ky, kw, key, kk, kfg)
            local k = key
            addHit(x, ky, kw, function()
                if props.onChar then props.onChar(k) end
            end)
            x = x + kw + 1
        end
    end

    -- Row 2 (y = baseY+1) — 9 keys, start at col 2
    do
        local ky = baseY + 2
        local row = rows[2]
        local kw = 2
        local x = 2
        for _, key in ipairs(row) do
            drawKey(x, ky, kw, key, kk, kfg)
            local k = key
            addHit(x, ky, kw, function()
                if props.onChar then props.onChar(k) end
            end)
            x = x + kw + 1
        end
    end

    -- Row 3 (y = baseY+2) — shift, 7 letters, backspace
    do
        local ky = baseY + 4
        local x  = 1

        -- Shift (width 3)
        local shiftBg = shifted and t.accent or kk
        drawKey(x, ky, 3, "^", shiftBg, shifted and t.textOnAccent or kfg)
        addHit(x, ky, 3, function()
            if props.onShift then props.onShift() end
        end)
        x = x + 4

        -- Letters
        for _, key in ipairs(rows[3]) do
            if key:sub(1,2) ~= "__" then
                drawKey(x, ky, 2, key, kk, kfg)
                local k = key
                addHit(x, ky, 2, function()
                    if props.onChar then props.onChar(k) end
                end)
                x = x + 3
            end
        end

        -- Backspace (remaining width)
        local bsW = 26 - x + 1
        drawKey(x, ky, bsW, "<", spc, kfg)
        addHit(x, ky, bsW, function()
            if props.onBack then props.onBack() end
        end)
    end

    -- Row 4 (y = baseY+3) — close(3), space(16), enter(7)
    do
        local ky = baseY + 6

        drawKey(1, ky, 3, "v", spc, kfg)
        addHit(1, ky, 3, function()
            if props.onClose then props.onClose() end
        end)

        drawKey(5, ky, 16, " ", kk, kfg)
        addHit(5, ky, 16, function()
            if props.onChar then props.onChar(" ") end
        end)

        drawKey(22, ky, 5, "ENT", t.accent, t.textOnAccent)
        addHit(22, ky, 5, function()
            if props.onEnter then props.onEnter() end
        end)
    end

    return hits
end

--- Route a mouse_click to the correct key action.
---@param hits table   Returned from draw()
---@param mx   number
---@param my   number
---@return boolean handled
function M.handleClick(hits, mx, my)
    for _, h in ipairs(hits) do
        if mx >= h.x1 and mx <= h.x2 and my >= h.y1 and my <= h.y2 then
            if h.action then h.action() end
            return true
        end
    end
    return false
end

return M
