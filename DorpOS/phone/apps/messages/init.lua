--[[  DorpOS :: phone/apps/messages/init.lua
    Messages app — DMs and group chats via the Messages server.
    Features: conversation list, chat view, typing indicator, read receipts.
]]
local C       = require("shared.constants")
local ui      = require("system.ui.ui")
local Theme   = require("system.theme.theme")
local Storage = require("system.storage.storage")
local net     = require("system.network.network")
local notif   = require("system.services.notification_manager")
local utils   = require("system.utils.utils")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT
local kbComp = require("system.ui.components.keyboard")

-- ─────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────

local userStore  = Storage.open("user_config")
local myUsername = userStore.get("username", "me")
-- Refresh username at runtime in case it was just set by the wizard
if myUsername == "me" or myUsername == "" then
    myUsername = userStore.get("username", "me")
end

local msgCache   = Storage.open("msg_cache")
local convos     = msgCache.get("convos", {})   -- list of { id, name, messages=[], unread }
local view       = "list"  -- "list" | "chat"
local activeConvo = nil
local composeText = ""
local shifted     = false
local kbHits      = nil
local chatScroll  = 0
local listScroll  = 1
local newConvoMode = false
local newConvoTarget = ""

-- ─────────────────────────────────────────────────────────────
-- Server communication
-- ─────────────────────────────────────────────────────────────

local function fetchConvos()
    local ok, resp = net.post(C.HOST_MESSAGES, "/messages/conversations", {})
    if ok and resp.body.conversations then
        convos = resp.body.conversations
        msgCache.set("convos", convos)
        msgCache.save()
    end
end

local function fetchMessages(convoId)
    local ok, resp = net.post(C.HOST_MESSAGES, "/messages/history", {
        convoId = convoId,
        limit   = 50,
    })
    if ok and resp.body.messages then
        return resp.body.messages
    end
    return nil
end

local function sendMessage(convoId, text)
    local ok, resp = net.post(C.HOST_MESSAGES, "/messages/send", {
        convoId = convoId,
        text    = text,
        from    = myUsername,
    })
    if not ok then
        -- Queue for offline delivery
        net.queue(C.HOST_MESSAGES, "/messages/send", {
            convoId = convoId, text = text, from = myUsername,
        })
    end
    return ok
end

local function startConvo(targetUsername)
    local ok, resp = net.post(C.HOST_MESSAGES, "/messages/start", {
        with = targetUsername,
    })
    if ok then
        return resp.body.convoId
    end
    return nil
end

