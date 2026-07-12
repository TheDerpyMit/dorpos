--[[
    DorpOS :: phone/system/setup/wizard.lua
    ────────────────────────────────────────
    First-boot setup wizard. Runs only when no user config exists.

    Steps:
        1. Welcome
        2. Language (placeholder — English only for now)
        3. Theme selection
        4. Network status
        5. Device activation (already done in boot, shows confirmation)
        6. Create account (username + password)
        7. Create PIN
        8. Permissions notice
        9. Quick tutorial
       10. Finish → Home screen

    All data is saved before moving to the next step so a crash
    mid-setup doesn't reset everything.
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

-- ─────────────────────────────────────────────────────────────
-- Wizard state (persisted between steps via storage)
-- ─────────────────────────────────────────────────────────────

local state = Storage.open("setup_wizard")

-- ─────────────────────────────────────────────────────────────
-- Shared helpers
-- ─────────────────────────────────────────────────────────────

local function header(title, step, total)
    local t = Theme.get()
    -- Status bar
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" Setup  " .. step .. "/" .. total, W))
    -- Title
    ui.write(2, 3, title, t.text, t.bg)
    -- Divider
    ui.divider(4)
end

local function nextButton(y)
    local t = Theme.get()
    return ui.button({
        x = W - 8, y = y or H - 1,
        width = 8, label = "Next >",
        style = "primary",
    })
end

local function backButton(y)
    return ui.button({
        x = 1, y = y or H - 1,
        width = 8, label = "< Back",
        style = "ghost",
    })
end

local function waitNext(nextBtn, backBtn)
    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if nextBtn and nextBtn.hit and nextBtn.hit(mx, my) then return "next" end
        if backBtn and backBtn.hit and backBtn.hit(mx, my) then return "back" end
    end
end

-- Input loop with on-screen keyboard for a single field
local function inputField(prompt, y, password, initialValue)
    local t = Theme.get()
    local value   = initialValue or ""
    local shifted = false
    local kbHits  = nil

    local kbComp = require("system.ui.components.keyboard")

    local function redraw()
        ui.clear()
        ui.write(2, y, prompt, t.textMuted, t.bg)
        ui.textbox({
            x = 2, y = y + 1, width = W - 3,
            value = value, password = password, focused = true,
        })
        kbHits = kbComp.draw({
            y       = H - 6,
            shifted = shifted,
            value   = value,
            onChar  = function(c)
                if #value < 64 then value = value .. c end
            end,
            onBack  = function()
                if #value > 0 then value = value:sub(1, -2) end
            end,
            onEnter = function() end,
            onShift = function() shifted = not shifted end,
            onClose = function() end,
        })
        -- Done button
        ui.button({ x = W - 7, y = y + 3, width = 7, label = "Done" })
    end

    redraw()

    while true do
        local ev = { os.pullEvent() }
        local name = ev[1]

        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            -- Check keyboard
            if kbHits and kbComp.handleClick(kbHits, mx, my) then
                redraw()
            elseif my == (H - 6 - 1 + 3) or (mx >= W - 7 and my == y + 3) then
                -- Done button
                break
            end
        elseif name == "char" then
            -- Physical keyboard fallback
            if #value < 64 then value = value .. ev[2] end
            redraw()
        elseif name == "key" then
            local key = ev[2]
            if key == keys.backspace and #value > 0 then
                value = value:sub(1, -2)
                redraw()
            elseif key == keys.enter then
                break
            end
        end
    end

    term.setCursorBlink(false)
    return value
end

-- ─────────────────────────────────────────────────────────────
-- Step 1: Welcome
-- ─────────────────────────────────────────────────────────────

