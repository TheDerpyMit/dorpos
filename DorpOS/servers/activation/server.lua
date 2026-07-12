--[[
    DorpOS :: servers/activation/server.lua
    ────────────────────────────────────────
    Activation Server — issues signed session tokens.

    On first contact from a device:
      - Creates a device record
      - Issues a signed token (HMAC-SHA256)
      - Returns configuration

    The token is thereafter sent with every authenticated request.
    Other servers verify it using the same shared HMAC secret (which
    they each independently load from their own /data/secret.txt — so
    the SMP admin must use the same secret on all servers, or use the
    Activation Server as a centralised verifier).

    For simplicity on an SMP: set the same /data/secret.txt on every
    server computer. The SERVER_SETUP.md doc explains how to do this.
]]

package.path = "/?.lua;/?/init.lua;" .. package.path

local Base = require("servers.shared.server_base")
local C    = require("shared.constants")

local server = Base.new(C.HOST_ACTIVATION, "Activation")

-- ─────────────────────────────────────────────────────────────
-- Device storage
-- ─────────────────────────────────────────────────────────────

local function loadDevices()
    if not fs.exists("/data/devices.dat") then return {} end
    local f = io.open("/data/devices.dat", "r")
    if not f then return {} end
    local raw = f:read("*a"); f:close()
    local ok, t = pcall(textutils.unserialise, raw)
    return (ok and type(t) == "table") and t or {}
end

local function saveDevices(d)
    if not fs.exists("/data") then fs.makeDir("/data") end
    local f = io.open("/data/devices.dat", "w")
    if f then f:write(textutils.serialise(d)); f:close() end
end

local devices = loadDevices()

-- Token module (loaded after server base initialises path)
local tok = require("system.crypto.token")

-- ─────────────────────────────────────────────────────────────
-- Routes
-- ─────────────────────────────────────────────────────────────

-- /activate — device requests activation token
server.route("/activate", function(clientId, req)
    local deviceId  = req.body and req.body.deviceId
    local osVersion = req.body and req.body.osVersion or "?"

    if not deviceId then
        return server.badRequest(clientId, req, "missing deviceId")
    end

    local key = tostring(deviceId)

    -- Create or update device record
    if not devices[key] then
        devices[key] = {
            deviceId    = deviceId,
            userId      = nil,
            activatedAt = os.epoch("utc"),
            osVersion   = osVersion,
        }
    else
        devices[key].lastSeen  = os.epoch("utc")
        devices[key].osVersion = osVersion
    end
    saveDevices(devices)

    -- Issue token (userId = "device_" .. id until account is linked)
    local userId   = devices[key].userId or ("device_" .. key)
    local token    = tok.create(server._secret, key, userId, os.epoch("utc"))

    print("[activation] Activated device " .. key .. " userId=" .. userId)

    server.ok(clientId, req, {
        token    = token,
        userId   = userId,
        deviceId = deviceId,
        config   = {
            osVersion        = C.OS_VERSION,
            updateInterval   = C.UPDATE_POLL_INTERVAL,
            notifInterval    = C.NOTIF_POLL_INTERVAL,
        },
    })
end)

-- /activation/link — link a device to a user account (called after login)
server.route("/activation/link", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local deviceId = req.body and req.body.deviceId
    local userId   = req.body and req.body.userId
    if not deviceId or not userId then
        return server.badRequest(clientId, req, "missing deviceId or userId")
    end

    local key = tostring(deviceId)
    if devices[key] then
        devices[key].userId = userId
        saveDevices(devices)
        -- Re-issue token with real userId
        local newToken = tok.create(server._secret, key, userId, os.epoch("utc"))
        server.ok(clientId, req, { token = newToken })
    else
        server.fail(clientId, req, 404, "Device not found")
    end
end)

-- /activation/verify — verify a token (called by other servers if needed)
server.route("/activation/verify", function(clientId, req)
    local tokenStr = req.body and req.body.token
    if not tokenStr then return server.badRequest(clientId, req, "missing token") end

    local ok2, claims = tok.verify(server._secret, tokenStr, C.SESSION_TTL)
    if ok2 then
        server.ok(clientId, req, { valid = true, claims = claims })
    else
        server.ok(clientId, req, { valid = false })
    end
end)

-- /activation/devices — admin: list all devices
server.route("/activation/devices", function(clientId, req)
    local list = {}
    for _, d in pairs(devices) do table.insert(list, d) end
    server.ok(clientId, req, { devices = list, count = #list })
end)

server.run()
