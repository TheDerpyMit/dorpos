--[[
    DorpOS :: phone/system/setup/wizard.lua
    ────────────────────────────────────────
    First-boot setup wizard. Runs only when no user config exists.

    Steps:
        1. Welcome
        2. Theme selection
        3. Network (REQUIRED — must be online)
        4. Account — choose Register OR Login (server must succeed, no offline fallback)
        5. Create PIN
        6. Permissions notice
        7. Tutorial
        8. Finish → Home screen

    No local accounts are allowed. The user MUST successfully authenticate
    with the DorpOS Accounts Server before setup can complete.
]]

local C       = require("shared.constants")
local ui      = require("system.ui.ui")
local Theme   = require("system.theme.theme")
local Storage = require("system.storage.storage")
local net     = require("system.network.network")
local sha     = require("system.crypto.sha256")
local utils   = require("system.utils.utils")
local log     = require("system.utils.logger")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT
local kbComp = require("system.ui.components.keyboard")

local state = Storage.open("setup_wizard")

-- ─────────────────────────────────────────────────────────────
-- Shared UI helpers
-- ─────────────────────────────────────────────────────────────

local function header(title, step, total)
    local t = Theme.get()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" Setup  " .. step .. "/" .. total, W))
    ui.write(2, 3, title, t.text, t.bg)
    ui.divider(4)
end

local function nextButton(y)
    return ui.button({ x = W - 8, y = y or H - 1, width = 8, label = "Next >", style = "primary" })
end

local function backButton(y)
    return ui.button({ x = 1, y = y or H - 1, width = 8, label = "< Back", style = "ghost" })
end

local function waitNext(nb, bb)
    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if nb and nb.hit and nb.hit(mx, my) then return "next" end
        if bb and bb.hit and bb.hit(mx, my) then return "back" end
    end
end

-- Single on-screen-keyboard input field.
-- Returns the typed value. Never returns nil.
local function inputField(label, y, isPassword, initial)
    local t      = Theme.get()
    local value  = initial or ""
    local shifted = false
    local kbHits  = nil

    local KBY = H - 7  -- keyboard top row (leaves room for content above)

    local function redraw()
        -- Clear field + status rows
        for row = y, KBY - 1 do
            term.setCursorPos(1, row)
            term.setBackgroundColor(t.bg)
            term.write(string.rep(" ", W))
        end
        ui.write(2, y, label .. ":", t.textMuted, t.bg)
        ui.textbox({ x = 2, y = y + 1, width = W - 3,
                     value = value, password = isPassword, focused = true })
        -- "Done" button sits just above the keyboard
        ui.button({ x = W - 7, y = KBY - 1, width = 7, label = "Done" })

        kbHits = kbComp.draw({
            y = KBY, shifted = shifted,
            onChar  = function(c) if #value < 64 then value = value .. c end end,
            onBack  = function() if #value > 0 then value = value:sub(1, -2) end end,
            onEnter = function() end,   -- treated as Done
            onShift = function() shifted = not shifted end,
            onClose = function() end,
        })
    end

    redraw()

    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if kbHits and kbComp.handleClick(kbHits, mx, my) then
                redraw()
            elseif my == KBY - 1 and mx >= W - 7 then
                break  -- Done button
            end
        elseif ev[1] == "char" then
            if #value < 64 then value = value .. ev[2] end
            redraw()
        elseif ev[1] == "key" then
            if ev[2] == keys.backspace and #value > 0 then
                value = value:sub(1, -2); redraw()
            elseif ev[2] == keys.enter then
                break
            end
        end
    end

    term.setCursorBlink(false)
    return value
end

-- Show a status / error message in a fixed area (row 6 area)
local function showMsg(msg, color, y)
    local t = Theme.get()
    local row = y or 6
    term.setCursorPos(1, row)
    term.setBackgroundColor(t.bg)
    term.write(string.rep(" ", W))
    if msg and msg ~= "" then
        ui.write(2, row, utils.truncate(msg, W - 2), color or t.danger, t.bg)
    end
end

-- ─────────────────────────────────────────────────────────────
-- Step 1: Welcome
-- ─────────────────────────────────────────────────────────────

