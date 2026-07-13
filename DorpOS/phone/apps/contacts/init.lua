--[[  DorpOS :: phone/apps/contacts/init.lua
    Friends — manage your DorpOS friends, accept/decline requests,
    and scan for nearby phones to add people instantly.

    Views:
        "friends"   — list of accepted friends, tap to open Messages
        "requests"  — incoming friend requests with Accept / Decline
        "scan"      — rednet discovery: broadcasts and lists nearby phones
        "search"    — look up any user by @username and send a request

    Input: real keyboard only (char / key events).  No on-screen keyboard.
    Tab bar: full-width single row with abbreviated labels.
]]

local C       = require("shared.constants")
local ui      = require("system.ui.ui")
local Theme   = require("system.theme.theme")
local Storage = require("system.storage.storage")
local net     = require("system.network.network")
local utils   = require("system.utils.utils")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT

local PROTO = "dorpos_discover"

-- ─────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────

local userStore  = Storage.open("user_config")
local myUsername = userStore.get("username", "me")

local view        = "friends"
local friends     = {}
local requests    = {}
local scanResults = {}

-- ─────────────────────────────────────────────────────────────
-- Server calls
-- ─────────────────────────────────────────────────────────────

local function fetchFriends()
    local ok, resp = net.post(C.HOST_ACCOUNTS, "/friends/list", {})
    if ok and resp.body then
        friends  = resp.body.friends  or {}
        requests = resp.body.requests or {}
    end
end

local function sendRequest(username)
    local ok, resp = net.post(C.HOST_ACCOUNTS, "/friends/request", { username = username })
    return ok, resp and resp.body and resp.body.status
end

local function acceptRequest(username)
    return net.post(C.HOST_ACCOUNTS, "/friends/accept", { username = username })
end

local function declineRequest(username)
    return net.post(C.HOST_ACCOUNTS, "/friends/decline", { username = username })
end

local function openChat(username)
    net.post(C.HOST_MESSAGES, "/messages/start", { with = username })
    os.queueEvent("dorpos_launch_app", C.APP_MESSAGES, { openWith = username })
end

-- ─────────────────────────────────────────────────────────────
-- Tab bar — 4 tabs across full width, no truncation
-- ─────────────────────────────────────────────────────────────
-- Tab layout:  [  Friends  ][  Requests ][   Scan   ][  Search  ]
-- Each tab = W/4 columns wide. Use short labels to fit.

local TAB_DEFS = {
    { id = "friends",  label = "Friends"  },
    { id = "requests", label = "Requests" },
    { id = "scan",     label = "Scan"     },
    { id = "search",   label = "Search"   },
}

