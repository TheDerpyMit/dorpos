--[[  DorpOS :: phone/apps/contacts/init.lua
    Friends — manage your DorpOS friends, accept/decline requests,
    and scan for nearby phones to add people instantly.

    Views:
        "friends"   — list of accepted friends, tap to open Messages
        "requests"  — incoming friend requests with Accept / Decline
        "scan"      — rednet discovery: broadcasts and lists nearby phones
        "search"    — look up any user by @username and send a request
]]

local C       = require("shared.constants")
local ui      = require("system.ui.ui")
local Theme   = require("system.theme.theme")
local Storage = require("system.storage.storage")
local net     = require("system.network.network")
local utils   = require("system.utils.utils")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT
local kbComp = require("system.ui.components.keyboard")

local PROTO = "dorpos_discover"

-- ─────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────

local userStore  = Storage.open("user_config")
local myUsername = userStore.get("username", "me")

local view         = "friends"
local friends      = {}   -- accepted friends
local requests     = {}   -- incoming friend requests
local scanResults  = {}   -- discovered nearby phones
local shifted      = false
local kbHits       = nil

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
    local ok, resp = net.post(C.HOST_ACCOUNTS, "/friends/accept", { username = username })
    if ok then fetchFriends() end
    return ok
end

local function declineRequest(username)
    local ok = net.post(C.HOST_ACCOUNTS, "/friends/decline", { username = username })
    if ok then fetchFriends() end
    return ok
end

local function removeFriend(username)
    net.post(C.HOST_ACCOUNTS, "/friends/remove", { username = username })
    fetchFriends()
end

-- Open a chat with a friend by launching Messages with a target
local function openChat(username)
    -- Start convo on messages server, then launch messages app
    net.post(C.HOST_MESSAGES, "/messages/start", { with = username })
    os.queueEvent("dorpos_launch_app", C.APP_MESSAGES, { openWith = username })
    return  -- app exits, kernel handles launch
end

-- ─────────────────────────────────────────────────────────────
-- Tab bar helper
-- ─────────────────────────────────────────────────────────────

local function drawTabBar()
    local t    = Theme.get()
    local tabs = {
        { id = "friends",  label = "Friends" },
        { id = "requests", label = "Requests" },
        { id = "scan",     label = "Scan" },
        { id = "search",   label = "Search" },
    }
    local tabW = math.floor(W / #tabs)
    for i, tab in ipairs(tabs) do
        local x   = 1 + (i - 1) * tabW
        local isSel = (tab.id == view)
        local bg  = isSel and t.accent or t.bgCard
        local fg  = isSel and t.textOnAccent or t.textMuted
        term.setCursorPos(x, 2)
        term.setBackgroundColor(bg)
        term.setTextColor(fg)
        term.write(utils.padRight(utils.centre(tab.label, tabW), tabW))
    end
end

local function drawHeader()
    local t = Theme.get()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" Friends", W))
    drawTabBar()
end

-- ─────────────────────────────────────────────────────────────
-- Friends list view
-- ─────────────────────────────────────────────────────────────

