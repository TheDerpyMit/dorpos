--[[
    DorpOS :: phone/apps/lockscreen/init.lua
    ─────────────────────────────────────────
    Lock screen. Shown on boot (after wizard) and when the phone is locked.

    Features:
        - Clock (updates every second)
        - Date
        - Notification summary strip
        - PIN entry with on-screen keyboard
        - Unlock animation
        - Too-many-attempts lockout

    Exits by returning normally when unlocked.
    The caller (boot.lua or kernel.lua) then proceeds to home screen.
]]

local C       = require("shared.constants")
local ui      = require("system.ui.ui")
local Theme   = require("system.theme.theme")
local Storage = require("system.storage.storage")
local sha     = require("system.crypto.sha256")
local utils   = require("system.utils.utils")
local anim    = require("system.animation.animation")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT

-- ─────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────

local pinStore    = Storage.open("pin")
local pinHash     = pinStore.get("hash", nil)
local attempts    = 0
local lockedUntil = 0
local entry       = ""

-- ─────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────

local function isLocked()
    return os.epoch("utc") / 1000 < lockedUntil
end

local function remainingLock()
    return math.ceil(lockedUntil - os.epoch("utc") / 1000)
end

-- ─────────────────────────────────────────────────────────────
-- Drawing
-- ─────────────────────────────────────────────────────────────

local function drawClock(y)
    local t = Theme.get()
    local time = utils.now()
    local date = utils.today()
    ui.write(math.floor((W - #time) / 2) + 1, y,     time, t.accent,   t.bg)
    ui.write(math.floor((W - #date) / 2) + 1, y + 1, date, t.textMuted, t.bg)
end

local function drawPinDots(y)
    local t  = Theme.get()
    local dots = ""
    for i = 1, 8 do
        if i <= #entry then
            dots = dots .. "\7 "  -- filled circle
        else
            dots = dots .. "o "   -- empty circle
        end
    end
    local x = math.floor((W - #dots) / 2) + 1
    ui.write(x, y, dots, t.accent, t.bg)
end

local function drawLockScreen()
    local t = Theme.get()
    ui.clear()

    -- Header
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.bg)
    term.setTextColor(t.textMuted)
    term.write(utils.centre("DorpOS", W))

    -- Clock
    drawClock(4)

    -- Notification count (from cache)
    local notifCache = Storage.open("notifications")
    local count      = notifCache.get("unread", 0)
    if count > 0 then
        local msg = count .. " notification" .. (count > 1 and "s" or "")
        ui.write(math.floor((W - #msg) / 2) + 1, 8, msg, t.info, t.bg)
    end

    -- Divider
    ui.divider(10)

    -- PIN label
    if isLocked() then
        local msg = "Locked " .. remainingLock() .. "s"
        ui.write(math.floor((W - #msg) / 2) + 1, 12, msg, t.danger, t.bg)
    else
        ui.write(math.floor((W - 9) / 2) + 1, 12, "Enter PIN", t.textMuted, t.bg)
        drawPinDots(13)
    end

    -- Error feedback
    if attempts > 0 and not isLocked() then
        local msg = attempts .. "/" .. C.PIN_MAX_ATTEMPTS .. " attempts"
        ui.write(math.floor((W - #msg) / 2) + 1, 15, msg, t.warning, t.bg)
    end
end

-- PIN numpad (digits only, no full keyboard needed)
local function drawNumpad()
    local t   = Theme.get()
    local startY = 16
    local keys  = { "1","2","3","4","5","6","7","8","9","<","0","\x16" }
    -- \x16 = check mark substitute

    local hits = {}
    for i, k in ipairs(keys) do
        local col  = ((i - 1) % 3)
        local row  = math.floor((i - 1) / 3)
        local kx   = 3 + col * 8
        local ky   = startY + row * 1
        local lbl  = k
        local bg   = t.bgCard
        local fg   = t.text
        if k == "<" then fg = t.danger end
        if k == "\x16" then bg = t.accent; fg = t.textOnAccent; lbl = "OK" end

        term.setCursorPos(kx, ky)
        term.setBackgroundColor(bg)
        term.setTextColor(fg)
        term.write("[" .. lbl .. "]")

        local kk = k
        table.insert(hits, {
            x1 = kx, x2 = kx + 3, y1 = ky, y2 = ky,
            key = kk,
        })
    end
    return hits
end

-- ─────────────────────────────────────────────────────────────
-- Unlock animation
-- ─────────────────────────────────────────────────────────────

local function unlockAnim()
    anim.slideUp(function()
        local t = Theme.get()
        term.setBackgroundColor(t.accent)
        term.clear()
        ui.write(math.floor((W - 9) / 2) + 1, H / 2, "Unlocked!", t.textOnAccent, t.accent)
    end)
end

-- ─────────────────────────────────────────────────────────────
-- Main lock screen loop
-- ─────────────────────────────────────────────────────────────

-- If no PIN has been set, skip the lock screen entirely
if not pinHash then
    return
end

local numpadHits = nil

local function fullRedraw()
    drawLockScreen()
    if not isLocked() then
        numpadHits = drawNumpad()
    end
end

fullRedraw()

-- Clock tick coroutine
local function clockTick()
    while true do
        os.sleep(1)
        os.queueEvent("dorpos_clock_tick")
    end
end
local clockCo = coroutine.create(clockTick)
coroutine.resume(clockCo)

while true do
    local ev = { os.pullEvent() }
    local name = ev[1]

    if name == "dorpos_clock_tick" then
        -- Update clock display without full redraw
        local t = Theme.get()
        drawClock(4)
        if isLocked() then
            local msg = "Locked " .. remainingLock() .. "s"
            ui.write(math.floor((W - #msg) / 2) + 1, 12, msg, t.danger, t.bg)
            -- Check if lockout expired
            if not isLocked() then fullRedraw() end
        end
        coroutine.resume(clockCo)

    elseif name == "mouse_click" then
        if isLocked() then
            -- Flash "Locked" message
        elseif numpadHits then
            local mx, my = ev[3], ev[4]
            for _, h in ipairs(numpadHits) do
                if mx >= h.x1 and mx <= h.x2 and my == h.y1 then
                    if h.key == "<" then
                        -- Backspace
                        if #entry > 0 then entry = entry:sub(1, -2) end
                        drawPinDots(13)
                    elseif h.key == "OK" or h.key == "\x16" then
                        -- Verify PIN
                        if sha.equal(sha.hash(entry), pinHash) then
                            -- Correct!
                            attempts = 0
                            unlockAnim()
                            return  -- exit lock screen
                        else
                            attempts = attempts + 1
                            entry = ""
                            if attempts >= C.PIN_MAX_ATTEMPTS then
                                lockedUntil = os.epoch("utc") / 1000 + C.PIN_LOCKOUT_DURATION
                            end
                            fullRedraw()
                        end
                    else
                        -- Digit
                        if #entry < 8 then entry = entry .. h.key end
                        drawPinDots(13)
                    end
                    break
                end
            end
        end
    end
end