local function drawHeader()
    local t    = Theme.get()
    local tabW = math.floor(W / #TAB_DEFS)

    -- Row 1: App title bar
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" Contacts", W))

    -- Row 2: Tab bar — each tab gets tabW columns
    for i, tab in ipairs(TAB_DEFS) do
        local x     = 1 + (i - 1) * tabW
        local isSel = (tab.id == view)
        local bg    = isSel and t.text or t.bgCard
        local fg    = isSel and t.bg   or t.textMuted

        -- Fill tab background
        term.setCursorPos(x, 2)
        term.setBackgroundColor(bg)
        term.setTextColor(fg)

        -- Centre the label, always fits (tabW = 6 for 26-wide screens)
        local lbl = tab.label
        if #lbl > tabW - 1 then lbl = lbl:sub(1, tabW - 1) end
        local pad = tabW - #lbl
        local lp  = math.floor(pad / 2)
        local rp  = pad - lp
        term.write(string.rep(" ", lp) .. lbl .. string.rep(" ", rp))

        -- Request badge on requests tab
        if tab.id == "requests" and #requests > 0 then
            term.setCursorPos(x, 2)
            term.setBackgroundColor(t.danger)
            term.setTextColor(colors.white)
            term.write(tostring(math.min(#requests, 9)))
        end
    end
end

local function drawBack()
    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
end

-- ─────────────────────────────────────────────────────────────
-- Friends list view
-- ─────────────────────────────────────────────────────────────

local _friendHits = {}

local function drawFriends()
    local t = Theme.get()
    ui.clear()
    drawHeader()
    _friendHits = {}

    if #friends == 0 then
        ui.write(2, 5, "No friends yet.", t.textMuted, t.bg)
        ui.write(2, 6, "Use Search or Scan to", t.textMuted, t.bg)
        ui.write(2, 7, "find and add people.", t.textMuted, t.bg)
    else
        for i, f in ipairs(friends) do
            local ry = 3 + i
            if ry > H - 2 then break end
            term.setCursorPos(1, ry)
            term.setBackgroundColor(t.bg)
            term.setTextColor(t.text)
            term.write(utils.padRight("  @" .. f.username, W - 10))
            term.setBackgroundColor(t.accent)
            term.setTextColor(t.textOnAccent)
            term.write("[Message]")
            term.setBackgroundColor(t.bg)
            term.write(" ")
            table.insert(_friendHits, { y = ry, username = f.username })
        end
    end

    drawBack()
end

-- ─────────────────────────────────────────────────────────────
-- Friend requests view
-- ─────────────────────────────────────────────────────────────

local _reqHits = {}

local function drawRequests()
    local t = Theme.get()
    ui.clear()
    drawHeader()
    _reqHits = {}

    if #requests == 0 then
        ui.write(2, 5, "No pending requests.", t.textMuted, t.bg)
        ui.write(2, 6, "They'll appear here", t.textMuted, t.bg)
        ui.write(2, 7, "when someone adds you.", t.textMuted, t.bg)
    else
        ui.write(2, 4, "Tap OK to accept, X to decline:", t.textMuted, t.bg)
        for i, r in ipairs(requests) do
            local ry = 4 + i
            if ry > H - 2 then break end
            term.setCursorPos(1, ry)
            term.setBackgroundColor(t.bg)
            term.setTextColor(t.text)
            term.write(utils.padRight("  @" .. r.username, W - 12))
            term.setBackgroundColor(t.success)
            term.setTextColor(colors.white)
            term.write("[OK]")
            term.setBackgroundColor(t.bg)
            term.write(" ")
            term.setBackgroundColor(t.danger)
            term.setTextColor(colors.white)
            term.write("[X]")
            term.setBackgroundColor(t.bg)
            term.write(" ")
            table.insert(_reqHits, {
                y        = ry,
                username = r.username,
                acceptX  = W - 11,
                declineX = W - 6,
            })
        end
    end

    drawBack()
end

-- ─────────────────────────────────────────────────────────────
-- Scan view
-- ─────────────────────────────────────────────────────────────

local function runScan()
    local t = Theme.get()
    ui.clear()
    drawHeader()
    ui.write(2, 5, "Scanning nearby phones...", t.textMuted, t.bg)

    rednet.broadcast({
        type = "dorpos.discover",
        from = myUsername,
    }, PROTO)

    scanResults = {}
    local seen = {}
    seen[myUsername:lower()] = true

    local spinChars = { "|", "/", "-", "\\" }
    local deadline = os.clock() + 3
    local frame = 0
    while os.clock() < deadline do
        local sp = spinChars[(frame % #spinChars) + 1]
        term.setCursorPos(2, 6)
        term.setBackgroundColor(t.bg)
        term.setTextColor(t.accent)
        term.write(sp .. " Listening... ")
        frame = frame + 1
        local remaining = deadline - os.clock()
        local senderId, msg = rednet.receive(PROTO, math.min(0.3, math.max(0.05, remaining)))
        if senderId and type(msg) == "table"
           and msg.type == "dorpos.discover.reply"
           and type(msg.username) == "string" then
            local uname = msg.username:lower()
            if not seen[uname] then
                seen[uname] = true
                table.insert(scanResults, { username = msg.username, id = senderId })
            end
        end
    end

    ui.clear()
    drawHeader()
end

local _scanHits = {}

local function drawScan()
    local t = Theme.get()
    -- header already drawn if coming from runScan; redraw fully
    ui.clear()
    drawHeader()
    _scanHits = {}

    if #scanResults == 0 then
        ui.write(2, 5, "No phones found nearby.", t.textMuted, t.bg)
        ui.write(2, 6, "Tap Scan Now to search.", t.textMuted, t.bg)
        ui.button({ x = math.floor((W - 14) / 2) + 1, y = 9,
                    width = 14, label = "Scan Now!", style = "primary" })
    else
        ui.write(2, 4, "Found " .. #scanResults .. " phone(s) nearby:", t.textMuted, t.bg)
        for i, r in ipairs(scanResults) do
            local ry = 4 + i
            if ry > H - 2 then break end
            local isFriend = false
            for _, f in ipairs(friends) do
                if f.username:lower() == r.username:lower() then isFriend = true end
            end
            term.setCursorPos(1, ry)
            term.setBackgroundColor(t.bg)
            term.setTextColor(t.text)
            term.write(utils.padRight("  @" .. r.username, W - 10))
            if isFriend then
                term.setBackgroundColor(t.bgCard)
                term.setTextColor(t.textMuted)
                term.write(" Friends ")
            else
                term.setBackgroundColor(t.accent)
                term.setTextColor(t.textOnAccent)
                term.write("[Add +] ")
            end
            table.insert(_scanHits, { y = ry, r = r, isFriend = isFriend })
        end
        ui.button({ x = W - 9, y = H, width = 9, label = "Rescan", style = "primary" })
    end

    drawBack()
end

-- ─────────────────────────────────────────────────────────────
-- Search view
-- ─────────────────────────────────────────────────────────────

local searchQuery  = ""
local searchStatus = ""
local searchOk     = true

local function doSearch()
    local t = Theme.get()
    local target = searchQuery:lower()
    if #target == 0 then return end

    -- Show loading
    term.setCursorPos(1, 7)
    term.setBackgroundColor(t.bg)
    term.setTextColor(t.textMuted)
    term.write(utils.padRight("  / Searching...", W))

    local ok, resp = net.postAnon(C.HOST_ACCOUNTS, "/account/lookup", { username = target })
    if not ok or not (resp.body and resp.body.username) then
        searchStatus = "User '" .. target .. "' not found!"
        searchOk     = false
        return
    end
    local canonical = resp.body.username

    term.setCursorPos(1, 7)
    term.setBackgroundColor(t.bg)
    term.setTextColor(t.textMuted)
    term.write(utils.padRight("  / Sending request...", W))

    local reqOk, status = sendRequest(canonical)
    if reqOk then
        searchStatus = (status == "accepted") and "You're now friends! \4" or "Request sent! \4"
        searchOk     = true
        searchQuery  = ""
        fetchFriends()
    else
        searchStatus = "Could not send request."
        searchOk     = false
    end
end

local function drawSearch()
    local t = Theme.get()
    ui.clear()
    drawHeader()

    ui.write(2, 4, "Type @username + Enter to add:", t.textMuted, t.bg)
    ui.textbox({ x = 2, y = 5, width = W - 3, value = searchQuery,
                 focused = true, placeholder = "e.g. derpymit" })

    if searchStatus ~= "" then
        local fg = searchOk and t.success or t.danger
        ui.write(2, 7, utils.truncate(searchStatus, W - 2), fg, t.bg)
    end

    drawBack()
end

-- ─────────────────────────────────────────────────────────────
-- Tab hit detection
-- ─────────────────────────────────────────────────────────────

local function tabHit(mx, my)
    if my ~= 2 then return nil end
    local tabW = math.floor(W / #TAB_DEFS)
    local idx  = math.min(math.ceil(mx / tabW), #TAB_DEFS)
    return TAB_DEFS[idx] and TAB_DEFS[idx].id or nil
end

local function switchView(newView)
    if newView == view then return end
    view = newView
    searchStatus = ""
    if view == "friends"  then drawFriends()
    elseif view == "requests" then drawRequests()
    elseif view == "scan"     then drawScan()
    elseif view == "search"   then drawSearch()
    end
end

-- ─────────────────────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────────────────────

-- Initial load with indicator
local t = Theme.get()
ui.clear()
term.setCursorPos(1, 1)
term.setBackgroundColor(t.accent)
term.setTextColor(t.textOnAccent)
term.write(utils.padRight(" Contacts", W))
term.setCursorPos(1, 5)
term.setBackgroundColor(t.bg)
term.setTextColor(t.textMuted)
term.write("  / Loading friends...")
fetchFriends()
drawFriends()

while true do
    local ev = { os.pullEvent() }
    local name = ev[1]

    if name == "dorpos_friend_update" then
        fetchFriends()
        if view == "friends"  then drawFriends()
        elseif view == "requests" then drawRequests()
        end
    end

    if name == "mouse_click" then
        local mx, my = ev[3], ev[4]

        -- Tab bar
        local tab = tabHit(mx, my)
        if tab then
            switchView(tab)
        -- Global back button
        elseif my == H and mx <= 3 then
            return
        -- View-specific
        elseif view == "friends" then
            for _, h in ipairs(_friendHits) do
                if my == h.y then
                    openChat(h.username)
                    return
                end
            end

        elseif view == "requests" then
            for _, h in ipairs(_reqHits) do
                if my == h.y then
                    if mx >= h.acceptX and mx < h.acceptX + 4 then
                        term.setCursorPos(1, h.y)
                        term.setBackgroundColor(Theme.get().bg)
                        term.setTextColor(Theme.get().textMuted)
                        term.write(utils.padRight("  / Accepting...", W))
                        acceptRequest(h.username)
                        fetchFriends()
                        drawRequests()
                    elseif mx >= h.declineX and mx < h.declineX + 3 then
                        term.setCursorPos(1, h.y)
                        term.setBackgroundColor(Theme.get().bg)
                        term.setTextColor(Theme.get().textMuted)
                        term.write(utils.padRight("  / Declining...", W))
                        declineRequest(h.username)
                        fetchFriends()
                        drawRequests()
                    end
                    break
                end
            end

        elseif view == "scan" then
            -- Scan Now / Rescan buttons
            if (my == 9 and #scanResults == 0) or (my == H and mx >= W - 9) then
                runScan()
                drawScan()
            else
                -- Tap a scan result to add
                for _, h in ipairs(_scanHits) do
                    if my == h.y and not h.isFriend then
                        local t2 = Theme.get()
                        term.setCursorPos(1, h.y)
                        term.setBackgroundColor(t2.bg)
                        term.setTextColor(t2.textMuted)
                        term.write(utils.padRight("  / Sending request...", W))
                        local reqOk = sendRequest(h.r.username)
                        term.setCursorPos(1, h.y)
                        term.setBackgroundColor(t2.bg)
                        term.setTextColor(reqOk and t2.success or t2.danger)
                        term.write(utils.padRight("  " .. (reqOk and "\4 Sent!" or "x Failed"), W))
                        os.sleep(0.8)
                        fetchFriends()
                        drawScan()
                        break
                    end
                end
            end

        elseif view == "search" then
            -- clicks in search view do nothing extra; keyboard drives input
        end

    elseif name == "char" then
        if view == "search" then
            searchQuery = searchQuery .. ev[2]
            searchStatus = ""
            drawSearch()
        end

    elseif name == "key" then
        if view == "search" then
            local key = ev[2]
            if key == keys.backspace and #searchQuery > 0 then
                searchQuery = searchQuery:sub(1, -2)
                searchStatus = ""
                drawSearch()
            elseif key == keys.enter then
                doSearch()
                drawSearch()
            end
        end
    end
end
