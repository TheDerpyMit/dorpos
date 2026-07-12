--[[
    DorpOS :: phone/kernel.lua
    ──────────────────────────
    Central kernel — the heart of DorpOS.

    Responsibilities:
        - Central event dispatcher (parallel coroutines)
        - Launch and manage applications via app_manager
        - Handle notification banners
        - Background services: network polling, update checks
        - Crash recovery (display error screen, return to home)
        - Clean shutdown / reboot

    The kernel runs an infinite event loop. Every subsystem hooks into
    this loop by registering a handler coroutine.
]]

if package then
    package.path = "/?.lua;/?/init.lua;/shared/?.lua;/system/?.lua;/servers/?.lua;" .. (package.path or "")
else
    pcall(dofile, "/shared/shim.lua")
end

local C       = require("shared.constants")
local log     = require("system.utils.logger")
local Theme   = require("system.theme.theme")
local ui      = require("system.ui.ui")
local net     = require("system.network.network")
local notif   = require("system.services.notification_manager")
local updater = require("system.services.updater")
local appMgr  = require("system.services.app_manager")
local utils   = require("system.utils.utils")
local anim    = require("system.animation.animation")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT

-- ─────────────────────────────────────────────────────────────
-- Discovery responder: reply to nearby phone scans
-- ─────────────────────────────────────────────────────────────

local Storage = require("system.storage.storage")

local function discoveryResponder()
    local PROTO = "dorpos_discover"
    while true do
        -- Wait for an incoming discovery ping
        local senderId, msg = rednet.receive(PROTO, 5)
        if senderId and type(msg) == "table" and msg.type == "dorpos.discover" then
            -- Reply with our username so the scanner can add us
            local userStore  = Storage.open("user_config")
            local myUsername = userStore.get("username", nil)
            if myUsername then
                rednet.send(senderId, {
                    type     = "dorpos.discover.reply",
                    username = myUsername,
                }, PROTO)
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Kernel state
-- ─────────────────────────────────────────────────────────────

local _running        = true
local _lastUpdateCheck = 0
local _lastNotifPoll  = 0
local _updateReady    = false
local _updateVersion  = nil

-- ─────────────────────────────────────────────────────────────
-- Error screen
-- ─────────────────────────────────────────────────────────────

local function showCrashScreen(appId, err)
    local t = Theme.get()
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    term.write(utils.centre("APP CRASHED", W))
    term.setCursorPos(1, 3)
    term.write(utils.centre(appId or "unknown", W))

    -- Wrap error message
    local lines = utils.wrap(tostring(err), W - 2)
    for i, line in ipairs(lines) do
        if i > 8 then break end
        term.setCursorPos(2, 4 + i)
        term.write(line)
    end

    term.setCursorPos(1, H - 1)
    term.setBackgroundColor(colors.white)
    term.setTextColor(colors.red)
    term.write(utils.centre("Tap to return home", W))

    os.pullEvent("mouse_click")
end

-- ─────────────────────────────────────────────────────────────
-- Notification banner
-- ─────────────────────────────────────────────────────────────

local function showNotifBanner(n)
    local t = Theme.get()
    local drawBg = function()
        -- We don't redraw the app bg — just clear the banner row
        term.setCursorPos(1, 1)
        term.setBackgroundColor(t.bg)
        term.write(string.rep(" ", W))
        term.setCursorPos(1, 2)
        term.write(string.rep(" ", W))
    end
    local drawToast = function()
        term.setCursorPos(1, 1)
        term.setBackgroundColor(t.accent)
        term.setTextColor(t.textOnAccent)
        term.write(utils.padRight(" " .. (n.title or ""), W))
        term.setCursorPos(1, 2)
        term.setBackgroundColor(t.bgCard)
        term.setTextColor(t.text)
        term.write(utils.padRight(" " .. utils.truncate(n.body or "", W - 2), W))
    end
    anim.toast(drawBg, drawToast, 2.5)
end

-- ─────────────────────────────────────────────────────────────
-- Background services (called from event loop periodically)
-- ─────────────────────────────────────────────────────────────

local function runBackgroundServices()
    local now = os.epoch("utc") / 1000

    -- Update check
    if now - _lastUpdateCheck >= C.UPDATE_POLL_INTERVAL then
        _lastUpdateCheck = now
        -- Run in a coroutine so it doesn't block
        local co = coroutine.create(function()
            local ok = updater.run()
            if ok then
                _updateReady = true
                notif.push({
                    title    = "DorpOS Update",
                    body     = "A system update is ready. Restart to apply.",
                    type     = "info",
                    priority = 1,
                })
            end
        end)
        coroutine.resume(co)
    end

    -- Notification poll (ping the notifications server)
    if now - _lastNotifPoll >= C.NOTIF_POLL_INTERVAL then
        _lastNotifPoll = now
        local co = coroutine.create(function()
            local ok, resp = net.post(C.HOST_NOTIFICATIONS, "/notifications/poll", {})
            if ok and resp.body.notifications then
                for _, n in ipairs(resp.body.notifications) do
                    notif.push(n)
                end
            end
            -- Flush offline message queue
            net.flushQueue()
        end)
        coroutine.resume(co)
    end
end

-- ─────────────────────────────────────────────────────────────
-- Main kernel loop
-- ─────────────────────────────────────────────────────────────

log.info("kernel", "Kernel started")

-- Initialise network (may already be initialised from boot.lua)
net.init()

-- Launch home screen (blocks until user opens an app or the app exits)
local function runHome()
    local ok, err = appMgr.launch(C.APP_HOME)
    if not ok then
        log.error("kernel", "Home screen crashed", { err = err })
        showCrashScreen(C.APP_HOME, err)
    end
end

-- Handle dorpos_ events from other parts of the system
-- These are co-processed in the kernel by checking the event queue
-- before re-entering the home screen loop.
local function processSystemEvents()
    while true do
        local ev = { os.pullEvent() }
        local name = ev[1]

        if name == "dorpos_notification" then
            showNotifBanner(ev[2])

        elseif name == "dorpos_update_ready" then
            _updateVersion = ev[2]
            log.info("kernel", "Update ready", { version = _updateVersion })

        elseif name == "dorpos_launch_app" then
            local id   = ev[2]
            local args = ev[3]
            local ok, err = appMgr.launch(id, args)
            if not ok then
                showCrashScreen(id, err)
            end

        elseif name == "dorpos_shutdown" then
            log.info("kernel", "Shutdown requested")
            _running = false
            return

        elseif name == "dorpos_reboot" then
            log.info("kernel", "Reboot requested")
            os.reboot()
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Real-time push listener
-- ─────────────────────────────────────────────────────────────

local function realtimePushListener()
    while true do
        local senderId, msg = rednet.receive(C.PROTOCOL_NAME)
        if type(msg) == "table" and msg.type then
            if msg.type == "dorpos.message" then
                os.queueEvent("dorpos_message_received", msg)
            elseif msg.type == "dorpos.friend_update" then
                os.queueEvent("dorpos_friend_update", msg)
            end
        end
    end
end

parallel.waitForAny(
    function()
        while _running do
            -- Dispatch background services
            runBackgroundServices()

            -- Run home screen
            runHome()

            -- After home returns (shouldn't normally happen — home is the root)
            -- Re-launch it to keep the kernel alive
            log.warn("kernel", "Home screen exited — relaunching")
            os.sleep(0.5)
        end
    end,
    processSystemEvents,
    discoveryResponder, -- replies to nearby phones scanning for friends
    realtimePushListener
)

log.info("kernel", "Kernel shutting down")