local function stepWelcome()
    local t = Theme.get()
    ui.clear()
    header("Welcome", 1, 7)

    ui.write(2, 6,  "Welcome to DorpOS!", t.accent, t.bg)
    ui.write(2, 8,  "This wizard sets up", t.text, t.bg)
    ui.write(2, 9,  "your phone in ~2 min.", t.text, t.bg)
    ui.write(2, 11, "You need a server", t.textMuted, t.bg)
    ui.write(2, 12, "connection to continue.", t.textMuted, t.bg)

    local nb = nextButton()
    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if nb.hit(mx, my) then return end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Step 2: Theme
-- ─────────────────────────────────────────────────────────────

local function stepTheme()
    local themes = Theme.list()
    local sel    = 1
    local t      = Theme.get()

    local function redraw()
        t = Theme.get()
        ui.clear()
        header("Choose Theme", 2, 7)
        for i, th in ipairs(themes) do
            local isSel = (i == sel)
            local bg = isSel and t.accent or t.bgCard
            local fg = isSel and t.textOnAccent or t.text
            ui.rect(2, 5 + (i - 1) * 2, W - 3, 1, bg)
            ui.write(2, 5 + (i - 1) * 2, (isSel and "> " or "  ") .. th.name, fg, bg)
        end
        nextButton(); backButton()
    end

    redraw()
    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        for i = 1, #themes do
            local ry = 5 + (i - 1) * 2
            if my == ry and mx >= 2 and mx <= W - 1 then
                sel = i; Theme.set(themes[i].id); redraw()
            end
        end
        if my == H - 1 and mx >= W - 8 then
            state.set("themeId", themes[sel].id); state.save(); return
        end
        if my == H - 1 and mx <= 8 then return "back" end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Step 3: Network — must be online
-- ─────────────────────────────────────────────────────────────

local function stepNetwork()
    local function draw(online)
        local t = Theme.get()
        ui.clear()
        header("Network", 3, 7)
        if online then
            ui.write(2, 6, "\4 Connected!", t.success, t.bg)
            ui.write(2, 8, "Great — the server is", t.text, t.bg)
            ui.write(2, 9, "reachable. Let's go!", t.text, t.bg)
            nextButton(); backButton()
        else
            ui.write(2, 6, "x No Server Found", t.danger, t.bg)
            ui.write(2, 8, "DorpOS requires a", t.text, t.bg)
            ui.write(2, 9, "server connection.", t.text, t.bg)
            ui.write(2, 11, "Make sure the server", t.textMuted, t.bg)
            ui.write(2, 12, "computer is running.", t.textMuted, t.bg)
            ui.button({ x = W - 10, y = H - 1, width = 10, label = "Retry...", style = "primary" })
            backButton()
        end
        return online
    end

    local online = net.isOnline()
    draw(online)

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if my == H - 1 then
            if mx <= 8 then return "back" end
            if online and mx >= W - 8 then return "next" end
            if not online then
                -- Retry
                ui.write(2, 6, "  Checking...", Theme.get().textMuted, Theme.get().bg)
                os.sleep(0.4)
                online = net.isOnline()
                draw(online)
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Step 4: Account — Login OR Register
-- No local fallback. Must authenticate with server.
-- ─────────────────────────────────────────────────────────────

-- 4a: Choose path
local function stepAccountChoice()
    local t = Theme.get()
    ui.clear()
    header("Your Account", 4, 7)

    ui.write(2, 6, "How do you want to", t.text, t.bg)
    ui.write(2, 7, "use DorpOS?", t.text, t.bg)

    -- Two big tap-target buttons
    ui.rect(2, 9,  W - 3, 1, t.accent)
    ui.write(3, 9, "  Create a new account", t.textOnAccent, t.accent)

    ui.rect(2, 11, W - 3, 1, t.bgCard)
    ui.write(3, 11, "  Sign in to existing", t.text, t.bgCard)

    ui.write(2, H - 2, "Server must be online.", t.textMuted, t.bg)
    backButton()

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if my == 9  and mx >= 2 and mx <= W - 1 then return "register" end
        if my == 11 and mx >= 2 and mx <= W - 1 then return "login" end
        if my == H - 1 and mx <= 8 then return "back" end
    end
