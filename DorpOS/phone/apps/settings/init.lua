--[[  DorpOS :: phone/apps/settings/init.lua
    System settings app.
    Sections: Profile, Appearance, Security, Network, Notifications, About.
]]
local C       = require("shared.constants")
local ui      = require("system.ui.ui")
local Theme   = require("system.theme.theme")
local Storage = require("system.storage.storage")
local net     = require("system.network.network")
local sha     = require("system.crypto.sha256")
local notif   = require("system.services.notification_manager")
local utils   = require("system.utils.utils")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT

local view   = "menu"
local scroll = 1

local SECTIONS = {
    { id = "profile",     label = "Profile",       icon = "@" },
    { id = "appearance",  label = "Appearance",    icon = "*" },
    { id = "security",    label = "Security",      icon = "!" },
    { id = "network",     label = "Network",       icon = "~" },
    { id = "notifs",      label = "Notifications", icon = "N" },
    { id = "storage",     label = "Storage",       icon = "F" },
    { id = "update",      label = "System Update", icon = "U" },
    { id = "about",       label = "About",         icon = "i" },
}

-- ─────────────────────────────────────────────────────────────
-- Section views
-- ─────────────────────────────────────────────────────────────

local function drawMenu()
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" Settings", W))

    local _hits = {}
    for i, sec in ipairs(SECTIONS) do
        local ry = 2 + i
        term.setCursorPos(1, ry)
        term.setBackgroundColor(t.bg)
        term.setTextColor(t.text)
        term.write(utils.padRight("  " .. sec.icon .. "  " .. sec.label, W))
        term.setCursorPos(W, ry)
        term.setTextColor(t.textMuted)
        term.write(">")
        table.insert(_hits, { y = ry, id = sec.id })
    end

    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
    return _hits
end

local function sectionProfile()
    local t   = Theme.get()
    local uc  = Storage.open("user_config")
    local un  = uc.get("username", "Unknown")
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" Profile", W))

    ui.write(2, 4, "Username:", t.textMuted, t.bg)
    ui.write(2, 5, un, t.text, t.bg)
    ui.write(2, 7, "Device ID:", t.textMuted, t.bg)
    ui.write(2, 8, tostring(os.getComputerID()), t.text, t.bg)
    ui.write(2, 10, "OS Version:", t.textMuted, t.bg)
    ui.write(2, 11, C.OS_VERSION, t.accent, t.bg)

    ui.button({ x = 2, y = 14, width = 14, label = "Logout", style = "danger" })
    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if my == 14 and mx >= 2 and mx <= 15 then
            net.clearSession()
            ui.dialog({ title = "Logged out",
                         message = "Session cleared. Reboot to log in again.",
                         buttons = {{ label = "OK", value = true }}})
            return
        end
        if my == H and mx <= 3 then return end
    end
end

local function sectionAppearance()
    local t      = Theme.get()
    local themes = Theme.list()
    local curId  = Theme.currentId()
    local sel    = 1
    for i, th in ipairs(themes) do if th.id == curId then sel = i end end

    local function redraw()
        t = Theme.get()
        ui.clear()
        term.setCursorPos(1, 1)
        term.setBackgroundColor(t.accent)
        term.setTextColor(t.textOnAccent)
        term.write(utils.padRight(" Appearance", W))
        ui.write(2, 3, "Theme:", t.textMuted, t.bg)
        for i, th in ipairs(themes) do
            local isSel = (i == sel)
            local bg = isSel and t.accent or t.bg
            local fg = isSel and t.textOnAccent or t.text
            term.setCursorPos(2, 4 + i)
            term.setBackgroundColor(bg)
            term.setTextColor(fg)
            term.write(utils.padRight((isSel and "> " or "  ") .. th.name, W - 2))
        end
        ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
    end

    redraw()
    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if my == H and mx <= 3 then return end
        for i = 1, #themes do
            if my == 4 + i then
                sel = i
                Theme.set(themes[i].id)
                redraw()
                break
            end
        end
    end
end

local function sectionSecurity()
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" Security", W))

    ui.write(2, 4, "Change PIN:", t.text, t.bg)
    ui.button({ x = 2, y = 5, width = 12, label = "Change PIN" })
    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if my == H and mx <= 3 then return end
        if my == 5 and mx >= 2 and mx <= 13 then
            -- Rerun PIN setup
            dofile("/system/setup/wizard.lua")  -- or a standalone PIN change flow
            return
        end
    end
end

local function sectionNetwork()
    local t      = Theme.get()
    local online = net.isOnline()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" Network", W))

    ui.write(2, 4, "Status:", t.textMuted, t.bg)
    ui.write(2, 5, online and "Online" or "Offline", online and t.success or t.danger, t.bg)
    ui.write(2, 7, "Protocol: " .. C.PROTOCOL_NAME, t.textMuted, t.bg)
    ui.write(2, 8, "Version: " .. C.PROTOCOL_VERSION, t.textMuted, t.bg)

    ui.button({ x = 2, y = 11, width = 12, label = "Test Conn." })
    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if my == H and mx <= 3 then return end
        if my == 11 then
            local ok = net.isOnline()
            ui.toast({ text = ok and "Connected!" or "Offline.", type = ok and "success" or "error", y = H - 1 })
            os.sleep(1.5)
        end
    end
end

