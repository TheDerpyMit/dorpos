--[[  DorpOS :: phone/apps/about/init.lua  ]]
local C       = require("shared.constants")
local ui      = require("system.ui.ui")
local Theme   = require("system.theme.theme")
local Storage = require("system.storage.storage")
local net     = require("system.network.network")
local utils   = require("system.utils.utils")
local log     = require("system.utils.logger")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT

local function drawAbout()
    local t    = Theme.get()
    local uc   = Storage.open("user_config")
    local cfg  = Storage.open("install")

    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" About DorpOS", W))

    local rows = {
        { "OS",          C.OS_NAME .. " " .. C.OS_VERSION },
        { "Protocol",    C.PROTOCOL_NAME .. " v" .. C.PROTOCOL_VERSION },
        { "Device ID",   tostring(os.getComputerID()) },
        { "Username",    uc.get("username", "?") },
        { "Theme",       Theme.currentId() },
        { "Network",     net.isOnline() and "Online" or "Offline" },
    }

    for i, row in ipairs(rows) do
        ui.write(2,  2 + i, row[1] .. ":", t.textMuted, t.bg)
        ui.write(14, 2 + i, row[2],        t.text,      t.bg)
    end

    ui.divider(2 + #rows + 1)

    -- Log tail
    ui.write(2, 2 + #rows + 2, "Recent log:", t.textMuted, t.bg)
    local lines = log.tail(5)
    for i, line in ipairs(lines) do
        term.setCursorPos(1, 2 + #rows + 2 + i)
        term.setBackgroundColor(t.bgCard)
        term.setTextColor(t.textMuted)
        term.write(utils.padRight(utils.truncate(line, W), W))
    end

    -- Credits
    ui.write(2, H - 2, "Made for ComputerCraft:T", t.textMuted, t.bg)
    ui.write(2, H - 1, "DorpOS " .. C.OS_VERSION, t.accent, t.bg)
    ui.button({ x = 1, y = H, width = 6, label = "Back", style = "ghost" })
    ui.button({ x = W - 7, y = H, width = 7, label = "Root", style = "danger" })
end

drawAbout()

while true do
    local _, _, mx, my = os.pullEvent("mouse_click")
    if my == H and mx <= 6 then
        return
    elseif my == H and mx >= W - 7 then
        local res = ui.dialog({
            title = "Root Device?",
            message = "Void warranty? Phone will no longer be supported.",
            buttons = {
                { label = "Cancel", style = "ghost", value = false },
                { label = "Root", style = "danger", value = true }
            }
        })
        if res then
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.red)
            term.clear()
            term.setCursorPos(1, math.floor(H / 2))
            term.write(utils.centre("ROOTING DEVICE...", W))
            term.setCursorPos(1, math.floor(H / 2) + 2)
            term.setTextColor(colors.lightGray)
            term.write(utils.centre("Warranty Voided.", W))
            os.sleep(1.5)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            term.clear()
            term.setCursorPos(1, 1)
            os.queueEvent("dorpos_shutdown")
            return
        else
            drawAbout()
        end
    end
end
