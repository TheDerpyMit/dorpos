--[[
    DorpOS :: shared/protocol.lua
    ─────────────────────────────
    Networking protocol layer — the ONLY way DorpOS code talks over Rednet.

    Servers advertise with:  rednet.host(C.HOST_xxx, C.PROTOCOL_NAME)
    Phones find them with:   proto.lookup(C.HOST_xxx)

    Wire format (every packet is textutils.serialise'd table):
    ┌─ Request ──────────────────────────────────────────────┐
    │ protocol = "dorpos"      always                        │
    │ version  = 1             protocol version              │
    │ id       = "a1b2-34567"  correlation id                │
    │ endpoint = "/svc/action" REST-style route              │
    │ session  = "..."         omit if unauthenticated       │
    │ body     = { ... }       payload                       │
    └────────────────────────────────────────────────────────┘
    ┌─ Response ─────────────────────────────────────────────┐
    │ protocol = "dorpos"                                    │
    │ version  = 1                                           │
    │ id       = "a1b2-34567"  mirrors request id            │
    │ ok       = true|false                                  │
    │ code     = 200           HTTP-style status             │
    │ message  = "OK"          human readable                │
    │ body     = { ... }       response payload              │
    └────────────────────────────────────────────────────────┘

    Status codes:
        200 OK  201 Created  400 Bad Request  401 Unauthorised
        403 Forbidden  404 Not Found  409 Conflict
        429 Rate Limited  500 Server Error  503 Unavailable
        504 Timeout (generated locally)
]]

local proto = {}
local C = require("shared.constants")

-- ─────────────────────────────────────────────────────────────
-- Internals
-- ─────────────────────────────────────────────────────────────

local _initialized = false

local function genId()
    local h = ""
    for _ = 1, 8 do h = h .. string.format("%x", math.random(0,15)) end
    return h .. tostring(os.epoch("utc") % 99999)
end

local function buildRequest(endpoint, body, session)
    return {
        protocol = C.PROTOCOL_NAME,
        version  = C.PROTOCOL_VERSION,
        id       = genId(),
        endpoint = endpoint,
        session  = session,
        body     = body or {},
    }
end

local function buildSuccess(reqId, body, code, msg)
    return {
        protocol = C.PROTOCOL_NAME,
        version  = C.PROTOCOL_VERSION,
        id       = reqId,
        ok       = true,
        code     = code or 200,
        message  = msg  or "OK",
        body     = body or {},
    }
end

local function buildError(reqId, code, msg, body)
    return {
        protocol = C.PROTOCOL_NAME,
        version  = C.PROTOCOL_VERSION,
        id       = reqId or "?",
        ok       = false,
        code     = code,
        message  = msg,
        body     = body or {},
    }
end

local function isValid(pkt)
    return type(pkt) == "table"
        and pkt.protocol == C.PROTOCOL_NAME
        and type(pkt.version) == "number"
end

-- ─────────────────────────────────────────────────────────────
-- Initialisation
-- ─────────────────────────────────────────────────────────────

--- Open the wireless modem. Safe to call multiple times.
function proto.init()
    if _initialized then return end
    local modem = peripheral.find("modem")
    if modem then
        rednet.open(peripheral.getName(modem))
    elseif peripheral.isPresent(C.MODEM_SIDE) then
        rednet.open(C.MODEM_SIDE)
    end
    math.randomseed(os.getComputerID() * 7919 + os.epoch("utc") % 10000)
    _initialized = true
end

--- Register this computer as a named service (call from servers).
---@param hostname string  e.g. C.HOST_PROVISIONING
function proto.host(hostname)
    assert(_initialized, "Call proto.init() first")
    rednet.host(C.PROTOCOL_NAME, hostname)
end

--- Resolve a hostname to a computer ID via rednet.lookup.
--- Returns nil if the service is not found within timeout.
---@param hostname string
---@return number|nil computerId
function proto.lookup(hostname)
    assert(_initialized, "Call proto.init() first")
    local id = rednet.lookup(C.PROTOCOL_NAME, hostname)
    if id then return id end

    -- Fallback: try other service hostnames to find the All-in-One server computer ID
    local hosts = {
        C.HOST_CLOUD,
        C.HOST_UPDATES,
        C.HOST_MARKETPLACE,
        C.HOST_NOTIFICATIONS,
        C.HOST_MESSAGES,
        C.HOST_ACCOUNTS,
        C.HOST_ACTIVATION,
        C.HOST_PROVISIONING
    }
    for _, h in ipairs(hosts) do
        if h ~= hostname then
            id = rednet.lookup(C.PROTOCOL_NAME, h)
            if id then return id end
        end
    end
    return nil
end

-- ─────────────────────────────────────────────────────────────
-- Client-side
-- ─────────────────────────────────────────────────────────────

--- Send a request to a named service and wait for a response.
--- Automatically resolves hostname → computer ID, retries on timeout.
---
---@param hostname  string  e.g. C.HOST_MESSAGES
---@param endpoint  string  e.g. "/messages/send"
---@param body      table?  Payload
---@param session   string? Session token
---@param timeout   number? Seconds to wait (default C.NET_TIMEOUT)
---@return boolean ok, table response
function proto.request(hostname, endpoint, body, session, timeout)
    assert(_initialized, "Call proto.init() first")
    local maxWait = timeout or C.NET_TIMEOUT

    -- Resolve hostname to computer ID
    local serverId = proto.lookup(hostname)
    if not serverId then
        return false, buildError(nil, 503,
            "Service unavailable: cannot find host '" .. hostname .. "'")
    end

    local packet = buildRequest(endpoint, body, session)

    for attempt = 1, C.NET_MAX_RETRIES do
        rednet.send(serverId, packet, C.PROTOCOL_NAME)

        local deadline = os.clock() + maxWait
        while os.clock() < deadline do
            local remaining = deadline - os.clock()
            if remaining <= 0 then break end
            local sender, response = rednet.receive(C.PROTOCOL_NAME, math.max(0.1, remaining))
            if sender == serverId and isValid(response) and response.id == packet.id then
                return response.ok, response
            end
        end

        if attempt < C.NET_MAX_RETRIES then
            os.sleep(C.NET_RETRY_DELAY)
        end
    end

    return false, buildError(packet.id, 504,
        "No response after " .. C.NET_MAX_RETRIES .. " attempts (" .. endpoint .. ")")
end

--- Broadcast and wait for the first reply (used by bootstrap to
--- find the Provisioning Server before hostname lookup works).
---@param endpoint string
---@param body     table?
---@param timeout  number?
---@return boolean ok, table response, number|nil senderId
function proto.broadcast(endpoint, body, timeout)
    assert(_initialized, "Call proto.init() first")
    local packet  = buildRequest(endpoint, body, nil)
    rednet.broadcast(packet, C.PROTOCOL_NAME)

    local deadline = os.clock() + (timeout or C.NET_TIMEOUT)
    while os.clock() < deadline do
        local remaining = deadline - os.clock()
        if remaining <= 0 then break end
        local sender, response = rednet.receive(C.PROTOCOL_NAME, math.max(0.1, remaining))
        if sender and isValid(response) and response.id == packet.id then
            return response.ok, response, sender
        end
    end

    return false, buildError(packet.id, 504, "No server responded to broadcast"), nil
end

-- ─────────────────────────────────────────────────────────────
-- Server-side
-- ─────────────────────────────────────────────────────────────

--- Block until a valid DorpOS request arrives (server event loop).
---@param timeout number?  nil = wait forever
---@return number|nil senderId, table|nil packet
function proto.receive(timeout)
    while true do
        local sender, data = rednet.receive(C.PROTOCOL_NAME, timeout)
        if sender == nil then return nil, nil end
        if isValid(data) and data.endpoint then
            return sender, data
        end
        -- drop malformed packets silently
    end
end

--- Send a success response back to the requester.
function proto.respond(clientId, request, body, code, message)
    rednet.send(clientId, buildSuccess(request.id, body, code, message), C.PROTOCOL_NAME)
end

--- Send an error response back to the requester.
function proto.respondError(clientId, request, code, message, body)
    rednet.send(clientId, buildError(request.id, code, message, body), C.PROTOCOL_NAME)
end

function proto.respondUnauthorized(clientId, request)
    proto.respondError(clientId, request, 401, "Unauthorised: invalid or expired session")
end

function proto.respondBadRequest(clientId, request, detail)
    proto.respondError(clientId, request, 400, "Bad request" .. (detail and (": "..detail) or ""))
end

function proto.respondServerError(clientId, request, detail)
    proto.respondError(clientId, request, 500, "Server error" .. (detail and (": "..detail) or ""))
end

-- Exported builders (used by servers to build packets manually)
proto.buildSuccess = buildSuccess
proto.buildError   = buildError
proto.isValid      = isValid

return proto
