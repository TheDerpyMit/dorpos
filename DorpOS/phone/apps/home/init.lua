--[[
    DorpOS :: phone/apps/home/init.lua
    ─────────────────────────────────────
    Home screen — the main launcher UI.

    Features:
        - Status bar (time, battery/signal indicators)
        - App icon grid (pages, swipe left/right)
        - Dock (4 fixed apps at bottom)
        - App drawer (scrollable full list)
        - Notification center (pull down from status bar)
        - Quick settings panel
        - Search overlay
        - Animated page transitions
]]

local C       = require("shared.constants")
local ui      = require("system.ui.ui")
local Theme   = require("system.theme.theme")
local anim    = require("system.animation.animation")
local appMgr  = require("system.services.app_manager")
local notif   = require("system.services.notification_manager")
local Storage = require("system.storage.storage")
local utils   = require("system.utils.utils")
local net     = require("system.network.network")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT

-- ─────────────────────────────────────────────────────────────
-- Layout constants
-- ─────────────────────────────────────────────────────────────

local STATUS_Y   = 1
local CONTENT_Y  = 2
local CONTENT_H  = H - 2
local DOCK_Y     = H
local COLS       = 3    -- icon columns (3 allows 8 chars per icon, preventing truncation)
local ROWS       = 4    -- icon rows per page
local ICON_W     = math.floor(W / COLS)
local ICON_H     = 3   -- rows per icon (char + label + gap)
local ICONS_PER_PAGE = COLS * ROWS

-- ─────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────

local prefs     = Storage.open("home_prefs")
local page      = prefs.get("page", 1)
local showDrawer = false
local showNotifs = false
local showQuick  = false
local searchMode = false
local searchQuery = ""

-- Dock app IDs (with a dedicated App Drawer button in the center)
local DOCK = {
    C.APP_MESSAGES,
    C.APP_MARKETPLACE,
    "drawer",
    C.APP_SETTINGS,
    C.APP_CALCULATOR,
}

-- All launchable apps (excluding home itself and lockscreen)
local function getLaunchableApps()
    local all = appMgr.getAll()
    local out = {}
    for _, app in ipairs(all) do
        if app.id ~= C.APP_HOME and app.id ~= C.APP_LOCKSCREEN
        and app.id ~= C.APP_SETUP then
            table.insert(out, app)
        end
    end
    return out
end

-- ─────────────────────────────────────────────────────────────
-- Drawing helpers
-- ─────────────────────────────────────────────────────────────

