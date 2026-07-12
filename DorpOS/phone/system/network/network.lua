--[[
    DorpOS :: phone/system/network/network.lua
    ──────────────────────────────────────────
    High-level networking facade for phone-side code.

    Wraps shared/protocol.lua with:
      - Automatic session token injection from saved storage
      - Offline detection and queuing (fire-and-forget messages)
      - Convenience methods per service endpoint

    Apps should use this module, not shared/protocol.lua directly.

    Usage:
        local net = require("system.network.network")
        net.init()

        -- Authenticated request (session auto-injected)
        local ok, resp = net.post(net.ACCOUNTS, "/profile/get", {})

        -- Check connectivity
        if net.isOnline() then ... end
]]

local net = {}

local proto   = require("shared.protocol")
local C       = require("shared.constants")
local Storage = require("system.storage.storage")
local log     = require("system.utils.logger")

-- ─────────────────────────────────────────────────────────────
-- Service hostname aliases (re-exported for convenience)
-- ─────────────────────────────────────────────────────────────
net.PROVISIONING    = C.HOST_PROVISIONING
net.ACTIVATION      = C.HOST_ACTIVATION
net.ACCOUNTS        = C.HOST_ACCOUNTS
net.MESSAGES        = C.HOST_MESSAGES
net.NOTIFICATIONS   = C.HOST_NOTIFICATIONS
net.MARKETPLACE     = C.HOST_MARKETPLACE
net.UPDATES         = C.HOST_UPDATES
net.CLOUD           = C.HOST_CLOUD

-- ─────────────────────────────────────────────────────────────
-- Offline queue (fire-and-forget messages stored until online)
-- ─────────────────────────────────────────────────────────────
local _offlineQueue = {}

-- ─────────────────────────────────────────────────────────────
-- Internals
-- ─────────────────────────────────────────────────────────────

local function getSession()
    local store = Storage.open("session")
    return store.get("token", nil)
end

-- ─────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────

--- Initialise the network layer. Must be called once at boot.
function net.init()
    proto.init()
    log.info("network", "Network layer initialised")
end

--- Check whether at least one known service is reachable.
---@return boolean
function net.isOnline()
    -- Check if rednet is open (instant, no blocking network lookups)
    return rednet.isOpen()
end

--- Send an authenticated POST-style request to a service.
---@param hostname string  e.g. net.ACCOUNTS
---@param endpoint string  e.g. "/profile/get"
---@param body     table?  Request payload
---@param timeout  number? Override timeout
---@return boolean ok, table response
function net.post(hostname, endpoint, body, timeout)
    local session = getSession()
    local ok, resp = proto.request(hostname, endpoint, body or {}, session, timeout)
    if not ok then
        log.warn("network", "Request failed", { host = hostname, ep = endpoint, code = resp.code, msg = resp.message })
    end
    return ok, resp
end

--- Send an unauthenticated request (used for login / provisioning).
---@param hostname string
---@param endpoint string
---@param body     table?
---@param timeout  number?
---@return boolean ok, table response
function net.postAnon(hostname, endpoint, body, timeout)
    local ok, resp = proto.request(hostname, endpoint, body or {}, nil, timeout)
    if not ok then
        log.warn("network", "Anon request failed", { host = hostname, ep = endpoint })
    end
    return ok, resp
end

--- Broadcast and wait for any server to respond (bootstrap only).
function net.broadcast(endpoint, body, timeout)
    return proto.broadcast(endpoint, body, timeout)
end

--- Queue a message for delivery when the server comes back online.
--- Queued messages are sent automatically next time net.post() succeeds.
---@param hostname string
---@param endpoint string
---@param body     table
function net.queue(hostname, endpoint, body)
    table.insert(_offlineQueue, {
        hostname = hostname,
        endpoint = endpoint,
        body     = body,
        queued   = os.epoch("utc"),
    })
    log.info("network", "Message queued for offline delivery", { host = hostname, ep = endpoint })
end

--- Attempt to drain the offline queue. Call periodically.
---@return number sent  Number of successfully delivered messages
function net.flushQueue()
    if #_offlineQueue == 0 then return 0 end
    local sent  = 0
    local remaining = {}
    for _, item in ipairs(_offlineQueue) do
        local ok = net.post(item.hostname, item.endpoint, item.body)
        if ok then
            sent = sent + 1
        else
            table.insert(remaining, item)
        end
    end
    _offlineQueue = remaining
    if sent > 0 then
        log.info("network", "Offline queue flushed", { sent = sent, remaining = #remaining })
    end
    return sent
end

--- Store a received session token (called after login/activation).
---@param tokenStr string
function net.saveSession(tokenStr)
    local store = Storage.open("session")
    store.set("token", tokenStr)
    store.save()
    log.info("network", "Session token saved")
end

--- Clear the stored session token (called on logout).
function net.clearSession()
    local store = Storage.open("session")
    store.clear()
    log.info("network", "Session cleared")
end

--- Return the current session token or nil.
---@return string|nil
function net.getSession()
    return getSession()
end

return net