end

-- 4b: Register flow
local function stepRegister()
    local t = Theme.get()

    ::retry::

    -- ── Username ──────────────────────────────────────────────
    ui.clear()
    header("Create Account", 4, 7)
    ui.write(2, 5, "Pick a username.", t.text, t.bg)
    ui.write(2, 6, "3+ letters/digits/_ only", t.textMuted, t.bg)

    local username = inputField("Username", 7, false, state.get("reg_user", ""))

    username = username:lower():gsub("%s+", "")
    if #username < 3 then
        ui.clear(); header("Create Account", 4, 7)
        showMsg("Min 3 characters!", t.danger, 6)
        os.sleep(1.5); goto retry
    end
    if not username:match("^[a-z0-9_]+$") then
        ui.clear(); header("Create Account", 4, 7)
        showMsg("Letters/digits/_ only!", t.danger, 6)
        os.sleep(1.5); goto retry
    end
    state.set("reg_user", username); state.save()

    -- ── Password ──────────────────────────────────────────────
    ui.clear()
    header("Create Account", 4, 7)
    ui.write(2, 5, "Create a password.", t.text, t.bg)
    ui.write(2, 6, "Minimum 6 characters.", t.textMuted, t.bg)

    local pass1 = inputField("Password", 7, true, "")

    if #pass1 < 6 then
        ui.clear(); header("Create Account", 4, 7)
        showMsg("Password too short! (min 6)", t.danger, 6)
        os.sleep(1.5); goto retry
    end

    -- ── Confirm password ──────────────────────────────────────
    ui.clear()
    header("Create Account", 4, 7)
    ui.write(2, 5, "Confirm your password.", t.text, t.bg)

    local pass2 = inputField("Confirm", 7, true, "")

    if pass1 ~= pass2 then
        ui.clear(); header("Create Account", 4, 7)
        showMsg("Passwords don't match!", t.danger, 6)
        os.sleep(1.5); goto retry
    end

    -- ── Submit to server ──────────────────────────────────────
    ui.clear()
    header("Create Account", 4, 7)
    ui.write(2, 6, "Creating account...", t.textMuted, t.bg)

    local passHash = sha.hash(pass1)
    local ok, resp = net.postAnon(C.HOST_ACCOUNTS, "/account/create", {
        username = username,
        passHash = passHash,
        deviceId = os.getComputerID(),
    })

    if ok and resp.body and resp.body.token then
        net.saveSession(resp.body.token)
        local savedName = (resp.body.username and #resp.body.username > 0)
                          and resp.body.username or username
        state.set("username", savedName)
        state.delete("reg_user")
        state.save()
        ui.write(2, 8,  "\4 Account created!", t.success, t.bg)
        ui.write(2, 9,  "Welcome, " .. savedName .. "!", t.text, t.bg)
        os.sleep(1.2)
        return savedName
    end

    -- ── Server error handling ─────────────────────────────────
    local errMsg = "Server error. Try again."
    if resp and resp.body and resp.code == 409 then
        errMsg = "Username '" .. username .. "' is taken!"
    elseif not net.isOnline() then
        errMsg = "Server offline. Retry."
    end

    ui.clear(); header("Create Account", 4, 7)
    showMsg(errMsg, t.danger, 6)
    ui.write(2, 8, "You must register with", t.text, t.bg)
    ui.write(2, 9, "the server to continue.", t.text, t.bg)
    ui.button({ x = W - 10, y = H - 1, width = 10, label = "Try Again", style = "primary" })

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if my == H - 1 and mx >= W - 10 then goto retry end
    end
end

-- 4c: Login flow
local function stepLogin()
    local t = Theme.get()

    ::retry::

    -- ── Username ──────────────────────────────────────────────
    ui.clear()
    header("Sign In", 4, 7)
    ui.write(2, 5, "Enter your username.", t.text, t.bg)

    local username = inputField("Username", 7, false, state.get("login_user", ""))
    username = username:lower():gsub("%s+", "")
    if #username == 0 then goto retry end
    state.set("login_user", username); state.save()

    -- ── Password ──────────────────────────────────────────────
    ui.clear()
    header("Sign In", 4, 7)
    ui.write(2, 5, "Enter your password.", t.text, t.bg)

    local password = inputField("Password", 7, true, "")
    if #password == 0 then goto retry end

    -- ── Submit ────────────────────────────────────────────────
    ui.clear()
    header("Sign In", 4, 7)
    ui.write(2, 6, "Signing in...", t.textMuted, t.bg)

    local passHash = sha.hash(password)
    local ok, resp = net.postAnon(C.HOST_ACCOUNTS, "/account/login", {
        username = username,
        passHash = passHash,
        deviceId = os.getComputerID(),
    })

    if ok and resp.body and resp.body.token then
        net.saveSession(resp.body.token)
        local savedName = (resp.body.username and #resp.body.username > 0)
                          and resp.body.username or username
        state.set("username", savedName)
        state.delete("login_user")
        state.save()

        ui.write(2, 7, "Checking for backups...", t.textMuted, t.bg)
        local restOk, restResp = net.post(C.HOST_ACCOUNTS, "/account/restore", {})
        if restOk and restResp.body and type(restResp.body.data) == "table" then
            ui.write(2, 7, "Restoring your data... ", t.success, t.bg)
            if not fs.exists("/data") then fs.makeDir("/data") end
            for file, content in pairs(restResp.body.data) do
                local f = io.open("/data/" .. file, "w")
                if f then
                    f:write(textutils.serialise(content))
                    f:close()
                end
            end
            os.sleep(0.5)
            ui.write(2, 7, "Restore complete!      ", t.success, t.bg)
            -- Re-load the state store since we just overwrote it
            state = require("system.storage.storage").open("user_config")
        else
            ui.write(2, 7, "                       ", t.bg, t.bg)
        end

        ui.write(2, 8,  "\4 Signed in!", t.success, t.bg)
        ui.write(2, 9,  "Welcome back, " .. savedName .. "!", t.text, t.bg)
        os.sleep(1.2)
        return savedName
    end

    -- ── Error handling ────────────────────────────────────────
    local errMsg = "Server error. Try again."
    if resp and resp.code == 401 then
        errMsg = "Wrong username or password."
    elseif not net.isOnline() then
        errMsg = "Server offline. Retry."
    end

    ui.clear(); header("Sign In", 4, 7)
    showMsg(errMsg, t.danger, 6)
    ui.write(2, 8, "You must sign in with", t.text, t.bg)
    ui.write(2, 9, "the server to continue.", t.text, t.bg)
    ui.button({ x = W - 10, y = H - 1, width = 10, label = "Try Again", style = "primary" })

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if my == H - 1 and mx >= W - 10 then goto retry end
    end
end

-- Combined account step: choose path → run it → return canonical username
local function stepAccount()
    while true do
        local choice = stepAccountChoice()
        if choice == "back" then
            -- Go back to network check (handled by caller loop)
            return nil
        elseif choice == "register" then
            local name = stepRegister()
            if name then return name end
        elseif choice == "login" then
            local name = stepLogin()
            if name then return name end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Step 5: PIN
-- ─────────────────────────────────────────────────────────────

local function stepPin()
    local t = Theme.get()

    ::retry::
    ui.clear()
    header("Set PIN", 5, 7)
    ui.write(2, 5, "Create a PIN to lock", t.text, t.bg)
    ui.write(2, 6, "your phone (min 4 chars).", t.textMuted, t.bg)

    local pin1 = inputField("PIN", 7, true, "")

    ui.clear()
    header("Set PIN", 5, 7)
    ui.write(2, 5, "Confirm your PIN:", t.text, t.bg)

    local pin2 = inputField("Confirm PIN", 7, true, "")

    if pin1 ~= pin2 or #pin1 < 4 then
        ui.clear(); header("Set PIN", 5, 7)
        showMsg("PINs don't match or too short!", t.danger, 6)
        os.sleep(1.5); goto retry
    end

    local pinStore = Storage.open("pin")
    pinStore.set("hash", sha.hash(pin1))
    pinStore.save()
    ui.write(2, 8, "\4 PIN set!", t.success, t.bg)
    os.sleep(0.8)
end

-- ─────────────────────────────────────────────────────────────
-- Step 6: Permissions
-- ─────────────────────────────────────────────────────────────

local function stepPermissions()
    local t = Theme.get()
    ui.clear()
    header("Permissions", 6, 7)
    ui.write(2, 6, "DorpOS will:", t.text, t.bg)
    local perms = {
        "\4 Store data locally",
        "\4 Connect to servers",
        "\4 Send & receive messages",
        "\4 Access DorpMarket",
    }
    for i, p in ipairs(perms) do
        ui.write(2, 7 + i, p, t.success, t.bg)
    end
    local nb = nextButton()
    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if nb.hit(mx, my) then return end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Step 7: Tutorial
-- ─────────────────────────────────────────────────────────────

local function stepTutorial()
    local t    = Theme.get()
    local tips = {
        { title = "Home Screen",  body = "Tap any app icon\nto open it." },
        { title = "Status Bar",   body = "Shows the time and\nyour connection status." },
        { title = "DorpMarket",   body = "Buy and sell items\nwith other DorpOS users." },
        { title = "Messages",     body = "Chat with any user\nby their @username." },
    }
    local step = 1

    local function redraw()
        local tip = tips[step]
        ui.clear()
        header("Tutorial", 7, 7)
        ui.write(2, 6, tip.title, t.accent, t.bg)
        local lines = utils.wrap(tip.body, W - 3)
        for i, line in ipairs(lines) do
            ui.write(2, 7 + i, line, t.text, t.bg)
        end
        -- Progress dots
        ui.write(2, H - 3,
            step .. "/" .. #tips .. "  " .. string.rep("\7 ", step) .. string.rep("o ", #tips - step),
            t.textMuted, t.bg)
        nextButton(H - 1)
        if step > 1 then backButton(H - 1) end
    end

    redraw()
    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if my == H - 1 then
            if mx >= W - 8 then
                if step < #tips then step = step + 1; redraw()
                else return end
            elseif mx <= 8 and step > 1 then
                step = step - 1; redraw()
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Finish screen
-- ─────────────────────────────────────────────────────────────

local function stepFinish(username)
    local t = Theme.get()
    ui.clear()
    header("All Done!", 7, 7)

    ui.write(2, 6,  "\4 Setup complete!", t.success, t.bg)
    ui.write(2, 8,  "Hey " .. (username or "there") .. "!", t.text, t.bg)
    ui.write(2, 9,  "Your phone is ready.", t.text, t.bg)
    ui.write(2, 11, "Logged in as:", t.textMuted, t.bg)
    ui.write(2, 12, "@" .. (username or "?"), t.accent, t.bg)

    local bx = math.floor((W - 14) / 2)
    ui.button({ x = bx, y = H - 2, width = 14, label = "Get Started!" })

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if my == H - 2 then return end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Commit setup config to disk
-- ─────────────────────────────────────────────────────────────

local function commitSetup(username)
    local userStore = Storage.open("user_config")
    userStore.set("username",  username)
    userStore.set("themeId",   state.get("themeId", "dark"))
    userStore.set("setupDone", true)
    userStore.save()

    local f = io.open(C.FILE_USER_CONFIG, "w")
    if f then
        f:write(textutils.serialise(userStore.getAll()))
        f:close()
    end

    Storage.delete("setup_wizard")
    log.info("wizard", "Setup complete", { username = username })
end

-- ─────────────────────────────────────────────────────────────
-- Main wizard run
-- ─────────────────────────────────────────────────────────────

log.info("wizard", "Starting setup wizard")

-- Step sequence with basic back support
local username = nil

::step1::
stepWelcome()

::step2::
local r2 = stepTheme()
if r2 == "back" then goto step1 end

::step3::
local r3 = stepNetwork()
if r3 == "back" then goto step2 end

::step4::
username = stepAccount()
-- stepAccount returns nil only if user pressed back on the choice screen
if not username then goto step3 end

stepPin()
stepPermissions()
stepTutorial()
stepFinish(username)
commitSetup(username)