local function drawStatusBar()
    local t   = Theme.get()
    local now = utils.now()
    local unread = notif.unreadCount()

    term.setCursorPos(1, STATUS_Y)
    term.setBackgroundColor(t.statusBarBg)
    term.setTextColor(t.statusBarText)
    term.write(string.rep(" ", W))

    -- Time (left)
    term.setCursorPos(2, STATUS_Y)
    term.write(now)

    -- Notification dot (centre-ish)
    if unread > 0 then
        local indicator = "(" .. math.min(unread, 9) .. ")"
        term.setCursorPos(math.floor(W / 2) - 1, STATUS_Y)
        term.setTextColor(t.accent)
        term.write(indicator)
        term.setTextColor(t.statusBarText)
    end

    -- Signal status (right, no battery)
    local online = net.isOnline()
    local right  = online and "Online" or "Offline"
    term.setCursorPos(W - #right - 1, STATUS_Y)
    term.write(right)
end

local APP_ICONS = {
    [C.APP_MESSAGES] = {
        "  /--\\  ",
        "  \\--V  "
    },
    [C.APP_MARKETPLACE] = {
        "  _$_   ",
        "  \\-/   "
    },
    [C.APP_SETTINGS] = {
        "  /-\\   ",
        "  \\-/   "
    },
    [C.APP_CALCULATOR] = {
        "  [+-]  ",
        "  [*/]  "
    },
    [C.APP_CONTACTS] = {
        "  ( )   ",
        "  /-\\   "
    },
    [C.APP_NOTES] = {
        "  ___   ",
        " |___|  "
    },
    [C.APP_FILES] = {
        "  /~\\   ",
        " |___|  "
    },
    [C.APP_CLOCK] = {
        "  /-\\   ",
        "  \\o/   "
    },
    [C.APP_CALENDAR] = {
        " [===]  ",
        " | 31|  "
    },
    [C.APP_ABOUT] = {
        "  (i)   ",
        "   |    "
    },
    [C.APP_CLOUD] = {
        "  (~)   ",
        " (___)  "
    }
}

local function drawAppIcon(app, x, y, selected)
    local t  = Theme.get()
    local bg = selected and t.accent or t.iconBg
    local fg = selected and t.textOnAccent or t.iconText

    local lines = APP_ICONS[app.id] or {
        "  [" .. (app.icon or "?") .. "]   ",
        "  [" .. (app.icon or "?") .. "]   "
    }

    -- Row 1: Icon line 1
    term.setCursorPos(x, y)
    term.setBackgroundColor(bg)
    term.setTextColor(fg)
    term.write(utils.centre(lines[1], ICON_W))

    -- Row 2: Icon line 2
    term.setCursorPos(x, y + 1)
    term.write(utils.centre(lines[2], ICON_W))

    -- Label below (in background colour)
    term.setCursorPos(x, y + 2)
    term.setBackgroundColor(t.bg)
    term.setTextColor(t.text)
    term.write(utils.centre(utils.truncate(app.name, ICON_W), ICON_W))
end

local function drawPageDots(total, current, y)
    local t   = Theme.get()
    local str = ""
    for i = 1, total do
        str = str .. (i == current and "\7" or ".")
        if i < total then str = str .. " " end
    end
    local x = math.floor((W - #str) / 2) + 1
    term.setCursorPos(x, y)
    term.setBackgroundColor(t.bg)
    term.setTextColor(t.accent)
    term.write(str)
end

local function drawDock(dockApps)
    local t   = Theme.get()
    local x   = 1
    local dw  = math.floor(W / #dockApps)

    term.setCursorPos(1, DOCK_Y)
    term.setBackgroundColor(t.dockBg)
    term.write(string.rep(" ", W))

    for i, app in ipairs(dockApps) do
        local dx = 1 + (i - 1) * dw
        term.setCursorPos(dx + math.floor(dw / 2), DOCK_Y)
        term.setTextColor(t.dockText)
        term.setBackgroundColor(t.dockBg)
        if app == "drawer" then
            term.write("::")
        else
            term.write(app and (app.icon or "?") or " ")
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Main home screen draw
-- ─────────────────────────────────────────────────────────────

local _hitAreas = {}

local function drawHome(apps)
    local t = Theme.get()
    ui.clear()

    drawStatusBar()

    -- Fill background
    term.setBackgroundColor(t.bg)
    for row = CONTENT_Y, H - 1 do
        term.setCursorPos(1, row)
        term.write(string.rep(" ", W))
    end

    -- Calculate page range
    local totalPages = math.max(1, math.ceil(#apps / ICONS_PER_PAGE))
    page = math.max(1, math.min(page, totalPages))

    local startIdx = (page - 1) * ICONS_PER_PAGE + 1

    _hitAreas = {}

    -- Draw icons
    for row = 0, ROWS - 1 do
        for col = 0, COLS - 1 do
            local appIdx = startIdx + row * COLS + col
            if appIdx <= #apps then
                local app = apps[appIdx]
                local ix  = 1 + col * ICON_W
                local iy  = CONTENT_Y + row * ICON_H

                drawAppIcon(app, ix, iy, false)

                local appId = app.id
                table.insert(_hitAreas, {
                    x1 = ix, x2 = ix + ICON_W - 1,
                    y1 = iy, y2 = iy + ICON_H - 1,
                    action = function()
                        os.queueEvent("dorpos_launch_app", appId)
                    end,
                })
            end
        end
    end

    -- Page dots
    local dotsY = CONTENT_Y + ROWS * ICON_H + 1
    if dotsY < DOCK_Y - 1 then
        drawPageDots(totalPages, page, dotsY)
    end

    -- Dock
    local dockInfos = {}
    for _, id in ipairs(DOCK) do
        if id == "drawer" then
            table.insert(dockInfos, "drawer")
        else
            table.insert(dockInfos, appMgr.getInfo(id))
        end
    end
    drawDock(dockInfos)

    -- Dock hit areas
    local dw = math.floor(W / #DOCK)
    for i, id in ipairs(DOCK) do
        local dx1 = 1 + (i - 1) * dw
        local dx2 = dx1 + dw - 1
        local launchId = id
        table.insert(_hitAreas, {
            x1 = dx1, x2 = dx2, y1 = DOCK_Y, y2 = DOCK_Y,
            action = function()
                if launchId == "drawer" then
                    showDrawer = true
                else
                    os.queueEvent("dorpos_launch_app", launchId)
                end
            end,
        })
    end

    -- Status bar hit (pull down = notification centre)
    table.insert(_hitAreas, {
        x1 = 1, x2 = W, y1 = STATUS_Y, y2 = STATUS_Y,
        action = function() showNotifs = true end,
    })
end

-- ─────────────────────────────────────────────────────────────
-- Notification center overlay
-- ─────────────────────────────────────────────────────────────

local function drawNotifCenter(apps)
    local t      = Theme.get()
    local notifs = notif.getAll()
    local panelH = math.min(H - 2, math.max(6, #notifs * 2 + 3))
    local panelY = 1

    -- Semi-dark backdrop
    term.setBackgroundColor(colors.black)
    for r = 1, H do
        term.setCursorPos(1, r)
        term.write(string.rep(" ", W))
    end

    -- Panel
    ui.window({ x = 1, y = panelY, width = W, height = panelH,
                title = "Notifications  [x close]", titleBg = t.accent })

    local _nhits = {}

    if #notifs == 0 then
        ui.write(3, panelY + 2, "No notifications", t.textMuted, t.bgCard)
    else
        local visCount = math.floor((panelH - 2) / 2)
        for i = 1, math.min(visCount, #notifs) do
            local n  = notifs[i]
            local ny = panelY + 1 + (i - 1) * 2
            ui.write(2, ny,     utils.truncate(n.title or "", W - 3), t.accent,   t.bgCard)
            ui.write(2, ny + 1, utils.truncate(n.body  or "", W - 3), t.textMuted, t.bgCard)
            local ni = n.id
            table.insert(_nhits, {
                x1 = 1, x2 = W, y1 = ny, y2 = ny + 1,
                action = function() notif.markRead(ni) end,
            })
        end
    end

    -- Mark all read button
    ui.button({ x = 2, y = panelY + panelH - 1, width = 14,
                label = "Mark all read", style = "ghost" })
    table.insert(_nhits, {
        x1 = 2, x2 = 15, y1 = panelY + panelH - 1, y2 = panelY + panelH - 1,
        action = function() notif.markAllRead() end,
    })

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        -- Close button (check for "x" in title area)
        if my == panelY and mx >= W - 7 then
            showNotifs = false
            return
        end
        -- Notification items
        local handled = false
        for _, h in ipairs(_nhits) do
            if mx >= h.x1 and mx <= h.x2 and my >= h.y1 and my <= h.y2 then
                if h.action then h.action() end
                handled = true
                break
            end
        end
        if not handled then
            -- Click outside panel = close
            if my > panelY + panelH then
                showNotifs = false
                return
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- App drawer overlay (full scrollable app list)
-- ─────────────────────────────────────────────────────────────

local _drawerScroll = 1

local function drawAppDrawer(apps)
    local t = Theme.get()
    ui.clear()

    -- Header
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" All Apps        [v]", W))

    -- Search bar
    term.setCursorPos(1, 2)
    term.setBackgroundColor(t.bgInput)
    term.setTextColor(t.text)
    term.write(utils.padRight("  Search: " .. searchQuery .. "_", W))

    -- Filter apps
    local filtered = searchQuery == "" and apps or (function()
        local q = searchQuery:lower()
        local out = {}
        for _, a in ipairs(apps) do
            if a.name:lower():find(q, 1, true) then
                table.insert(out, a)
            end
        end
        return out
    end)()

    -- List
    local listH = H - 3
    local _dhits = {}
    for i = _drawerScroll, math.min(_drawerScroll + listH - 1, #filtered) do
        local app = filtered[i]
        local ry  = 3 + (i - _drawerScroll)
        term.setCursorPos(1, ry)
        term.setBackgroundColor(t.bg)
        term.setTextColor(t.text)
        term.write(utils.padRight("  " .. (app.icon or "?") .. "  " .. app.name, W))
        local appId = app.id
        table.insert(_dhits, {
            y = ry,
            action = function() os.queueEvent("dorpos_launch_app", appId) end,
        })
    end

    while true do
        local ev = { os.pullEvent() }
        local name = ev[1]

        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            -- Close / header
            if my == 1 and mx >= W - 3 then
                showDrawer = false; return
            end
            -- Search bar
            if my == 2 then
                searchMode = true
            end
            -- List items
            for _, h in ipairs(_dhits) do
                if my == h.y then
                    if h.action then h.action() end
                    showDrawer = false
                    return
                end
            end
        elseif name == "mouse_scroll" then
            local dir = ev[2]
            _drawerScroll = math.max(1,
                math.min(_drawerScroll + dir, math.max(1, #filtered - listH + 1)))
            drawAppDrawer(apps); return
        elseif name == "char" and searchMode then
            searchQuery = searchQuery .. ev[2]
            drawAppDrawer(apps); return
        elseif name == "key" then
            local key = ev[2]
            if key == keys.backspace and #searchQuery > 0 then
                searchQuery = searchQuery:sub(1, -2)
                drawAppDrawer(apps); return
            elseif key == keys.escape then
                showDrawer = false; return
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Main loop
-- ─────────────────────────────────────────────────────────────

local apps = getLaunchableApps()
drawHome(apps)

while true do
    local ev = { os.pullEvent() }
    local name = ev[1]

    if showNotifs then
        drawNotifCenter(apps)
        drawHome(apps)

    elseif showDrawer then
        drawAppDrawer(apps)
        apps = getLaunchableApps()  -- refresh after possible install
        drawHome(apps)

    elseif name == "mouse_click" then
        local mx, my = ev[3], ev[4]
        local handled = false

        for _, h in ipairs(_hitAreas) do
            if mx >= h.x1 and mx <= h.x2 and my >= h.y1 and my <= h.y2 then
                if h.action then h.action() end
                handled = true
                break
            end
        end

        if not handled then
            -- Tap empty area does nothing now to prevent accidental popups
        end

    elseif name == "mouse_scroll" then
        local dir = ev[2]
        local apps2  = getLaunchableApps()
        local total  = math.max(1, math.ceil(#apps2 / ICONS_PER_PAGE))
        local oldPage = page
        page = math.max(1, math.min(page + dir, total))
        if page ~= oldPage then
            prefs.set("page", page)
            prefs.save()
            if dir > 0 then
                anim.slideLeft(function() drawHome(apps2) end, function() drawHome(apps2) end)
            else
                anim.slideRight(function() drawHome(apps2) end, function() drawHome(apps2) end)
            end
            drawHome(apps2)
        end

    elseif name == "dorpos_launch_app" then
        local appId = ev[2]
        local args  = ev[3]
        -- Animate open
        local info = appMgr.getInfo(appId)
        if info then
            anim.fade(function() ui.clear() end, false)
            local ok, err = appMgr.launch(appId, args)
            if not ok then
                -- Show error briefly
                term.setBackgroundColor(colors.red)
                term.setTextColor(colors.white)
                term.clear()
                term.setCursorPos(1, H / 2)
                term.write(utils.centre("App crashed: " .. (err or "?"), W))
                os.sleep(2)
            end
            apps = getLaunchableApps()
            anim.fade(function() drawHome(apps) end, true)
        end

    elseif name == "dorpos_notification" then
        -- Banner shown by kernel; just refresh status bar
        drawStatusBar()

    elseif name == "dorpos_clock_tick" or name == "timer" then
        drawStatusBar()
    end
end
