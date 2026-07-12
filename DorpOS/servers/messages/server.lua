--[[
    DorpOS :: servers/messages/server.lua
    ──────────────────────────────────────
    Messages Server — DMs, group chats, offline queue, read receipts.
]]

package.path = "/?.lua;/?/init.lua;" .. package.path

local Base = require("servers.shared.server_base")
local C    = require("shared.constants")

local server = Base.new(C.HOST_MESSAGES, "Messages")

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

local _msgId = 0
local function nextMsgId()
    _msgId = _msgId + 1
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

    local userId = claims.userId
    local convo  = getOrCreateConvo(userId, with)
    save("convos", convos)

    server.ok(clientId, req, { convoId = convo.id, convo = convo })
end)

-- Send a message
server.route("/messages/send", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local convoId = req.body and req.body.convoId
    local text    = req.body and req.body.text
    local from    = claims.userId

    if not convoId or not text or #text == 0 then
        return server.badRequest(clientId, req, "missing convoId or text")
    end
    if not convos[convoId] then
        return server.fail(clientId, req, 404, "Conversation not found")
    end

    local msg = {
        id        = nextMsgId(),
        from      = from,
        text      = text,
        timestamp = os.epoch("utc"),
        read      = false,
    }
    table.insert(convos[convoId].messages, msg)
    save("convos", convos)

    -- Queue for offline recipients
    for _, participant in ipairs(convos[convoId].participants) do
        if participant ~= from then
            offline[participant] = offline[participant] or {}
            table.insert(offline[participant], {
                type    = "message",
                convoId = convoId,
                msg     = msg,
            })
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

    local userId = claims.userId
    local list   = {}

    for id, c in pairs(convos) do
        local isParticipant = false
        for _, p in ipairs(c.participants) do
            if p == userId then isParticipant = true end
        end
        if isParticipant then
            -- Count unread
            local unread = 0
            for _, m in ipairs(c.messages) do
                if not m.read and m.from ~= userId then unread = unread + 1 end
            end
            local lastMsg = #c.messages > 0 and c.messages[#c.messages] or nil
            table.insert(list, {
                id      = c.id,
                name    = (function()
                    for _, p in ipairs(c.participants) do
                        if p ~= userId then return p end
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

    local userId = claims.userId
    local pending = offline[userId] or {}
    offline[userId] = {}
    save("offline", offline)

    server.ok(clientId, req, { pending = pending, count = #pending })
end)

server.run()
