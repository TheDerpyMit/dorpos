--[[
    DorpOS :: phone/boot.lua
    ─────────────────────────
    Main boot loader. Runs after startup.lua confirms the OS is installed.

    Boot sequence:
        Animated DorpOS logo
        → Hardware check
        → Filesystem check
        → Network initialisation
        → Activation check (contact server if no token)
        → First-run check (launch setup wizard if no user config)
        → Lock screen
        → Hand off to kernel
]]

-- ─────────────────────────────────────────────────────────────
-- Require paths — add /system and /shared to package.path
pcall(dofile, "/shared/shim.lua")

local C     = require("shared.constants")
local log   = require("system.utils.logger")
local Theme = require("system.theme.theme")
local net   = require("system.network.network")
local anim  = require("system.animation.animation")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT

-- ─────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────

local function cls()
    local t = Theme.get()
    term.setBackgroundColor(t.bg)
    term.setTextColor(t.text)
    term.clear()
    term.setCursorPos(1, 1)
end

local function cwrite(y, text, fg, bg)
    local t = Theme.get()
    term.setCursorPos(math.floor((W - #text) / 2) + 1, y)
    term.setTextColor(fg or t.text)
    term.setBackgroundColor(bg or t.bg)
    term.write(text)
end

local function statusLine(msg)
    local t = Theme.get()
    term.setCursorPos(1, H)
    term.setBackgroundColor(t.bg)
    term.setTextColor(t.textMuted)
    term.write(string.rep(" ", W))
    term.setCursorPos(1, H)
    term.write(msg:sub(1, W))
end

-- ─────────────────────────────────────────────────────────────
-- Boot screens
-- ─────────────────────────────────────────────────────────────

local function logoScreen()
    Theme.load("dark")
    cls()

    -- ASCII logo (fits in 26 cols)
    local logo = {
        " ____             ",
        "|  _ \\ ___  _ __ ",
        "| | | / _ \\| '__|",
        "| |_| | (_) | |  ",
        "|____/ \\___/|_|  ",
    }

    local startY = math.floor((H - #logo - 3) / 2) + 1
    for i, line in ipairs(logo) do
        cwrite(startY + i - 1, line, colors.cyan, colors.black)
    end
    cwrite(startY + #logo + 1, "OS", colors.lightGray, colors.black)

    -- Loading dots animation
    for dots = 1, 3 do
        cwrite(startY + #logo + 2, "Loading" .. string.rep(".", dots), colors.gray, colors.black)
        os.sleep(0.35)
    end
    os.sleep(0.3)
end

local function checkScreen(label, result, ok)
    local t = Theme.get()
    local icon = ok and "\4" or "x"
    local fg   = ok and t.success or t.danger
    statusLine(icon .. " " .. label .. (result and (": " .. result) or ""))
    os.sleep(0.1)
end

-- ─────────────────────────────────────────────────────────────
-- Hardware check
-- ─────────────────────────────────────────────────────────────

local function hardwareCheck()
    statusLine("Checking hardware...")
    local modem = peripheral.find("modem")
    checkScreen("Modem", modem and "OK" or "MISSING", modem ~= nil)
    if not modem then
        os.sleep(2)
        -- Continue anyway — phone can still run offline
    end

    local isPocket = pocket ~= nil  -- pocket API exists on pocket computers
    checkScreen("Device type", isPocket and "Pocket" or "Computer", true)
    os.sleep(0.05)
end

-- ─────────────────────────────────────────────────────────────
-- Filesystem check
-- ─────────────────────────────────────────────────────────────

local function filesystemCheck()
    statusLine("Checking filesystem...")

    local dirs = {
        C.PATH_DATA, C.PATH_CONFIG, C.PATH_CACHE,
        C.PATH_USER, C.PATH_LOGS, C.PATH_DOWNLOADS,
    }
    for _, dir in ipairs(dirs) do
        if not fs.exists(dir) then
            fs.makeDir(dir)
        end
    end
    checkScreen("Filesystem", "OK", true)
    os.sleep(0.05)
end

-- ─────────────────────────────────────────────────────────────
-- Network check
-- ─────────────────────────────────────────────────────────────

local function networkCheck()
    statusLine("Connecting to network...")
    net.init()
    local online = net.isOnline()
    checkScreen("Network", online and "Online" or "Offline", online)
    if not online then
        log.warn("boot", "Network offline at boot")
    end
    os.sleep(0.1)
end

-- ─────────────────────────────────────────────────────────────
-- Activation check
-- ─────────────────────────────────────────────────────────────

local function activationCheck()
    local session = net.getSession()
    if session then
        checkScreen("Session", "Valid", true)
        return true
    end

    statusLine("Activating device...")
    log.info("boot", "No session — contacting activation server")

    local ok, resp = net.postAnon(C.HOST_ACTIVATION, "/activate", {
        deviceId  = os.getComputerID(),
        osVersion = C.OS_VERSION,
    })

    if ok and resp.body.token then
        net.saveSession(resp.body.token)
        checkScreen("Activation", "OK", true)
        return true
    else
        checkScreen("Activation", "FAILED", false)
        log.error("boot", "Activation failed", { resp = resp })
        return false
    end
end

-- ─────────────────────────────────────────────────────────────
-- First run check
-- ─────────────────────────────────────────────────────────────

local function isFirstRun()
    return not fs.exists(C.FILE_USER_CONFIG)
end

-- ─────────────────────────────────────────────────────────────
-- Main boot sequence
-- ─────────────────────────────────────────────────────────────

log.info("boot", "Boot started", { version = C.OS_VERSION })

-- Step 1: logo
logoScreen()

-- Step 2: load user theme from config (or default dark)
Theme.get()  -- triggers auto-load from saved config
cls()
statusLine("DorpOS " .. C.OS_VERSION)

-- Step 3: checks
hardwareCheck()
filesystemCheck()
networkCheck()
activationCheck()

os.sleep(0.3)
cls()

-- Step 4: first run or normal boot
if isFirstRun() then
    log.info("boot", "First run — launching setup wizard")
    dofile("/system/setup/wizard.lua")
else
    log.info("boot", "Launching lock screen")
    dofile("/apps/lockscreen/init.lua")
end

-- Step 5: after lock screen unlocks, launch kernel
log.info("boot", "Launching kernel")
dofile("/kernel.lua")