local function drawFriends()
    local t = Theme.get()
    ui.clear()
    drawHeader()

    -- Badge on "Requests" tab if there are any
    if #requests > 0 then
        local tabW = math.floor(W / 4)
        term.setCursorPos(1 + tabW, 2)
        term.setBackgroundColor(t.bgCard)
        term.setTextColor(t.danger)
        term.write("[" .. #requests .. "]")
    end

    local _hits = {}

    if #friends == 0 then
        ui.write(2, 5, "No friends yet.", t.textMuted, t.bg)
        ui.write(2, 6, "Use Search or Scan", t.textMuted, t.bg)
        ui.write(2, 7, "to find people.", t.textMuted, t.bg)
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
            table.insert(_hits, { y = ry, username = f.username })
        end
    end

    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
    return _hits
end

-- ─────────────────────────────────────────────────────────────
-- Friend requests view
-- ─────────────────────────────────────────────────────────────

local reqHits = {}

local function drawRequests()
    local t = Theme.get()
    ui.clear()
    drawHeader()

    reqHits = {}

    if #requests == 0 then
        ui.write(2, 5, "No pending requests.", t.textMuted, t.bg)
        ui.write(2, 6, "When someone adds you,", t.textMuted, t.bg)
        ui.write(2, 7, "they'll appear here.", t.textMuted, t.bg)
    else
        ui.write(2, 4, "Incoming requests:", t.textMuted, t.bg)
        for i, r in ipairs(requests) do
            local ry = 4 + i
            if ry > H - 2 then break end
            -- Username
            term.setCursorPos(1, ry)
            term.setBackgroundColor(t.bg)
            term.setTextColor(t.text)
            term.write(utils.padRight("  @" .. r.username, W - 12))
            -- Accept button
            term.setBackgroundColor(t.success)
            term.setTextColor(t.textOnAccent)
            term.write("[OK]")
            term.setBackgroundColor(t.bg)
            term.write(" ")
            -- Decline button
            term.setBackgroundColor(t.danger)
            term.setTextColor(t.textOnAccent)
            term.write("[X]")
            term.setBackgroundColor(t.bg)
            term.write(" ")
            table.insert(reqHits, {
                y          = ry,
                username   = r.username,
                acceptX    = W - 11,
                declineX   = W - 6,
            })
        end
    end

    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
end

-- ─────────────────────────────────────────────────────────────
-- Scan view — rednet discovery
-- ─────────────────────────────────────────────────────────────

local function runScan()
    local t = Theme.get()
    ui.clear()
    drawHeader()
    ui.write(2, 5, "Scanning nearby phones...", t.textMuted, t.bg)

    -- Broadcast discovery ping
    rednet.broadcast({
        type = "dorpos.discover",
        from = myUsername,
    }, PROTO)

    -- Collect responses for 3 seconds
    scanResults = {}
    local seen = {}
    seen[myUsername:lower()] = true  -- don't show ourselves

    local deadline = os.clock() + 3
    while os.clock() < deadline do
        local remaining = deadline - os.clock()
        local senderId, msg = rednet.receive(PROTO, math.max(0.1, remaining))
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

    -- Draw results
    ui.clear()
    drawHeader()

    if #scanResults == 0 then
        ui.write(2, 5, "No phones found nearby.", t.textMuted, t.bg)
        ui.write(2, 6, "Make sure others have", t.textMuted, t.bg)
        ui.write(2, 7, "DorpOS running.", t.textMuted, t.bg)
    else
        ui.write(2, 4, "Found " .. #scanResults .. " phone(s):", t.textMuted, t.bg)
        for i, r in ipairs(scanResults) do
            local ry = 4 + i
            if ry > H - 2 then break end
            -- Check if already friends
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
        end
    end

    ui.button({ x = W - 9, y = H, width = 9, label = "Rescan", style = "primary" })
    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
end

local function drawScan()
    -- scanResults already populated, just redraw
    local t = Theme.get()
    ui.clear()
    drawHeader()

    if #scanResults == 0 then
        ui.write(2, 5, "Tap Scan to start.", t.textMuted, t.bg)
        ui.write(2, 6, "Discovers nearby", t.textMuted, t.bg)
        ui.write(2, 7, "DorpOS phones.", t.textMuted, t.bg)
        ui.button({ x = math.floor((W - 12) / 2), y = 9, width = 12, label = "Scan Now!", style = "primary" })
    else
        ui.write(2, 4, "Nearby phones:", t.textMuted, t.bg)
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
        end
        ui.button({ x = W - 9, y = H, width = 9, label = "Rescan", style = "primary" })
    end

    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
end

-- ─────────────────────────────────────────────────────────────
-- Search view — add by @username
-- ─────────────────────────────────────────────────────────────

local searchQuery  = ""
local searchStatus = ""
local searchOk     = true

local function drawSearch()
    local t = Theme.get()
    ui.clear()
    drawHeader()

    ui.write(2, 4, "Enter @username to add:", t.textMuted, t.bg)
    ui.textbox({ x = 2, y = 5, width = W - 3, value = searchQuery,
                 focused = true, placeholder = "e.g. derpymit" })

    if searchStatus ~= "" then
        local fg = searchOk and t.success or t.danger
        ui.write(2, 7, utils.truncate(searchStatus, W - 2), fg, t.bg)
    end

    kbHits = kbComp.draw({
        y = H - 7, shifted = shifted,
        onChar  = function(c) searchQuery = searchQuery .. c; searchStatus = "" end,
        onBack  = function()
            if #searchQuery > 0 then searchQuery = searchQuery:sub(1, -2); searchStatus = "" end
        end,
        onEnter = function()
            local target = searchQuery:lower()
            if #target == 0 then return end

            -- Verify user exists
            searchStatus = "Searching..."
            searchOk = true

            local ok, resp = net.postAnon(C.HOST_ACCOUNTS, "/account/lookup", { username = target })
            if not ok or not (resp.body and resp.body.username) then
                searchStatus = "User '" .. target .. "' not found!"
                searchOk = false
                return
            end

            local canonical = resp.body.username
            -- Send friend request
            local reqOk, status = sendRequest(canonical)
            if reqOk then
                if status == "accepted" then
                    searchStatus = "You're now friends! \4"
                    fetchFriends()
                else
                    searchStatus = "Friend request sent! \4"
                end
                searchOk = true
                searchQuery = ""
            else
                searchStatus = "Could not send request."
                searchOk = false
            end
        end,
        onShift = function() shifted = not shifted end,
        onClose = function() view = "friends" end,
    })
end

-- ─────────────────────────────────────────────────────────────
-- Tab hit detection
-- ─────────────────────────────────────────────────────────────

local tabs = { "friends", "requests", "scan", "search" }
local function tabHit(mx, my)
    if my ~= 2 then return nil end
    local tabW = math.floor(W / #tabs)
    local idx  = math.ceil(mx / tabW)
    return tabs[idx]
end

-- ─────────────────────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────────────────────

fetchFriends()

local friendHits = drawFriends()

while true do
    local ev = { os.pullEvent() }
    local name = ev[1]

    -- Tab switching (row 2 = tab bar)
    if name == "mouse_click" then
        local mx, my = ev[3], ev[4]
        local tab = tabHit(mx, my)
        if tab and tab ~= view then
            view = tab
            searchStatus = ""
            if view == "friends"  then friendHits = drawFriends()
            elseif view == "requests" then drawRequests()
            elseif view == "scan"     then drawScan()
            elseif view == "search"   then drawSearch()
            end
        end
    end

    -- View-specific handling
    if view == "friends" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if my == H and mx <= 3 then return end
            for _, h in ipairs(friendHits) do
                if my == h.y then
                    -- Tap anywhere on friend row → open chat
                    openChat(h.username)
                    return  -- app exits, kernel re-launches messages
                end
            end
        end

    elseif view == "requests" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if my == H and mx <= 3 then return end
            for _, h in ipairs(reqHits) do
                if my == h.y then
                    if mx >= h.acceptX and mx < h.acceptX + 4 then
                        acceptRequest(h.username)
                        drawRequests()
                    elseif mx >= h.declineX and mx < h.declineX + 3 then
                        declineRequest(h.username)
                        drawRequests()
                    end
                    break
                end
            end
        end

    elseif view == "scan" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if my == H and mx <= 3 then return end
            if (my == H and mx >= W - 9) or (my == 9 and #scanResults == 0) then
                -- Scan / Rescan button
                runScan()
            else
                -- Tap on a discovered phone
                local offset = 5  -- results start at row 5
                for i, r in ipairs(scanResults) do
                    local ry = 4 + i
                    if my == ry and mx >= W - 9 then
                        -- Check not already friends
                        local isFriend = false
                        for _, f in ipairs(friends) do
                            if f.username:lower() == r.username:lower() then isFriend = true end
                        end
                        if not isFriend then
                            local t = Theme.get()
                            local reqOk, status = sendRequest(r.username)
                            -- Show brief confirmation
                            term.setCursorPos(1, ry)
                            term.setBackgroundColor(t.bg)
                            term.setTextColor(reqOk and t.success or t.danger)
                            term.write(utils.padRight("  " .. (reqOk and "Request sent!" or "Failed"), W))
                            os.sleep(1)
                            fetchFriends()
                            drawScan()
                        end
                        break
                    end
                end
            end
        end

    elseif view == "search" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if my == H and mx <= 3 then return end
            if kbHits then kbComp.handleClick(kbHits, mx, my) end
            if view == "search" then drawSearch()
            elseif view == "friends" then friendHits = drawFriends() end
        elseif name == "char" then
            searchQuery = searchQuery .. ev[2]; searchStatus = ""; drawSearch()
        elseif name == "key" then
            if ev[2] == keys.backspace and #searchQuery > 0 then
                searchQuery = searchQuery:sub(1, -2); searchStatus = ""; drawSearch()
            end
        end
    end
end
