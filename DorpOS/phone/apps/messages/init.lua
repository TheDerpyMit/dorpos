--[[  DorpOS :: phone/apps/messages/init.lua
    Enchat Client — real-time global chat via gollark's Skynet Websocket API.
    Features premium UI, real-time message stream, room channels, and AES encryption.
]]

local C       = require("shared.constants")
local ui      = require("system.ui.ui")
local Theme   = require("system.theme.theme")
local Storage = require("system.storage.storage")
local skynet  = require("system.network.skynet")
local aes     = require("system.crypto.aes")
local utils   = require("system.utils.utils")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT

-- ─────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────

local userStore  = Storage.open("user_config")
local defaultNick = userStore.get("username", "dorp_user")

-- Connection config
local nickName   = defaultNick
local channelName = "enchat3-default"
local secretKey  = "public"
local focusField = "nick" -- "nick" | "channel" | "key"

local isConnected = false
local connectErr  = ""
local isConnecting = false

-- Chat states
local messages   = {}
local composeMsg = ""
local chatScroll = 0

-- Local client ID for deduplication
local function makeRandomString(length)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local s = ""
    for _ = 1, length do
        local idx = math.random(1, #chars)
        s = s .. chars:sub(idx, idx)
    end
    return s
end

local personalID = makeRandomString(16)
local _messageIDs = {}

-- ─────────────────────────────────────────────────────────────
-- AES encryption & decryption
-- ─────────────────────────────────────────────────────────────

local function encryptPayload(payload, key)
    local raw = textutils.serialize(payload)
    if not key or key == "" then
        return raw
    end
    local ok, res = pcall(aes.encrypt, key, raw)
    if ok and res then return res end
    return raw
end

local function decryptPayload(raw, key)
    -- Try decrypting if key exists
    if key and key ~= "" then
        local ok, decrypted = pcall(aes.decrypt, key, raw)
        if ok and decrypted then
            local ok2, tbl = pcall(textutils.unserialize, decrypted)
            if ok2 and type(tbl) == "table" then return tbl end
        end
    end
    -- Fallback to raw unserialize
    local ok, tbl = pcall(textutils.unserialize, raw)
    if ok and type(tbl) == "table" then return tbl end
    return nil
end

-- ─────────────────────────────────────────────────────────────
-- Rendering
-- ─────────────────────────────────────────────────────────────

local function drawConnectScreen()
    local t = Theme.get()
    ui.clear()

    -- Title
    term.setCursorPos(1, 3)
    term.setTextColor(t.accent)
    term.setBackgroundColor(t.bg)
    term.write(utils.centre("ENCHAT 3.0", W))

    term.setCursorPos(1, 4)
    term.setTextColor(t.textMuted)
    term.write(utils.centre("Global Real-time Chat", W))

    -- Text inputs
    ui.write(2, 6, "Nickname:", t.textMuted, t.bg)
    ui.textbox({ x = 2, y = 7, width = W - 3, value = nickName, focused = (focusField == "nick") })

    ui.write(2, 9, "Channel:", t.textMuted, t.bg)
    ui.textbox({ x = 2, y = 10, width = W - 3, value = channelName, focused = (focusField == "channel") })

    ui.write(2, 12, "Encryption Key:", t.textMuted, t.bg)
    ui.textbox({ x = 2, y = 13, width = W - 3, value = secretKey, focused = (focusField == "key") })

    -- Error msg
    if connectErr ~= "" then
        ui.write(2, 15, utils.truncate(connectErr, W - 2), t.danger, t.bg)
    elseif isConnecting then
        ui.write(2, 15, "Connecting to Skynet...", t.accent, t.bg)
    end

    -- Connect button
    ui.button({ x = math.floor((W - 12)/2) + 1, y = H - 2, width = 12, label = "Connect", style = "primary" })

    -- Back button
    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
end

local function drawChatScreen()
    local t = Theme.get()
    ui.clear()

    -- Header
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" # " .. utils.truncate(channelName, W - 4), W))

    local chatH = H - 3 -- rows 2 .. H-2 for messages

    -- Visible lines
    local lines = {}
    for _, m in ipairs(messages) do
        local prefix = "<" .. m.name .. "> "
        local wrapped = utils.wrap(prefix .. m.message, W - 2)
        for i, line in ipairs(wrapped) do
            local isMe = (m.name == nickName)
            table.insert(lines, { text = line, isMe = isMe })
        end
    end

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

    -- Compose input box
    term.setCursorPos(1, H - 1)
    term.setBackgroundColor(t.bgInput)
    term.setTextColor(t.text)
    local disp = #composeMsg > 0 and composeMsg or "Type message..."
    term.write(utils.padRight(disp, W - 5))
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write("[>>]")

    if #composeMsg > 0 then
        term.setCursorPos(math.min(#composeMsg + 1, W - 5), H - 1)
        term.setCursorBlink(true)
    else
        term.setCursorBlink(false)
    end

    -- Back button
    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
end

-- ─────────────────────────────────────────────────────────────
-- Actions
-- ─────────────────────────────────────────────────────────────

local function connect()
    if #nickName == 0 or #channelName == 0 then
        connectErr = "Fields cannot be empty"
        return
    end

    connectErr = ""
    isConnecting = true
    drawConnectScreen()

    local ok, err = skynet.connect(true)
    if not ok then
        connectErr = "Server down or offline."
        isConnecting = false
        drawConnectScreen()
        return
    end

    -- Subscribe to channel
    skynet.open(channelName)
    isConnected = true
    isConnecting = false
    messages = {}
    composeMsg = ""
    drawChatScreen()
end

local function disconnect()
    skynet.disconnect()
    isConnected = false
    drawConnectScreen()
end

local function sendMessage()
    if #composeMsg == 0 then return end
    local msgId = makeRandomString(16)
    _messageIDs[msgId] = true

    local payload = {
        name       = nickName,
        message    = composeMsg,
        messageID  = msgId,
        personalID = personalID,
    }

    local encrypted = encryptPayload(payload, secretKey)
    skynet.send(channelName, encrypted)

    -- Show locally instantly
    table.insert(messages, {
        name = nickName,
        message = composeMsg,
    })

    composeMsg = ""
    drawChatScreen()
end

-- ─────────────────────────────────────────────────────────────
-- Event loop
-- ─────────────────────────────────────────────────────────────

drawConnectScreen()

while true do
    local ev = { os.pullEvent() }
    local name = ev[1]

    if isConnected then
        -- ── Chat View Event Handling ─────────────────────────
        if name == "skynet_message" then
            local chan, rawMsg, sender = ev[2], ev[3], ev[4]
            if chan == channelName then
                local payload = decryptPayload(rawMsg, secretKey)
                if payload and payload.name and payload.message then
                    -- Deduplicate local echoed messages
                    if not _messageIDs[payload.messageID] then
                        table.insert(messages, {
                            name = payload.name,
                            message = payload.message,
                        })
                        drawChatScreen()
                    end
                end
            end

        elseif name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            -- Header/Back click -> disconnect
            if my == 1 and mx <= 3 then
                disconnect()
            elseif my == H and mx <= 3 then
                disconnect()
            elseif my == H - 1 and mx >= W - 4 then
                sendMessage()
            end

        elseif name == "char" then
            composeMsg = composeMsg .. ev[2]
            drawChatScreen()

        elseif name == "key" then
            local key = ev[2]
            if key == keys.backspace and #composeMsg > 0 then
                composeMsg = composeMsg:sub(1, -2)
                drawChatScreen()
            elseif key == keys.enter then
                sendMessage()
            end

        elseif name == "mouse_scroll" then
            chatScroll = math.max(0, chatScroll - ev[2])
            drawChatScreen()
        end
    else
        -- ── Connect View Event Handling ──────────────────────
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            -- Back button
            if my == H and mx <= 3 then
                return
            -- Inputs
            elseif my == 7 then
                focusField = "nick"
                drawConnectScreen()
            elseif my == 10 then
                focusField = "channel"
                drawConnectScreen()
            elseif my == 13 then
                focusField = "key"
                drawConnectScreen()
            -- Connect button
            elseif my == H - 2 and mx >= math.floor((W - 12)/2) + 1 and mx <= math.floor((W - 12)/2) + 12 then
                connect()
            end

        elseif name == "char" then
            if focusField == "nick" then
                nickName = nickName .. ev[2]
            elseif focusField == "channel" then
                channelName = channelName .. ev[2]
            elseif focusField == "key" then
                secretKey = secretKey .. ev[2]
            end
            drawConnectScreen()

        elseif name == "key" then
            local key = ev[2]
            if key == keys.backspace then
                if focusField == "nick" and #nickName > 0 then
                    nickName = nickName:sub(1, -2)
                elseif focusField == "channel" and #channelName > 0 then
                    channelName = channelName:sub(1, -2)
                elseif focusField == "key" and #secretKey > 0 then
                    secretKey = secretKey:sub(1, -2)
                end
                drawConnectScreen()
            elseif key == keys.tab or key == keys.enter then
                if focusField == "nick" then
                    focusField = "channel"
                elseif focusField == "channel" then
                    focusField = "key"
                elseif focusField == "key" then
                    connect()
                end
                drawConnectScreen()
            end
        end
    end
end
