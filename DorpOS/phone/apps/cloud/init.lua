--[[  DorpOS :: phone/apps/cloud/init.lua
    Cloud sync — backup and restore user data to/from the Cloud server.
]]
local C       = require("shared.constants")
local ui      = require("system.ui.ui")
local Theme   = require("system.theme.theme")
local Storage = require("system.storage.storage")
local net     = require("system.network.network")
local utils   = require("system.utils.utils")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT

local SYNC_STORES = { "user_config", "contacts", "notes", "calendar", "home_prefs", "theme" }

local function doBackup()
    local data = {}
    for _, name in ipairs(SYNC_STORES) do
        local s = Storage.open(name)
        data[name] = s.getAll()
    end
    local ok, resp = net.post(C.HOST_CLOUD, "/cloud/backup", { data = data })
    return ok, resp
end

local function doRestore()
    local ok, resp = net.post(C.HOST_CLOUD, "/cloud/restore", {})
    if not ok then return false, resp end
    local data = resp.body.data
    if not data then return false, { message = "No backup found" } end
    for name, vals in pairs(data) do
        local s = Storage.open(name)
        for k, v in pairs(vals) do s.set(k, v) end
        s.save()
    end
    return true, resp
end

local status = ""

local function draw()
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" Cloud Sync", W))

    ui.write(2, 4, "Syncs the following:", t.textMuted, t.bg)
    for i, name in ipairs(SYNC_STORES) do
        ui.write(3, 4 + i, "- " .. name, t.text, t.bg)
    end

    ui.divider(4 + #SYNC_STORES + 1)

    ui.button({ x = 2, y = 4 + #SYNC_STORES + 3, width = 14, label = "Backup to Cloud" })
    ui.button({ x = 2, y = 4 + #SYNC_STORES + 5, width = 16, label = "Restore from Cloud" })

    if #status > 0 then
        ui.write(2, 4 + #SYNC_STORES + 7, status, t.info, t.bg)
    end

    ui.button({ x = 1, y = H, width = 6, label = "Back", style = "ghost" })
end

draw()

while true do
    local _, _, mx, my = os.pullEvent("mouse_click")
    local baseY = 4 + #SYNC_STORES + 3
    if my == H and mx <= 6 then return end
    if my == baseY then
        status = "Backing up..."
        draw()
        local ok, resp = doBackup()
        status = ok and "Backup complete!" or ("Failed: " .. (resp.message or "?"))
        draw()
    elseif my == baseY + 2 then
        status = "Restoring..."
        draw()
        local ok, resp = doRestore()
        status = ok and "Restored! Restart recommended." or ("Failed: " .. (resp.message or "?"))
        draw()
    end
end
