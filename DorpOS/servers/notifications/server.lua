--[[  DorpOS :: servers/notifications/server.lua ]]
if package then
    package.path = "/?.lua;/?/init.lua;/shared/?.lua;/system/?.lua;/servers/?.lua;" .. (package.path or "")
else
    pcall(dofile, "/shared/shim.lua")
end
local Base = require("servers.shared.server_base")
local C    = require("shared.constants")
local server = Base.new(C.HOST_NOTIFICATIONS, "Notifications")

local function load(n) if not fs.exists("/data/"..n..".dat") then return {} end local f=io.open("/data/"..n..".dat","r") if not f then return {} end local r=f:read("*a");f:close() local ok,t=pcall(textutils.unserialise,r) return (ok and type(t)=="table") and t or {} end
local function save(n,d) if not fs.exists("/data") then fs.makeDir("/data") end local f=io.open("/data/"..n..".dat","w") if f then f:write(textutils.serialise(d));f:close() end end

-- notifs[userId] = list of pending push notifications
local notifs = load("notifs")

-- Push a notification to a user (called by other servers internally via direct rednet)
server.route("/notifications/push", function(clientId, req)
    local ok, claims = server.verifySession(req)
    -- Allow internal calls without session too (from other servers)
    local userId  = (req.body and req.body.userId) or (ok and claims.userId)
    local title   = req.body and req.body.title   or "Notification"
    local body    = req.body and req.body.body    or ""
    local kind    = req.body and req.body.type    or "info"
    local priority = req.body and req.body.priority or 1

    if not userId then return server.badRequest(clientId, req, "missing userId") end

    notifs[userId] = notifs[userId] or {}
    table.insert(notifs[userId], {
        title    = title,
        body     = body,
        type     = kind,
        priority = priority,
        ts       = os.epoch("utc"),
    })
    save("notifs", notifs)
    server.ok(clientId, req, { queued = true })
end)

-- Poll for pending notifications (called by phone background service)
server.route("/notifications/poll", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local userId  = claims.userId
    local pending = notifs[userId] or {}
    notifs[userId] = {}
    save("notifs", notifs)

    server.ok(clientId, req, {
        notifications = pending,
        count         = #pending,
    })
end)

-- Broadcast to all users (admin)
server.route("/notifications/broadcast", function(clientId, req)
    local title    = req.body and req.body.title or "Broadcast"
    local body     = req.body and req.body.body  or ""
    local priority = req.body and req.body.priority or 1

    local n = { title=title, body=body, type="info", priority=priority, ts=os.epoch("utc") }
    for userId, _ in pairs(notifs) do
        table.insert(notifs[userId], n)
    end
    save("notifs", notifs)
    server.ok(clientId, req, { broadcast = true })
end)

server.run()
