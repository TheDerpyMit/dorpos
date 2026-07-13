--[[  DorpOS :: phone/apps/messages/init.lua
    Messages app — DMs and group chats via the Messages server.
    Features: conversation list, chat view, typing indicator, read receipts.

    Input: real keyboard only (char / key events). No on-screen keyboard.
    Dedup: messages inserted locally with server-returned ID; real-time push
           is skipped if the ID is already present in chatMessages.
]]
local C       = require("shared.constants")
local ui      = require("system.ui.ui")
local Theme   = require("system.theme.theme")
local Storage = require("system.storage.storage")
local net     = require("system.network.network")
local notif   = require("system.services.notification_manager")
local utils   = require("system.utils.utils")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT

-- ─────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────

local userStore  = Storage.open("user_config")
local myUsername = userStore.get("username", "me")
if myUsername == "me" or myUsername == "" then
    myUsername = userStore.get("username", "me")
end

local msgCache   = Storage.open("msg_cache")
local convos     = msgCache.get("convos", {})
local view          = "list"
local activeConvo   = nil
local composeText   = ""
local chatScroll    = 0
local listScroll    = 1
local newConvoTarget = ""
local friendsList   = {}
local newConvoStatus    = ""
local newConvoStatusOk  = true
local friendPickHits    = {}

-- Chat messages for the active conversation (local cache)
local chatMessages = {}

-- Timer handle for auto-refresh
local _refreshTimer = nil
local _REFRESH_INTERVAL = 5  -- seconds

-- ─────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────

local function startRefreshTimer()
    _refreshTimer = os.startTimer(_REFRESH_INTERVAL)
end

--- Check if a messageId already exists in chatMessages (dedup guard)
local function msgIdExists(id)
    if not id then return false end
    for _, m in ipairs(chatMessages) do
        if m.id == id then return true end
    end
    return false
end

-- ─────────────────────────────────────────────────────────────
-- Server communication
-- ─────────────────────────────────────────────────────────────

local function fetchConvos()
    local ok, resp = net.post(C.HOST_MESSAGES, "/messages/conversations", {})
    if ok and resp.body and resp.body.conversations then
        convos = resp.body.conversations
        msgCache.set("convos", convos)
        msgCache.save()
    end
end

local function fetchMessages(convoId)
    local ok, resp = net.post(C.HOST_MESSAGES, "/messages/history", {
        convoId = convoId,
        limit   = 60,
    })
    if ok and resp.body and resp.body.messages then
        return resp.body.messages
    end
    return nil
end

--- Send a message. Returns (ok, serverMessageId).
local function sendMessage(convoId, text)
    local ok, resp = net.post(C.HOST_MESSAGES, "/messages/send", {
        convoId = convoId,
        text    = text,
        from    = myUsername,
    })
    if ok and resp.body and resp.body.messageId then
        return true, resp.body.messageId
    end
    if not ok then
        net.queue(C.HOST_MESSAGES, "/messages/send", {
            convoId = convoId, text = text, from = myUsername,
        })
    end
    return ok, nil
end

local function lookupUser(username)
    local ok, resp = net.postAnon(C.HOST_ACCOUNTS, "/account/lookup", {
        username = username:lower()
    })
    if ok and resp.body and resp.body.username then
        return resp.body.username
    end
    return nil
end

local function startConvo(targetUsername)
    local ok, resp = net.post(C.HOST_MESSAGES, "/messages/start", {
        with = targetUsername,
    })
    if ok and resp.body then
        return resp.body.convoId
    end
    return nil
end

local function fetchFriends()
    local ok, resp = net.post(C.HOST_ACCOUNTS, "/friends/list", {})
    if ok and resp.body then
        friendsList = resp.body.friends or {}
    end
end

-- ─────────────────────────────────────────────────────────────
-- Loading indicator helpers
-- ─────────────────────────────────────────────────────────────

local function showStatus(msg, row, color)
    local t = Theme.get()
    row = row or (H - 2)
    term.setCursorPos(1, row)
    term.setBackgroundColor(t.bg)
    term.setTextColor(color or t.textMuted)
    term.write(utils.padRight("  " .. msg, W))
end

local function clearStatus(row)
    local t = Theme.get()
    row = row or (H - 2)
    term.setCursorPos(1, row)
    term.setBackgroundColor(t.bg)
    term.write(string.rep(" ", W))
end

-- ─────────────────────────────────────────────────────────────
-- Conversation list view
-- ─────────────────────────────────────────────────────────────

