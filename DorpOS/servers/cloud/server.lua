--[[  DorpOS :: servers/cloud/server.lua
    Cloud Server — user data backup and restore.
]]
pcall(dofile, "/shared/shim.lua")
local Base = require("servers.shared.server_base")
local C    = require("shared.constants")
local server = Base.new(C.HOST_CLOUD, "Cloud")

local function load(n) if not fs.exists("/data/"..n..".dat") then return {} end local f=io.open("/data/"..n..".dat","r") if not f then return {} end local r=f:read("*a");f:close() local ok,t=pcall(textutils.unserialise,r) return (ok and type(t)=="table") and t or {} end
local function save(n,d) if not fs.exists("/data") then fs.makeDir("/data") end local f=io.open("/data/"..n..".dat","w") if f then f:write(textutils.serialise(d));f:close() end end

-- backups[userId] = { data={...}, timestamp }
local backups = load("backups")

server.route("/cloud/backup", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local data = req.body and req.body.data
    if not data or type(data) ~= "table" then
        return server.badRequest(clientId, req, "missing data")
    end

    backups[claims.userId] = { data = data, timestamp = os.epoch("utc") }
    save("backups", backups)
    print("[cloud] Backup from " .. claims.userId)
    server.ok(clientId, req, { backed_up = true, timestamp = backups[claims.userId].timestamp })
end)

server.route("/cloud/restore", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local backup = backups[claims.userId]
    if not backup then
        return server.fail(clientId, req, 404, "No backup found for this account")
    end
    server.ok(clientId, req, { data = backup.data, timestamp = backup.timestamp })
end)

server.route("/cloud/status", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local backup = backups[claims.userId]
    server.ok(clientId, req, {
        hasBackup = backup ~= nil,
        timestamp = backup and backup.timestamp or nil,
    })
end)

server.run()