local function sectionNotifs()
    local t   = Theme.get()
    local dnd = notif.isDND()

    local function redraw()
        t = Theme.get()
        dnd = notif.isDND()
        ui.clear()
        term.setCursorPos(1, 1)
        term.setBackgroundColor(t.accent)
        term.setTextColor(t.textOnAccent)
        term.write(utils.padRight(" Notifications", W))

        ui.write(2, 4, "Do Not Disturb:", t.text, t.bg)
        ui.switch({ x = 2, y = 5, value = dnd, label = "DND Mode" })
        ui.write(2, 7, "Unread: " .. notif.unreadCount(), t.textMuted, t.bg)
        ui.button({ x = 2, y = 9, width = 14, label = "Clear All", style = "danger" })
        ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
    end

    redraw()
    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if my == H and mx <= 3 then return end
        if my == 5 and mx >= 2 and mx <= 6 then
            notif.setDND(not dnd); redraw()
        end
        if my == 9 and mx >= 2 and mx <= 15 then
            notif.clear(); redraw()
        end
    end
end

local function sectionStorage()
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" Storage", W))

    local function dirSize(path)
        if not fs.exists(path) then return 0 end
        local total = 0
        local ok, list = pcall(fs.list, path)
        if not ok then return 0 end
        for _, name in ipairs(list) do
            local full = fs.combine(path, name)
            if fs.isDir(full) then total = total + dirSize(full)
            else total = total + (fs.getSize(full) or 0) end
        end
        return total
    end

    local sections = {
        { label = "Config",    path = C.PATH_CONFIG },
        { label = "Cache",     path = C.PATH_CACHE },
        { label = "User Data", path = C.PATH_USER },
        { label = "Logs",      path = C.PATH_LOGS },
    }

    for i, s in ipairs(sections) do
        local sz = dirSize(s.path)
        ui.write(2, 3 + i, s.label .. ":", t.textMuted, t.bg)
        ui.write(14, 3 + i, utils.padLeft(math.floor(sz / 1024) .. "KB", 6), t.text, t.bg)
    end

    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if my == H and mx <= 3 then return end
    end
end

local function sectionUpdate()
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" Update", W))

    ui.write(2, 4, "System Update", t.accent, t.bg)
    ui.write(2, 6, "This will back up your", t.textMuted, t.bg)
    ui.write(2, 7, "data, wipe the phone,", t.textMuted, t.bg)
    ui.write(2, 8, "and re-run setup.", t.textMuted, t.bg)

    ui.button({ x = 2, y = 11, width = 14, label = "Update & Wipe", style = "danger" })
    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if my == H and mx <= 3 then return end
        if my == 11 and mx >= 2 and mx <= 15 then
            ui.dialog({
                title = "Update System",
                message = "Are you sure you want to back up and wipe?",
                buttons = {
                    { label = "Cancel", value = false },
                    { label = "Yes, Wipe", value = true }
                }
            })
            local _, ev = os.pullEvent("dorpos_dialog_result")
            if ev.value == true then
                ui.clear()
                ui.write(2, 5, "Backing up data...", t.accent, t.bg)
                os.sleep(0.5)

                -- 1. Package /data
                local backupData = {}
                if fs.exists("/data") then
                    for _, file in ipairs(fs.list("/data")) do
                        if file:sub(-4) == ".dat" then
                            local path = "/data/" .. file
                            local f = io.open(path, "r")
                            if f then
                                local raw = f:read("*a")
                                f:close()
                                local ok, tData = pcall(textutils.unserialise, raw)
                                if ok and type(tData) == "table" then
                                    backupData[file] = tData
                                end
                            end
                        end
                    end
                end

                -- 2. Send backup
                local ok = net.post(C.HOST_ACCOUNTS, "/account/backup", { data = backupData })
                if not ok then
                    ui.toast({ text = "Backup failed!", type = "error", y = H - 1 })
                    os.sleep(2)
                    return
                end

                ui.clear()
                ui.write(2, 5, "Backup complete.", t.success, t.bg)
                ui.write(2, 7, "Wiping phone...", t.danger, t.bg)
                os.sleep(1)

                -- 3. Wipe phone
                if fs.exists("/boot.lua") then fs.delete("/boot.lua") end
                if fs.exists("/data") then
                    -- Delete phone-specific config files, but preserve server data
                    -- in case the phone and server are running on the same computer
                    local phoneFiles = {
                        "user_config.dat", "session.dat", "setup_wizard.dat",
                        "notifications.dat", "pin.dat", "messages.dat",
                        "contacts.dat", "marketplace.dat", "theme.json", "user.json"
                    }
                    for _, f in ipairs(phoneFiles) do
                        if fs.exists("/data/" .. f) then fs.delete("/data/" .. f) end
                    end
                    local phoneDirs = { "config", "cache", "user", "logs", "downloads" }
                    for _, d in ipairs(phoneDirs) do
                        if fs.exists("/data/" .. d) then fs.delete("/data/" .. d) end
                    end
                end

                -- 4. Reboot into provisioning
                os.reboot()
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Main loop
-- ─────────────────────────────────────────────────────────────

local _hits = drawMenu()

while true do
    local ev = { os.pullEvent() }
    if ev[1] == "mouse_click" then
        local mx, my = ev[3], ev[4]
        if my == H and mx <= 3 then return end

        for _, h in ipairs(_hits) do
            if my == h.y then
                if     h.id == "profile"    then sectionProfile()
                elseif h.id == "appearance" then sectionAppearance()
                elseif h.id == "security"   then sectionSecurity()
                elseif h.id == "network"    then sectionNetwork()
                elseif h.id == "notifs"     then sectionNotifs()
                elseif h.id == "storage"    then sectionStorage()
                elseif h.id == "update"     then sectionUpdate()
                elseif h.id == "about"      then
                    os.queueEvent("dorpos_launch_app", C.APP_ABOUT)
                    return
                end
                _hits = drawMenu()
                break
            end
        end
    end
end