local _listHits = {}

local function drawList()
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    local title = " Messages"
    local btn = "[+]"
    term.write(title .. string.rep(" ", W - #title - #btn) .. btn)

    local listH = H - 2
    _listHits = {}

    if #convos == 0 then
        ui.write(2, 4, "No messages yet.", t.textMuted, t.bg)
        ui.write(2, 5, "Tap [+] to start a chat.", t.textMuted, t.bg)
    else
        for i = listScroll, math.min(listScroll + listH - 1, #convos) do
            local c   = convos[i]
            local ry  = 2 + (i - listScroll)
            term.setCursorPos(1, ry)
            term.setBackgroundColor(t.bg)
            term.setTextColor(t.text)
            local preview = ""
            if c.lastMsg and #c.lastMsg > 0 then
                preview = ": " .. utils.truncate(c.lastMsg, 12)
            end
            local unreadStr = (c.unread and c.unread > 0) and (" (" .. c.unread .. ")") or ""
            term.write(utils.padRight(
                "  " .. utils.truncate((c.name or c.id), W - 6) .. unreadStr, W))
            if c.unread and c.unread > 0 then
                term.setCursorPos(W - 3, ry)
                term.setBackgroundColor(t.accent)
                term.setTextColor(t.textOnAccent)
                term.write(tostring(c.unread))
            end
            table.insert(_listHits, { y = ry, convo = c })
        end
    end

    ui.button({ x = 1,  y = H, width = 3, label = "<",       style = "ghost" })
    ui.button({ x = 9,  y = H, width = 8, label = "Refresh",  style = "ghost" })
end

-- ─────────────────────────────────────────────────────────────
-- Chat view
-- ─────────────────────────────────────────────────────────────

local function drawChat()
    local t     = Theme.get()
    local chatH = H - 3  -- rows 2 .. H-2 for messages; H-1 = compose; H = back

    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" < " .. utils.truncate(activeConvo.name or "Chat", W - 4), W))

    -- Build line list
    local lines = {}
    for _, msg in ipairs(chatMessages) do
        local isMe = msg.from == myUsername
        local prefix = isMe and "You: " or (msg.from .. ": ")
        local wrapped = utils.wrap(prefix .. msg.text, W - 2)
        for j, line in ipairs(wrapped) do
            table.insert(lines, { text = line, isMe = isMe })
        end
    end

    -- Render visible lines
    local visStart = math.max(1, #lines - chatH + 1 - chatScroll)
    local row = 2
    for i = visStart, math.min(visStart + chatH - 1, #lines) do
        local l = lines[i]
        term.setCursorPos(1, row)
        term.setBackgroundColor(t.bg)
        term.setTextColor(l.isMe and t.accent or t.text)
        term.write(utils.padRight(l.text, W))
        row = row + 1
    end

    -- Compose bar (row H-1)
    term.setCursorPos(1, H - 1)
    term.setBackgroundColor(t.bgInput)
    term.setTextColor(t.text)
    local displayText = #composeText > 0 and composeText or "Type a message..."
    term.write(utils.padRight(displayText, W - 5))
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write("[>>]")
    -- Show cursor
    if #composeText > 0 then
        local cx = math.min(#composeText + 1, W - 5)
        term.setCursorPos(cx, H - 1)
        term.setCursorBlink(true)
    else
        term.setCursorBlink(false)
    end

    -- Back button (always visible)
    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
end

-- ─────────────────────────────────────────────────────────────
-- New conversation view
-- ─────────────────────────────────────────────────────────────

local function drawNewConvo()
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" < New Message", W))

    friendPickHits = {}
    if #friendsList > 0 then
        ui.write(2, 3, "Friends (tap to chat):", t.textMuted, t.bg)
        local maxShow = math.min(#friendsList, H - 8)
        for i = 1, maxShow do
            local f  = friendsList[i]
            local ry = 3 + i
            term.setCursorPos(1, ry)
            term.setBackgroundColor(t.bgCard)
            term.setTextColor(t.text)
            term.write(utils.padRight("  @" .. f.username, W))
            table.insert(friendPickHits, { y = ry, username = f.username })
        end
    else
        ui.write(2, 3, "No friends yet.", t.textMuted, t.bg)
        ui.write(2, 4, "Add friends in Contacts", t.textMuted, t.bg)
        ui.write(2, 5, "or type a username below.", t.textMuted, t.bg)
    end

    local inputY = H - 4
    ui.divider(inputY - 1)
    ui.write(2, inputY, "Or type @username + Enter:", t.textMuted, t.bg)
    ui.textbox({ x = 2, y = inputY + 1, width = W - 3, value = newConvoTarget,
                 focused = true, placeholder = "username" })

    if newConvoStatus ~= "" then
        local fg = newConvoStatusOk and t.success or t.danger
        ui.write(2, inputY + 2, utils.truncate(newConvoStatus, W - 2), fg, t.bg)
    end

    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
end

-- ─────────────────────────────────────────────────────────────
-- Actions
-- ─────────────────────────────────────────────────────────────

local function doSendMessage()
    if #composeText == 0 then return end
    local text = composeText
    composeText = ""

    -- Show sending indicator
    local t = Theme.get()
    term.setCursorPos(1, H - 1)
    term.setBackgroundColor(t.bgInput)
    term.setTextColor(t.textMuted)
    term.write(utils.padRight("  / Sending...", W - 5))
    term.setCursorBlink(false)

    local ok, msgId = sendMessage(activeConvo.id, text)

    -- Insert locally with the server-returned ID (dedup key)
    -- If server returned no ID (offline), use a local sentinel
    local localId = msgId or ("local_" .. os.epoch("utc") .. "_" .. math.random(1000))
    if not msgIdExists(localId) then
        table.insert(chatMessages, {
            id        = localId,
            from      = myUsername,
            text      = text,
            timestamp = os.epoch("utc"),
        })
    end

    drawChat()
end

local function doStartConvoFromUsername()
    local target = newConvoTarget:lower()
    if #target == 0 then return end
    if target == myUsername:lower() then
        newConvoStatus    = "That's you!"
        newConvoStatusOk  = false
        drawNewConvo()
        return
    end

    newConvoStatus    = "/ Looking up user..."
    newConvoStatusOk  = true
    drawNewConvo()

    local canonical = lookupUser(target)
    if not canonical then
        newConvoStatus    = "User '" .. target .. "' not found!"
        newConvoStatusOk  = false
        drawNewConvo()
        return
    end

    newConvoStatus    = "/ Starting chat..."
    newConvoStatusOk  = true
    drawNewConvo()

    local id = startConvo(canonical)
    if id then
        local found = false
        for _, c in ipairs(convos) do if c.id == id then found = true end end
        if not found then
            table.insert(convos, { id = id, name = canonical, messages = {}, unread = 0 })
            msgCache.set("convos", convos); msgCache.save()
        end
        fetchConvos()
        for _, c in ipairs(convos) do
            if c.id == id then activeConvo = c; break end
        end
        chatMessages  = fetchMessages(id) or {}
        chatScroll    = 0
        newConvoStatus = ""
        newConvoTarget = ""
        view = "chat"
        drawChat()
        startRefreshTimer()
    else
        newConvoStatus    = "Could not start chat."
        newConvoStatusOk  = false
        drawNewConvo()
    end
end

local function openConvo(c)
    activeConvo  = c
    showStatus("/ Loading messages...", H - 2)
    chatMessages = fetchMessages(c.id) or {}
    chatScroll   = 0
    c.unread     = 0
    view         = "chat"
    drawChat()
    startRefreshTimer()
end

-- ─────────────────────────────────────────────────────────────
-- Main loop — initial fetch
-- ─────────────────────────────────────────────────────────────

showStatus("/ Loading conversations...", H - 2)
fetchConvos()
fetchFriends()
drawList()

-- ─────────────────────────────────────────────────────────────
-- Event loop
-- ─────────────────────────────────────────────────────────────

while true do
    local ev = { os.pullEvent() }
    local name = ev[1]

    -- ── Real-time push (incoming message from server) ────────
    if name == "dorpos_message_received" then
        local p = ev[2]
        if p and p.convoId and p.msg then
            -- Update convo list
            local foundConvo = false
            for _, c in ipairs(convos) do
                if c.id == p.convoId then
                    foundConvo = true
                    if view ~= "chat" or (activeConvo and activeConvo.id ~= p.convoId) then
                        c.unread = (c.unread or 0) + 1
                    end
                    c.lastMsg = p.msg.text
                    c.lastTs  = p.msg.timestamp
                    break
                end
            end
            if not foundConvo then fetchConvos() end

            -- Dedup: only insert if we don't already have this ID
            if view == "chat" and activeConvo and activeConvo.id == p.convoId then
                if not msgIdExists(p.msg.id) then
                    table.insert(chatMessages, p.msg)
                    drawChat()
                end
            elseif view == "list" then
                drawList()
            end
        end
    end

    -- ── Auto-refresh timer ───────────────────────────────────
    if name == "timer" and ev[2] == _refreshTimer then
        if view == "chat" and activeConvo then
            -- Silently refresh messages in background
            local fresh = fetchMessages(activeConvo.id)
            if fresh then
                -- Merge: add any new IDs we don't have
                local changed = false
                for _, m in ipairs(fresh) do
                    if not msgIdExists(m.id) then
                        table.insert(chatMessages, m)
                        changed = true
                    end
                end
                if changed then drawChat() end
            end
        elseif view == "list" then
            fetchConvos()
            drawList()
        end
        startRefreshTimer()
    end

    -- ── LIST view ─────────────────────────────────────────────
    if view == "list" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if my == H and mx <= 3 then return end  -- back = exit app
            if my == H and mx >= 9 and mx <= 16 then
                showStatus("/ Refreshing...", H - 2)
                fetchConvos()
                drawList()
            elseif my == 1 and mx >= W - 2 then
                -- New conversation
                newConvoTarget = ""
                newConvoStatus = ""
                view = "newconvo"
                drawNewConvo()
            else
                for _, h in ipairs(_listHits) do
                    if my == h.y then
                        openConvo(h.convo)
                        break
                    end
                end
            end
        elseif name == "mouse_scroll" then
            listScroll = math.max(1, listScroll + ev[2])
            drawList()
        end

    -- ── CHAT view ─────────────────────────────────────────────
    elseif view == "chat" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            -- Back arrow in header
            if my == 1 and mx <= 3 then
                if _refreshTimer then _refreshTimer = nil end
                view = "list"
                fetchConvos()
                drawList()
            -- Send button [>>]
            elseif my == H - 1 and mx >= W - 4 then
                doSendMessage()
            -- Back button row H
            elseif my == H and mx <= 3 then
                if _refreshTimer then _refreshTimer = nil end
                view = "list"
                fetchConvos()
                drawList()
            end
        elseif name == "char" then
            composeText = composeText .. ev[2]
            drawChat()
        elseif name == "key" then
            local key = ev[2]
            if key == keys.backspace and #composeText > 0 then
                composeText = composeText:sub(1, -2)
                drawChat()
            elseif key == keys.enter then
                doSendMessage()
            end
        elseif name == "mouse_scroll" then
            chatScroll = math.max(0, chatScroll - ev[2])
            drawChat()
        end

    -- ── NEW CONVO view ────────────────────────────────────────
    elseif view == "newconvo" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            -- Header tap or back button = back to list
            if (my == 1) or (my == H and mx <= 3) then
                newConvoStatus = ""
                newConvoTarget = ""
                view = "list"
                drawList()
            else
                -- Friend pick
                local pickedFriend = false
                for _, h in ipairs(friendPickHits) do
                    if my == h.y then
                        newConvoStatus    = "/ Starting chat..."
                        newConvoStatusOk  = true
                        drawNewConvo()
                        local id = startConvo(h.username)
                        if id then
                            local found = false
                            for _, c in ipairs(convos) do if c.id == id then found = true end end
                            if not found then
                                table.insert(convos, { id = id, name = h.username, messages = {}, unread = 0 })
                                msgCache.set("convos", convos); msgCache.save()
                            end
                            for _, c in ipairs(convos) do
                                if c.id == id then activeConvo = c; break end
                            end
                            chatMessages  = fetchMessages(id) or {}
                            chatScroll    = 0
                            newConvoStatus = ""
                            view = "chat"
                            drawChat()
                            startRefreshTimer()
                        end
                        pickedFriend = true
                        break
                    end
                end
                if not pickedFriend then
                    drawNewConvo()
                end
            end
        elseif name == "char" then
            newConvoTarget = newConvoTarget .. ev[2]
            newConvoStatus = ""
            drawNewConvo()
        elseif name == "key" then
            local key = ev[2]
            if key == keys.backspace and #newConvoTarget > 0 then
                newConvoTarget = newConvoTarget:sub(1, -2)
                newConvoStatus = ""
                drawNewConvo()
            elseif key == keys.enter then
                doStartConvoFromUsername()
            elseif key == keys.escape then
                newConvoStatus = ""
                newConvoTarget = ""
                view = "list"
                drawList()
            end
        end
    end
end