local function stepWelcome()
    local t = Theme.get()
    ui.clear()
    header("Welcome", 1, 9)

    ui.write(2, 6,  "Welcome to DorpOS!", t.accent, t.bg)
    ui.write(2, 8,  "This wizard will help", t.text, t.bg)
    ui.write(2, 9,  "you set up your phone.", t.text, t.bg)
    ui.write(2, 11, "Takes about 2 minutes.", t.textMuted, t.bg)

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
    local themes  = Theme.list()
    local sel     = 1
    local t       = Theme.get()

    local function redraw()
        t = Theme.get()
        ui.clear()
        header("Choose Theme", 2, 9)

        for i, th in ipairs(themes) do
            local isSel = (i == sel)
            local bg = isSel and t.accent or t.bgCard
            local fg = isSel and t.textOnAccent or t.text
            local prefix = isSel and "> " or "  "
            ui.rect(2, 5 + (i - 1) * 2, W - 3, 1, bg)
            ui.write(2, 5 + (i - 1) * 2, prefix .. th.name, fg, bg)
        end

        nextButton()
        backButton()
    end

    redraw()

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        -- Check theme rows
        for i, _ in ipairs(themes) do
            local ry = 5 + (i - 1) * 2
            if my == ry and mx >= 2 and mx <= W - 1 then
                sel = i
                Theme.set(themes[i].id)
                redraw()
            end
        end
        -- Next
        if my == H - 1 and mx >= W - 8 then
            state.set("themeId", themes[sel].id)
            state.save()
            return
        end
        -- Back
        if my == H - 1 and mx <= 8 then return "back" end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Step 3: Network
-- ─────────────────────────────────────────────────────────────

local function stepNetwork()
    local t = Theme.get()
    ui.clear()
    header("Network", 3, 9)

    ui.write(2, 6, "Checking connection...", t.textMuted, t.bg)
    os.sleep(0.3)

    local online = net.isOnline()
    if online then
        ui.write(2, 8,  "\4 Connected!", t.success, t.bg)
        ui.write(2, 10, "Your phone can sync", t.text, t.bg)
        ui.write(2, 11, "with DorpOS servers.", t.text, t.bg)
    else
        ui.write(2, 8,  "x Offline", t.danger, t.bg)
        ui.write(2, 10, "No server found.", t.text, t.bg)
        ui.write(2, 11, "You can still use", t.text, t.bg)
        ui.write(2, 12, "offline features.", t.text, t.bg)
    end

    local nb = nextButton()
    local bb = backButton()
    return waitNext(nb, bb)
end

-- ─────────────────────────────────────────────────────────────
-- Step 4: Create Account
-- ─────────────────────────────────────────────────────────────

local function stepAccount()
    local t = Theme.get()

    -- Username
    ui.clear()
    header("Create Account", 4, 9)
    ui.write(2, 6, "Choose a username:", t.text, t.bg)
    local username = inputField("Username", 7, false, state.get("username", ""))
    if #username < 3 then
        -- Show error and re-prompt
        ui.write(2, 12, "Min 3 characters!", t.danger, t.bg)
        os.sleep(1)
        return stepAccount()
    end

    -- Password
    ui.clear()
    header("Create Account", 4, 9)
    ui.write(2, 6, "Create a password:", t.text, t.bg)
    local pass1 = inputField("Password", 7, true, "")

    ui.clear()
    header("Create Account", 4, 9)
    ui.write(2, 6, "Confirm password:", t.text, t.bg)
    local pass2 = inputField("Confirm", 7, true, "")

    if pass1 ~= pass2 then
        ui.clear()
        header("Create Account", 4, 9)
        ui.write(2, 8, "Passwords don't match!", t.danger, t.bg)
        os.sleep(1.5)
        return stepAccount()
    end

    if #pass1 < 4 then
        ui.clear()
        header("Create Account", 4, 9)
        ui.write(2, 8, "Password too short!", t.danger, t.bg)
        os.sleep(1.5)
        return stepAccount()
    end

    -- Register with Accounts server
    ui.clear()
    header("Create Account", 4, 9)
    ui.write(2, 8, "Creating account...", t.textMuted, t.bg)

    local passHash = sha.hash(pass1)
    local ok, resp = net.postAnon(C.HOST_ACCOUNTS, "/account/create", {
        username = username,
        passHash = passHash,
        deviceId = os.getComputerID(),
    })

    if ok then
        if resp.body.token then
            net.saveSession(resp.body.token)
        end
        state.set("username", username)
        state.save()
        ui.write(2, 10, "\4 Account created!", t.success, t.bg)
        os.sleep(1)
    else
        -- Offline or error — save locally only
        state.set("username", username)
        state.set("passHash", passHash)
        state.save()
        ui.write(2, 10, "Saved locally (offline)", t.warning, t.bg)
        os.sleep(1.5)
    end
end

