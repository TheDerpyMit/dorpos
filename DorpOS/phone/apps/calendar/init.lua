--[[  DorpOS :: phone/apps/calendar/init.lua  ]]
local C       = require("shared.constants")
local ui      = require("system.ui.ui")
local Theme   = require("system.theme.theme")
local Storage = require("system.storage.storage")
local utils   = require("system.utils.utils")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT
local kbComp = require("system.ui.components.keyboard")

local store  = Storage.open("calendar")
local events = store.get("events", {})

-- Current display month/year (from epoch)
local now     = os.epoch("utc")
local nowDay  = math.floor(now / 86400000)

-- Compute year/month/day from day offset (days since 1970-01-01)
local function fromDays(d)
    local y, m = 1970, 1
    local daysInMonth = {31,28,31,30,31,30,31,31,30,31,30,31}
    while true do
        local leap = (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0))
        local diy  = leap and 366 or 365
        if d < diy then break end
        d = d - diy; y = y + 1
    end
    local leap = (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0))
    if leap then daysInMonth[2] = 29 end
    while d >= daysInMonth[m] do
        d = d - daysInMonth[m]; m = m + 1
    end
    return y, m, d + 1
end

local YEAR, MONTH, _ = fromDays(nowDay)
local selYear  = YEAR
local selMonth = MONTH
local selDay   = nil

local MONTH_NAMES = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}
local DAY_NAMES   = {"Su","Mo","Tu","We","Th","Fr","Sa"}

local function daysInMonth(y, m)
    local dims = {31,28,31,30,31,30,31,31,30,31,30,31}
    if m == 2 and (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) then return 29 end
    return dims[m]
end

-- Day of week for 1st of month (0=Sun)
local function firstDow(y, m)
    -- Zeller's congruence
    if m < 3 then m = m + 12; y = y - 1 end
    local k = y % 100; local j = math.floor(y / 100)
    local h = (1 + math.floor(13*(m+1)/5) + k + math.floor(k/4) + math.floor(j/4) - 2*j) % 7
    return (h + 6) % 7  -- 0=Sun
end

local function getEventsForDay(y, m, d)
    local key = string.format("%04d-%02d-%02d", y, m, d)
    local out = {}
    for _, e in ipairs(events) do
        if e.date == key then table.insert(out, e) end
    end
    return out
end

local shifted = false
local kbHits  = nil
local editMode = false
local newEvTitle = ""
local newEvDate  = ""

local function drawCalendar()
    local t    = Theme.get()
    local dow1 = firstDow(selYear, selMonth)
    local dims = daysInMonth(selYear, selMonth)

    ui.clear()
    -- Header
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" < " .. MONTH_NAMES[selMonth] .. " " .. selYear .. " >", W))

    -- Day header row
    term.setCursorPos(1, 2)
    term.setBackgroundColor(t.bgCard)
    term.setTextColor(t.textMuted)
    for _, dn in ipairs(DAY_NAMES) do
        term.write(dn .. " ")
    end

    -- Day grid
    local col = dow1
    local row = 3
    local _hits = {}

    for day = 1, dims do
        local x  = 1 + col * (math.floor(W / 7))
        local isToday = (selYear == YEAR and selMonth == MONTH and day == (nowDay % 31 + 1))
        local isSel   = (selDay == day)

        term.setCursorPos(x, row)
        local bg = isSel and t.accent or (isToday and t.accentDark or t.bg)
        local fg = (isSel or isToday) and t.textOnAccent or t.text
        term.setBackgroundColor(bg)
        term.setTextColor(fg)
        term.write(string.format("%2d", day))

        -- Dot if has events
        local evs = getEventsForDay(selYear, selMonth, day)
        if #evs > 0 then
            term.setCursorPos(x + 1, row)
            term.setTextColor(t.accent)
            if not isSel then term.write(".") end
        end

        table.insert(_hits, { x1 = x, x2 = x + 1, y1 = row, y2 = row, day = day })

        col = col + 1
        if col >= 7 then col = 0; row = row + 1 end
    end

    -- Events for selected day
    if selDay then
        local evs = getEventsForDay(selYear, selMonth, selDay)
        local ey  = row + 2
        ui.write(2, ey, string.format("Events %s %d:", MONTH_NAMES[selMonth], selDay), t.textMuted, t.bg)
        if #evs == 0 then
            ui.write(2, ey + 1, "None. Tap [+] to add.", t.textMuted, t.bg)
        else
            for i, e in ipairs(evs) do
                ui.write(2, ey + i, utils.truncate(e.title or "?", W - 3), t.text, t.bg)
            end
        end
    end

    ui.button({ x = 1,     y = H, width = 6, label = "< Back",  style = "ghost" })
    ui.button({ x = W - 7, y = H, width = 7, label = "[+] Add"  })
    return _hits
