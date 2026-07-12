--[[  DorpOS :: phone/apps/clock/init.lua
    Clock app: World Clock tab, Stopwatch tab, Timer tab.
]]
local C     = require("shared.constants")
local ui    = require("system.ui.ui")
local Theme = require("system.theme.theme")
local utils = require("system.utils.utils")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT

local TAB_CLOCK = 1
local TAB_STOP  = 2
local TAB_TIMER = 3

local tab       = TAB_CLOCK

-- Stopwatch state
local swRunning = false
local swStart   = 0
local swElapsed = 0

-- Timer state
local timerTarget = 0  -- seconds
local timerStart  = 0
local timerRunning = false
local timerInput  = ""

local function fmtMs(ms)
    local s  = math.floor(ms / 1000)
    local cs = math.floor((ms % 1000) / 10)
    local m  = math.floor(s / 60)
    s = s % 60
    return string.format("%02d:%02d.%02d", m, s, cs)
end

local function fmtSecs(s)
    local m = math.floor(s / 60)
    s = s % 60
    return string.format("%02d:%02d", m, s)
end

local function drawTabs()
    local t   = Theme.get()
    local tabs = { "Clock", "Stopwatch", "Timer" }
    local tw   = math.floor(W / #tabs)
    for i, name in ipairs(tabs) do
        local bg = (i == tab) and t.accent or t.bgCard
        local fg = (i == tab) and t.textOnAccent or t.text
        term.setCursorPos(1 + (i - 1) * tw, 2)
        term.setBackgroundColor(bg)
        term.setTextColor(fg)
        term.write(utils.centre(name, tw))
    end
end

local function drawHeader()
    local t = Theme.get()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" Clock", W))
end

local function drawClock()
    local t = Theme.get()
    local time = utils.now()
    local date = utils.today()
    local timeX = math.floor((W - #time) / 2) + 1
    local dateX = math.floor((W - #date) / 2) + 1

    -- Big time display
    term.setCursorPos(timeX, 7)
    term.setBackgroundColor(t.bg)
    term.setTextColor(t.accent)
    term.write(time)

    term.setCursorPos(dateX, 9)
    term.setTextColor(t.textMuted)
    term.write(date)

    -- Day of week (approximate from epoch)
    local epoch_secs = math.floor(os.epoch("utc") / 1000)
    local days = { "Thu","Fri","Sat","Sun","Mon","Tue","Wed" }
    local dow  = days[(math.floor(epoch_secs / 86400) % 7) + 1]
    term.setCursorPos(math.floor((W - #dow) / 2) + 1, 10)
    term.setTextColor(t.textMuted)
    term.write(dow)
end

local function drawStopwatch()
    local t   = Theme.get()
    local elapsed = swElapsed
    if swRunning then
        elapsed = elapsed + (os.epoch("utc") - swStart)
    end
    local display = fmtMs(elapsed)
    term.setCursorPos(math.floor((W - #display) / 2) + 1, 7)
    term.setBackgroundColor(t.bg)
    term.setTextColor(t.accent)
    term.write(display)

    local startLbl = swRunning and "Stop" or "Start"
    ui.button({ x = 2, y = 11, width = 10, label = startLbl,
                style = swRunning and "danger" or "primary" })
    ui.button({ x = 14, y = 11, width = 10, label = "Reset", style = "ghost" })
end

local function drawTimer()
    local t       = Theme.get()
    local remaining = 0
    if timerRunning then
        remaining = math.max(0, timerTarget - math.floor((os.epoch("utc") - timerStart) / 1000))
        if remaining == 0 then
            timerRunning = false
            -- Notify
            os.queueEvent("dorpos_notification", {
                title = "Timer", body = "Timer finished!", type = "info", priority = 2
            })
        end
    end
    local display = timerRunning and fmtSecs(remaining) or
                    (#timerInput > 0 and timerInput .. "s" or "00:00")

    term.setCursorPos(math.floor((W - #display) / 2) + 1, 7)
    term.setBackgroundColor(t.bg)
    term.setTextColor(t.accent)
    term.write(display)

    if not timerRunning then
        ui.write(2, 9, "Enter seconds:", t.textMuted, t.bg)
        ui.textbox({ x = 2, y = 10, width = 10, value = timerInput, focused = true })
        ui.button({ x = 14, y = 10, width = 10, label = "Start", style = "primary" })
    else
        ui.button({ x = 2, y = 11, width = 10, label = "Cancel", style = "danger" })
    end
end

local function redraw()
    local t = Theme.get()
    ui.clear()
    drawHeader()
    drawTabs()
    ui.divider(3)

    if tab == TAB_CLOCK then drawClock()
    elseif tab == TAB_STOP then drawStopwatch()
    elseif tab == TAB_TIMER then drawTimer() end

    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
end

-- Periodic tick timer
local tickTimer = os.startTimer(1)

redraw()

while true do
    local ev = { os.pullEvent() }
    local name = ev[1]

    if name == "mouse_click" then
        local mx, my = ev[3], ev[4]

        if my == H and mx <= 3 then return end

        -- Tab bar
        if my == 2 then
            local tw = math.floor(W / 3)
            local newTab = math.min(3, math.floor((mx - 1) / tw) + 1)
            tab = newTab; redraw()
        end

        -- Stopwatch controls
        if tab == TAB_STOP and my == 11 then
            if mx >= 2 and mx <= 11 then
                if swRunning then
                    swElapsed = swElapsed + (os.epoch("utc") - swStart)
                    swRunning = false
                else
                    swStart   = os.epoch("utc")
                    swRunning = true
                end
            elseif mx >= 14 and mx <= 23 then
                swElapsed = 0; swRunning = false
            end
            redraw()
        end

        -- Timer controls
        if tab == TAB_TIMER then
            if not timerRunning and my == 10 and mx >= 14 then
                local secs = tonumber(timerInput)
                if secs and secs > 0 then
                    timerTarget  = secs
                    timerStart   = os.epoch("utc")
                    timerRunning = true
                    timerInput   = ""
                end
            elseif timerRunning and my == 11 and mx >= 2 and mx <= 11 then
                timerRunning = false
            end
            redraw()
        end

    elseif name == "char" and tab == TAB_TIMER and not timerRunning then
        if ev[2]:match("%d") and #timerInput < 6 then
            timerInput = timerInput .. ev[2]; redraw()
        end
    elseif name == "key" and tab == TAB_TIMER then
        if ev[2] == keys.backspace and #timerInput > 0 then
            timerInput = timerInput:sub(1, -2); redraw()
        end

    elseif name == "timer" then
        tickTimer = os.startTimer(1)
        redraw()
    end
end