-- ─────────────────────────────────────────────────────────────
-- Step 5: PIN
-- ─────────────────────────────────────────────────────────────

local function stepPin()
    local t = Theme.get()

    ui.clear()
    header("Set PIN", 5, 9)
    ui.write(2, 6, "Create a 4-digit PIN", t.text, t.bg)
    ui.write(2, 7, "to lock your phone:", t.text, t.bg)
    local pin1 = inputField("PIN", 9, true, "")

    ui.clear()
    header("Set PIN", 5, 9)
    ui.write(2, 6, "Confirm your PIN:", t.text, t.bg)
    local pin2 = inputField("Confirm PIN", 9, true, "")

    if pin1 ~= pin2 or #pin1 < 4 then
        ui.clear()
        header("Set PIN", 5, 9)
        ui.write(2, 8, "PINs don't match or", t.danger, t.bg)
        ui.write(2, 9, "too short (min 4).", t.danger, t.bg)
        os.sleep(1.5)
        return stepPin()
    end

    -- Save hashed PIN
    local pinStore = Storage.open("pin")
    pinStore.set("hash", sha.hash(pin1))
    pinStore.save()
    ui.write(2, 11, "\4 PIN set!", t.success, t.bg)
    os.sleep(0.8)
end

-- ─────────────────────────────────────────────────────────────
-- Step 6: Permissions
-- ─────────────────────────────────────────────────────────────

local function stepPermissions()
    local t = Theme.get()
    ui.clear()
    header("Permissions", 6, 9)

    ui.write(2, 6, "DorpOS will:", t.text, t.bg)
    local perms = {
        "\4 Store data locally",
        "\4 Connect to servers",
        "\4 Send & receive msgs",
        "\4 Access marketplace",
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
        { title = "Home Screen",  body = "Tap an app icon to\nopen it." },
        { title = "Status Bar",   body = "Shows time and\nnetwork signal." },
        { title = "Quick Menu",   body = "Tap the top bar for\nquick settings." },
        { title = "Marketplace",  body = "Browse & post listings\nin DorpMarket." },
        { title = "Messages",     body = "Chat with other\nDorpOS users." },
    }

    local step = 1
    local function redraw()
        local tip = tips[step]
        ui.clear()
        header("Tutorial", 7, 9)
        ui.write(2, 6, tip.title, t.accent, t.bg)
        local lines = utils.wrap(tip.body, W - 3)
        for i, line in ipairs(lines) do
            ui.write(2, 7 + i, line, t.text, t.bg)
        end
        ui.write(2, H - 3,
            step .. "/" .. #tips .. " " .. string.rep(".", step) .. string.rep(" ", #tips - step),
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
-- Step 8: Finish
-- ─────────────────────────────────────────────────────────────

local function stepFinish()
    local t = Theme.get()
    ui.clear()
    header("All Done!", 9, 9)

    ui.write(2, 6,  "\4 Setup complete!", t.success, t.bg)
    local username = state.get("username", "User")
    ui.write(2, 8,  "Welcome, " .. username .. "!", t.text, t.bg)
    ui.write(2, 10, "Your phone is ready.", t.text, t.bg)

    ui.button({ x = math.floor((W - 14) / 2), y = H - 2,
                width = 14, label = "Get Started!" })

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        if my == H - 2 then return end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Write user config and mark setup done
-- ─────────────────────────────────────────────────────────────

local function commitSetup()
    local userStore = Storage.open("user_config")
    userStore.set("username",  state.get("username", "User"))
    userStore.set("themeId",   state.get("themeId",  "dark"))
    userStore.set("setupDone", true)
    userStore.save()

    -- Write the sentinel file that boot.lua checks
    local f = io.open(C.FILE_USER_CONFIG, "w")
    if f then
        f:write(textutils.serialise(userStore.getAll()))
        f:close()
    end

    -- Clean up wizard store
    Storage.delete("setup_wizard")
    log.info("wizard", "Setup complete", { username = userStore.get("username") })
end

-- ─────────────────────────────────────────────────────────────
-- Run wizard
-- ─────────────────────────────────────────────────────────────

log.info("wizard", "Starting setup wizard")
stepWelcome()
stepTheme()
stepNetwork()
stepAccount()
stepPin()
stepPermissions()
stepTutorial()
stepFinish()
commitSetup()