end

local function addEventDialog()
    local t = Theme.get()
    newEvTitle = ""
    newEvDate  = selDay and string.format("%04d-%02d-%02d", selYear, selMonth, selDay) or ""

    local focused = "title"
    local function redraw()
        ui.clear()
        term.setCursorPos(1, 1)
        term.setBackgroundColor(t.accent)
        term.setTextColor(t.textOnAccent)
        term.write(utils.padRight(" Add Event", W))
        ui.write(2, 3, "Title:", t.textMuted, t.bg)
        ui.textbox({ x = 2, y = 4, width = W - 3, value = newEvTitle,
                     focused = focused == "title", placeholder = "Event name" })
        ui.write(2, 6, "Date (YYYY-MM-DD):", t.textMuted, t.bg)
        ui.textbox({ x = 2, y = 7, width = W - 3, value = newEvDate,
                     focused = focused == "date", placeholder = "2026-01-01" })
        kbHits = kbComp.draw({
            y = H - 6, shifted = shifted,
            onChar  = function(c)
                if focused == "title" then newEvTitle = newEvTitle .. c
                else newEvDate = newEvDate .. c end
            end,
            onBack  = function()
                if focused == "title" and #newEvTitle > 0 then newEvTitle = newEvTitle:sub(1,-2)
                elseif focused == "date" and #newEvDate > 0 then newEvDate = newEvDate:sub(1,-2) end
            end,
            onEnter = function() focused = focused == "title" and "date" or "title" end,
            onShift = function() shifted = not shifted end,
            onClose = function() editMode = false end,
        })
        ui.button({ x = W - 7, y = H - 8, width = 7, label = "Save" })
    end

    redraw()
    while true do
        local ev = { os.pullEvent() }
        local name = ev[1]
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if my == H - 8 and mx >= W - 7 then
                if #newEvTitle > 0 and #newEvDate > 0 then
                    table.insert(events, { title = newEvTitle, date = newEvDate })
                    store.set("events", events); store.save()
                    return
                end
            end
            if my == 4 then focused = "title"; redraw()
            elseif my == 7 then focused = "date"; redraw()
            elseif kbHits then kbComp.handleClick(kbHits, mx, my); redraw() end
        elseif name == "char" then
            if focused == "title" then newEvTitle = newEvTitle .. ev[2]
            else newEvDate = newEvDate .. ev[2] end
            redraw()
        elseif name == "key" then
            if ev[2] == keys.backspace then
                if focused == "title" and #newEvTitle > 0 then newEvTitle = newEvTitle:sub(1,-2)
                elseif focused == "date" and #newEvDate > 0 then newEvDate = newEvDate:sub(1,-2) end
                redraw()
            end
        end
    end
end

local _hits = drawCalendar()

while true do
    local ev = { os.pullEvent() }
    if ev[1] == "mouse_click" then
        local mx, my = ev[3], ev[4]
        if my == H and mx <= 6 then return end
        if my == H and mx >= W - 7 then addEventDialog(); _hits = drawCalendar() end
        -- Month navigation (< >) in header
        if my == 1 then
            if mx <= 2 then
                selMonth = selMonth - 1
                if selMonth < 1 then selMonth = 12; selYear = selYear - 1 end
                selDay = nil; _hits = drawCalendar()
            elseif mx >= W - 1 then
                selMonth = selMonth + 1
                if selMonth > 12 then selMonth = 1; selYear = selYear + 1 end
                selDay = nil; _hits = drawCalendar()
            end
        end
        for _, h in ipairs(_hits) do
            if mx >= h.x1 and mx <= h.x2 and my == h.y1 then
                selDay = h.day; _hits = drawCalendar(); break
            end
        end
    end
end
