--[[
    DorpOS :: servers/messages/server.lua
    ──────────────────────────────────────
    Messages Server — DMs, group chats, offline queue, read receipts.
]]

if package then
    package.path = "/?.lua;/?/init.lua;/shared/?.lua;/system/?.lua;/servers/?.lua;" .. (package.path or "")
else
    pcall(dofile, "/shared/shim.lua")
end

local Base = require("servers.shared.server_base")
local C    = require("shared.constants")

local server = Base.new(C.HOST_MESSAGES, "Messages")

-- ─────────────────────────────────────────────────────────────
-- Helper: resolve userId → username by reading accounts data
-- ─────────────────────────────────────────────────────────────
local _accountsCache = {}
local _accountsCacheTime = 0

local function loadAccounts()
    local path = "/data/users.dat"
    if not fs.exists(path) then return {} end
    local modTime = fs.attributes(path).modification
    if modTime > _accountsCacheTime then
        local f = io.open(path, "r")
        if f then
            local raw = f:read("*a")
            f:close()
            local ok, t = pcall(textutils.unserialise, raw)
            if ok and type(t) == "table" then
                _accountsCache = t
                _accountsCacheTime = modTime
            end
        end
    end
    return _accountsCache
end

local function userIdToUsername(userId)
    local users = loadAccounts()
    for uname, u in pairs(users) do
        if u.userId == userId then return uname end
    end
    return userId  -- fallback: return raw id if not found
end

-- ─────────────────────────────────────────────────────────────
-- Storage
-- ─────────────────────────────────────────────────────────────

local function load(name)
    if not fs.exists("/data/" .. name .. ".dat") then return {} end
    local f = io.open("/data/" .. name .. ".dat", "r"); if not f then return {} end
    local raw = f:read("*a"); f:close()
    local ok, t = pcall(textutils.unserialise, raw)
    return (ok and type(t) == "table") and t or {}
end

local function save(name, data)
    if not fs.exists("/data") then fs.makeDir("/data") end
    local f = io.open("/data/" .. name .. ".dat", "w")
    if f then f:write(textutils.serialise(data)); f:close() end
end

-- convos[convoId] = { id, participants=[], name, messages=[] }
local convos  = load("convos")
-- offline[userId] = { list of pending messages }
local offline = load("offline")
-- Persist msgId counter so IDs are globally unique across restarts
local _meta   = load("msg_meta")
local _msgId  = _meta.lastMsgId or 0
local function nextMsgId()
    _msgId = _msgId + 1
    _meta.lastMsgId = _msgId
    save("msg_meta", _meta)
    return _msgId
end

local function getOrCreateConvo(participantA, participantB)
    -- Canonical ID: sorted usernames joined with ":"
    local parts = { participantA, participantB }
    table.sort(parts)
    local id = table.concat(parts, ":")
    if not convos[id] then
        convos[id] = {
            id           = id,
            participants = parts,
            name         = participantB,  -- shown to participantA
            messages     = {},
            created      = os.epoch("utc"),
        }
    end
    return convos[id]
end

-- ─────────────────────────────────────────────────────────────
-- Routes
-- ─────────────────────────────────────────────────────────────

-- Start or find a conversation
server.route("/messages/start", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local with = req.body and req.body.with
    if not with then return server.badRequest(clientId, req, "missing 'with'") end

    local myUsername = userIdToUsername(claims.userId)
    local convo      = getOrCreateConvo(myUsername, with)
    save("convos", convos)

    server.ok(clientId, req, { convoId = convo.id, convo = convo })
end)

-- Send a message
server.route("/messages/send", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local convoId  = req.body and req.body.convoId
    local text     = req.body and req.body.text
    -- Resolve userId to username so display names show correctly
    local fromName = userIdToUsername(claims.userId)

    if not convoId or not text or #text == 0 then
        return server.badRequest(clientId, req, "missing convoId or text")
    end
    if not convos[convoId] then
        return server.fail(clientId, req, 404, "Conversation not found")
    end

    local msg = {
        id        = nextMsgId(),
        from      = fromName,
        text      = text,
        timestamp = os.epoch("utc"),
        read      = false,
    }
    table.insert(convos[convoId].messages, msg)
    save("convos", convos)

    -- Queue for offline recipients and send real-time push.
    -- NOTE: we do NOT push back to the sender — they already inserted it locally.
    local accounts = loadAccounts()
    for _, participant in ipairs(convos[convoId].participants) do
        if participant ~= fromName then
            -- Offline queue (cleared on /messages/poll)
            offline[participant] = offline[participant] or {}
            table.insert(offline[participant], {
                type    = "message",
                convoId = convoId,
                msg     = msg,
            })

            -- Real-time push to recipient only
            local targetUser = accounts[participant]
            if targetUser and targetUser.deviceId then
                rednet.send(targetUser.deviceId, {
                    type    = "dorpos.message",
                    convoId = convoId,
                    msg     = msg,
                }, C.PROTOCOL_NAME)
            end
        end
    end
    save("offline", offline)

    server.ok(clientId, req, { messageId = msg.id })
end)

-- Get conversation history
server.route("/messages/history", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local convoId = req.body and req.body.convoId
    local limit   = req.body and req.body.limit or 50

    if not convoId or not convos[convoId] then
        return server.fail(clientId, req, 404, "Conversation not found")
    end

    local msgs  = convos[convoId].messages
    local start = math.max(1, #msgs - limit + 1)
    local slice = {}
    for i = start, #msgs do table.insert(slice, msgs[i]) end

    -- Mark as read
    for _, m in ipairs(slice) do
        if m.from ~= claims.userId then m.read = true end
    end
    save("convos", convos)

    server.ok(clientId, req, { messages = slice, total = #msgs })
end)

-- List conversations for current user
server.route("/messages/conversations", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local myUsername = userIdToUsername(claims.userId)
    local list       = {}

    for id, c in pairs(convos) do
        local isParticipant = false
        for _, p in ipairs(c.participants) do
            if p == myUsername then isParticipant = true end
        end
        if isParticipant then
            -- Count unread
            local unread = 0
            for _, m in ipairs(c.messages) do
                if not m.read and m.from ~= myUsername then unread = unread + 1 end
            end
            local lastMsg = #c.messages > 0 and c.messages[#c.messages] or nil
            table.insert(list, {
                id      = c.id,
                name    = (function()
                    for _, p in ipairs(c.participants) do
                        if p ~= myUsername then return p end
                    end
                    return c.name
                end)(),
                unread  = unread,
                lastMsg = lastMsg and lastMsg.text or "",
                lastTs  = lastMsg and lastMsg.timestamp or 0,
            })
        end
    end

    -- Sort by most recent
    table.sort(list, function(a, b) return a.lastTs > b.lastTs end)
    server.ok(clientId, req, { conversations = list })
end)

-- Poll for offline notifications
server.route("/messages/poll", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local myUsername = userIdToUsername(claims.userId)
    local pending    = offline[myUsername] or {}
    offline[myUsername] = {}
    save("offline", offline)

    server.ok(clientId, req, { pending = pending, count = #pending })
end)

server.run()