-- ─────────────────────────────────────────────────────────────
-- Conversation list view
-- ─────────────────────────────────────────────────────────────

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
    local _hits = {}

    if #convos == 0 then
        ui.write(2, 5, "No messages yet.", t.textMuted, t.bg)
        ui.write(2, 6, "Tap [+] to start a chat.", t.textMuted, t.bg)
    else
        for i = listScroll, math.min(listScroll + listH - 1, #convos) do
            local c   = convos[i]
            local ry  = 2 + (i - listScroll)
            local bg  = t.bg
            local fg  = t.text
            term.setCursorPos(1, ry)
            term.setBackgroundColor(bg)
            term.setTextColor(fg)
            local unreadStr = (c.unread and c.unread > 0) and (" (" .. c.unread .. ")") or ""
            term.write(utils.padRight("  " .. utils.truncate(c.name or c.id, W - 6) .. unreadStr, W))
            if c.unread and c.unread > 0 then
                term.setCursorPos(W - 3, ry)
                term.setBackgroundColor(t.accent)
                term.setTextColor(t.textOnAccent)
                term.write(tostring(c.unread))
            end
            table.insert(_hits, { y = ry, convo = c })
        end
    end

    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
    ui.button({ x = 9, y = H, width = 8, label = "Refresh", style = "ghost" })
    return _hits
end

-- ─────────────────────────────────────────────────────────────
-- Chat view
-- ─────────────────────────────────────────────────────────────

local chatMessages = {}

local function drawChat()
    local t     = Theme.get()
    local kbY   = H - 7
    local chatH = kbY - 3

    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    -- Show "< Name" so user knows left side = back
    term.write(utils.padRight(" < " .. utils.truncate(activeConvo.name or "Chat", W - 3), W))

    -- Messages
    -- Build line list from messages
    local lines = {}
    for _, msg in ipairs(chatMessages) do
        local isMe = msg.from == myUsername
        local prefix = isMe and "You: " or (msg.from .. ": ")
        local wrapped = utils.wrap(prefix .. msg.text, W - 2)
        for j, line in ipairs(wrapped) do
            table.insert(lines, { text = line, isMe = isMe, first = (j == 1), msg = msg })
        end
        table.insert(lines, { text = "", isMe = false, sep = true })
    end

    local visStart = math.max(1, #lines - chatH - chatScroll)
    local row = 2
    for i = visStart, math.min(visStart + chatH, #lines) do
        local l = lines[i]
        if not l.sep then
            term.setCursorPos(1, row)
            term.setBackgroundColor(t.bg)
            term.setTextColor(l.isMe and t.accent or t.text)
            term.write(utils.padRight(l.text, W))
        end
        row = row + 1
    end

    -- Compose bar
    term.setCursorPos(1, kbY - 1)
    term.setBackgroundColor(t.bgInput)
    term.setTextColor(t.text)
    term.write(utils.padRight(composeText == "" and "Type a message..." or composeText, W - 5))
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write("[>>]")

    -- Keyboard
    kbHits = kbComp.draw({
        y = kbY, shifted = shifted,
        onChar  = function(c) composeText = composeText .. c end,
        onBack  = function()
            if #composeText > 0 then composeText = composeText:sub(1, -2) end
        end,
        onEnter = function()
            if #composeText > 0 then
                sendMessage(activeConvo.id, composeText)
                table.insert(chatMessages, {
                    from = myUsername, text = composeText,
                    timestamp = os.epoch("utc"), sent = true,
                })
                composeText = ""
            end
        end,
        onShift = function() shifted = not shifted end,
        onClose = function() view = "list" end,
    })
end

-- ─────────────────────────────────────────────────────────────
-- New conversation dialog
-- ─────────────────────────────────────────────────────────────

local function drawNewConvo()
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" < New Message", W))

    ui.write(2, 4, "To (username):", t.textMuted, t.bg)
    ui.textbox({ x = 2, y = 5, width = W - 3, value = newConvoTarget,
                 focused = true, placeholder = "username" })

    kbHits = kbComp.draw({
        y = H - 7, shifted = shifted,
        onChar  = function(c) newConvoTarget = newConvoTarget .. c end,
        onBack  = function()
            if #newConvoTarget > 0 then newConvoTarget = newConvoTarget:sub(1, -2) end
        end,
        onEnter = function()
            if #newConvoTarget > 0 then
                local id = startConvo(newConvoTarget)
                if id then
                    -- Add to convos if not exists
                    local found = false
                    for _, c in ipairs(convos) do if c.id == id then found = true end end
                    if not found then
                        table.insert(convos, { id = id, name = newConvoTarget, messages = {}, unread = 0 })
                        msgCache.set("convos", convos); msgCache.save()
                    end
                    -- Switch to chat
                    for _, c in ipairs(convos) do
                        if c.id == id then activeConvo = c; break end
                    end
                    chatMessages = {}
                    newConvoMode = false
                    view = "chat"
                end
            end
        end,
        onShift = function() shifted = not shifted end,
        onClose = function() newConvoMode = false; view = "list" end,
    })
end

-- ─────────────────────────────────────────────────────────────
-- Main loop
-- ─────────────────────────────────────────────────────────────

-- Initial fetch
fetchConvos()

local _hits = drawList()

while true do
    local ev = { os.pullEvent() }
    local name = ev[1]

    if view == "list" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if my == H and mx <= 3 then return end
            if my == H and mx >= 9 and mx <= 16 then
                fetchConvos(); _hits = drawList()
            end
            if my == 1 and mx >= W - 2 then
                -- New conversation
                newConvoTarget = ""
                newConvoMode   = true
                view           = "newconvo"
                drawNewConvo()
            else
                for _, h in ipairs(_hits) do
                    if my == h.y then
                        activeConvo  = h.convo
                        chatMessages = fetchMessages(h.convo.id) or {}
                        chatScroll   = 0
                        h.convo.unread = 0
                        view = "chat"
                        drawChat()
                        break
                    end
                end
            end
        elseif name == "mouse_scroll" then
            listScroll = math.max(1, listScroll + ev[2])
            _hits = drawList()
        end

    elseif view == "chat" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if kbHits and kbComp.handleClick(kbHits, mx, my) then
                drawChat()
            elseif my == 1 and mx <= 3 then
                view = "list"; _hits = drawList()
            else
                -- Send on clicking send button
                local kbY = H - 7
                if my == kbY - 1 and mx >= W - 4 then
                    if #composeText > 0 then
                        sendMessage(activeConvo.id, composeText)
                        table.insert(chatMessages, {
                            from = myUsername, text = composeText,
                            timestamp = os.epoch("utc"),
                        })
                        composeText = ""
                        drawChat()
                    end
                end
            end
        elseif name == "char" then
            composeText = composeText .. ev[2]; drawChat()
        elseif name == "key" then
            local key = ev[2]
            if key == keys.backspace and #composeText > 0 then
                composeText = composeText:sub(1, -2); drawChat()
            elseif key == keys.enter and #composeText > 0 then
                sendMessage(activeConvo.id, composeText)
                table.insert(chatMessages, { from = myUsername, text = composeText, timestamp = os.epoch("utc") })
                composeText = ""; drawChat()
            end
        elseif name == "mouse_scroll" then
            chatScroll = math.max(0, chatScroll - ev[2])
            drawChat()
        end

    elseif view == "newconvo" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if kbHits then kbComp.handleClick(kbHits, mx, my) end
            drawNewConvo()
        elseif name == "char" then
            newConvoTarget = newConvoTarget .. ev[2]; drawNewConvo()
        elseif name == "key" then
            if ev[2] == keys.backspace and #newConvoTarget > 0 then
                newConvoTarget = newConvoTarget:sub(1, -2); drawNewConvo()
            end
        end

        if view == "chat" then drawChat()
        elseif view == "list" then _hits = drawList() end
    end
end
