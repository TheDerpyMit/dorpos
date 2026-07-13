--[[
    DorpOS :: servers/shared/server_base.lua
    ─────────────────────────────────────────
    Common base for all DorpOS backend servers.
    Handles routing, logging, and the main request loop.

    Usage in a server:
        local Base   = require("servers.shared.server_base")
        local server = Base.new("dorpos.messages", "Messages Server")

        server.route("/messages/send", function(clientId, req)
            -- handle request
            server.ok(clientId, req, { sent = true })
        end)

        server.run()
]]

local Base = {}

-- Load shared libraries
package.path = "/?.lua;/?/init.lua;" .. package.path

local proto = require("shared.protocol")
local C     = require("shared.constants")

-- Dashboard (optional — silently fails if not present)
local _dash = nil
pcall(function()
    _dash = require("servers.shared.monitor_dashboard")
end)

-- ─────────────────────────────────────────────────────────────
-- Logging (inline — servers may not have the phone logger)
-- ─────────────────────────────────────────────────────────────

local function log(tag, msg)
    local ts = os.epoch("utc")
    local line = string.format("[%d] [%s] %s", ts, tag, msg)
    print(line)
    if _dash then
        local level = "info"
        if msg:find("[Ee]rror") or msg:find("crash") then level = "error"
        elseif msg:find("[Ww]arn")  then level = "warn" end
        _dash.log(tag, level, msg)
        _dash.redraw()
    end
end

-- ─────────────────────────────────────────────────────────────
-- Token verification (servers verify tokens they issued)
-- ─────────────────────────────────────────────────────────────

-- Server config file stores the HMAC secret
local function loadSecret()
    if fs.exists("/data/secret.txt") then
        local f = io.open("/data/secret.txt", "r")
        if f then
            local s = f:read("*a"):gsub("%s+$", "")
            f:close()
            return s
        end
    end
    -- Generate and save a new secret on first run
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local secret = ""
    for _ = 1, 32 do
        local idx = math.random(1, #chars)
        secret = secret .. chars:sub(idx, idx)
    end
    if not fs.exists("/data") then fs.makeDir("/data") end
    local f = io.open("/data/secret.txt", "w")
    if f then f:write(secret); f:close() end
    return secret
end

-- ─────────────────────────────────────────────────────────────
-- Constructor
-- ─────────────────────────────────────────────────────────────

function Base.new(hostname, name)
    local server = {
        hostname  = hostname,
        name      = name,
        _routes   = {},
        _secret   = nil,
        _token    = nil,
    }

    -- Initialise
    proto.init()
    proto.host(hostname)
    math.randomseed(os.getComputerID() * 9001 + os.epoch("utc") % 100000)

    server._secret = loadSecret()

    -- Register with the monitor dashboard
    if _dash then
        _dash.register(name)
        _dash.redraw()
    end

    -- Load token module
    local ok, tok = pcall(require, "system.crypto.token")
    if ok then server._token = tok end

    log(name, "Started on hostname: " .. hostname)
    log(name, "Computer ID: " .. os.getComputerID())

    -- ─────────────────────────────────────────────────────────
    -- Session verification helper
    -- ─────────────────────────────────────────────────────────

    function server.verifySession(req)
        if not server._token then return false, nil end
        local tok = req.session
        if not tok then return false, nil end
        local ok2, claims = server._token.verify(server._secret, tok, C.SESSION_TTL)
        return ok2, claims
    end

    -- ─────────────────────────────────────────────────────────
    -- Response helpers
    -- ─────────────────────────────────────────────────────────

    function server.ok(clientId, req, body, msg)
        proto.respond(clientId, req, body or {}, 200, msg or "OK")
    end

    function server.created(clientId, req, body)
        proto.respond(clientId, req, body or {}, 201, "Created")
    end

    function server.fail(clientId, req, code, msg)
        proto.respondError(clientId, req, code, msg)
    end

    function server.unauthorized(clientId, req)
        proto.respondUnauthorized(clientId, req)
    end

    function server.badRequest(clientId, req, detail)
        proto.respondBadRequest(clientId, req, detail)
    end

    -- ─────────────────────────────────────────────────────────
    -- Router
    -- ─────────────────────────────────────────────────────────

    local HOST_PREFIXES = {
        [C.HOST_PROVISIONING]  = { "/provision/" },
        [C.HOST_ACTIVATION]    = { "/activate", "/activation/" },
        [C.HOST_ACCOUNTS]      = { "/account/", "/profile/", "/contacts/", "/friends/" },
        [C.HOST_MESSAGES]      = { "/messages/" },
        [C.HOST_NOTIFICATIONS] = { "/notifications/" },
        [C.HOST_MARKETPLACE]   = { "/market/" },
        [C.HOST_UPDATES]       = { "/updates/" },
        [C.HOST_CLOUD]         = { "/cloud/" },
    }

    function server.route(endpoint, handler)
        server._routes[endpoint] = handler
    end

    -- ─────────────────────────────────────────────────────────
    -- Main loop
    -- ─────────────────────────────────────────────────────────

    function server.run()
        log(name, "Ready and listening...")
        local prefixes = HOST_PREFIXES[server.hostname] or {}
        while true do
            local clientId, req = proto.receive()
            if clientId and req then
                -- Verify if endpoint belongs to this service prefix list
                local belongs = false
                for _, pref in ipairs(prefixes) do
                    if req.endpoint:sub(1, #pref) == pref then
                        belongs = true
                        break
                    end
                end

                if belongs then
                    local handler = server._routes[req.endpoint]
                    if handler then
                        -- Track in-flight request on dashboard
                        if _dash then
                            local s = _dash._stats and _dash._stats[name]
                            -- show "handling..." label immediately
                        end
                        local ok3, err = pcall(handler, clientId, req)
                        if not ok3 then
                            log(name, "Handler error on " .. req.endpoint .. ": " .. tostring(err))
                            proto.respondServerError(clientId, req, tostring(err))
                            if _dash then
                                _dash.request(name, req.endpoint, 500)
                                _dash.redraw()
                            end
                        else
                            if _dash then
                                -- We don't have the code here, mark as 200
                                _dash.request(name, req.endpoint, 200)
                                _dash.redraw()
                            end
                        end
                    else
                        log(name, "Unknown endpoint: " .. tostring(req.endpoint))
                        proto.respondError(clientId, req, 404, "Endpoint not found: " .. tostring(req.endpoint))
                        if _dash then
                            _dash.request(name, req.endpoint or "?", 404)
                            _dash.redraw()
                        end
                    end
                end
            end
        end
    end

    return server
end

return Base

