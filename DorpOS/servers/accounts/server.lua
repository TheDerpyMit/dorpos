--[[
    DorpOS :: servers/accounts/server.lua
    ──────────────────────────────────────
    Accounts Server — user profiles, authentication, friends, settings sync.
]]

if package then
    package.path = "/?.lua;/?/init.lua;/shared/?.lua;/system/?.lua;/servers/?.lua;" .. (package.path or "")
else
    pcall(dofile, "/shared/shim.lua")
end

local Base = require("servers.shared.server_base")
local C    = require("shared.constants")
local sha  = require("system.crypto.sha256")
local tok  = require("system.crypto.token")

local server = Base.new(C.HOST_ACCOUNTS, "Accounts")

-- ─────────────────────────────────────────────────────────────
-- Data storage helpers
-- ─────────────────────────────────────────────────────────────

local function dbPath(name) return "/data/" .. name .. ".dat" end

local function load(name)
    local path = dbPath(name)
    if not fs.exists(path) then return {} end
    local f = io.open(path, "r"); if not f then return {} end
    local raw = f:read("*a"); f:close()
    local ok, t = pcall(textutils.unserialise, raw)
    return (ok and type(t) == "table") and t or {}
end

local function save(name, data)
    if not fs.exists("/data") then fs.makeDir("/data") end
    local f = io.open(dbPath(name), "w")
    if f then f:write(textutils.serialise(data)); f:close() end
end

local users    = load("users")     -- { username -> { passHash, userId, ... } }
local contacts = load("contacts")  -- { userId -> { list of contacts } }
local settings = load("settings")  -- { userId -> settings table }

-- ─────────────────────────────────────────────────────────────
-- Routes
-- ─────────────────────────────────────────────────────────────

-- Create new account
server.route("/account/create", function(clientId, req)
    local username = req.body and req.body.username
    local passHash = req.body and req.body.passHash
    local deviceId = req.body and req.body.deviceId

    if not username or not passHash then
        return server.badRequest(clientId, req, "missing username or passHash")
    end
    -- Normalise to lowercase so usernames are case-insensitive
    username = username:lower()
    if #username < 3 then
        return server.badRequest(clientId, req, "username too short")
    end
    -- Validate: letters, digits, underscore only
    if not username:match("^[a-z0-9_]+$") then
        return server.badRequest(clientId, req, "username may only contain letters, digits and underscores")
    end
    if users[username] then
        return server.fail(clientId, req, 409, "Username already taken")
    end

    local userId = sha.hash(username .. tostring(os.epoch("utc"))):sub(1, 12)
    users[username] = {
        username  = username,
        userId    = userId,
        passHash  = passHash,
        deviceId  = deviceId,
        createdAt = os.epoch("utc"),
        friends   = {},
    }
    save("users", users)

    -- Issue activation token
    local token = tok.create(server._secret, tostring(deviceId or userId), userId, os.epoch("utc"))

    print("[accounts] Created: " .. username .. " id=" .. userId)
    server.created(clientId, req, { userId = userId, token = token, username = username })
end)

-- Login
server.route("/account/login", function(clientId, req)
    local username = req.body and req.body.username
    local passHash = req.body and req.body.passHash
    local deviceId = req.body and req.body.deviceId

    if not username or not passHash then
        return server.badRequest(clientId, req)
    end
    -- Normalise username to lowercase
    username = username:lower()

    local user = users[username]
    if not user then return server.fail(clientId, req, 401, "Invalid credentials") end
    if not sha.equal(user.passHash, passHash) then
        return server.fail(clientId, req, 401, "Invalid credentials")
    end

    local token = tok.create(server._secret, tostring(deviceId or user.userId),
                              user.userId, os.epoch("utc"))
    -- Return username too so client can store the canonical name
    server.ok(clientId, req, { userId = user.userId, token = token, username = user.username })
end)

-- Get profile
server.route("/profile/get", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local userId = claims.userId
    for _, u in pairs(users) do
        if u.userId == userId then
            server.ok(clientId, req, {
                username  = u.username,
                userId    = u.userId,
                friends   = u.friends or {},
                createdAt = u.createdAt,
            })
            return
        end
    end
    server.fail(clientId, req, 404, "User not found")
end)

-- Update profile / settings
server.route("/profile/update", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local userId  = claims.userId
    local updates = req.body or {}

    for uname, u in pairs(users) do
        if u.userId == userId then
            -- Only allow safe fields
            if updates.theme    then users[uname].theme    = updates.theme    end
            if updates.wallpaper then users[uname].wallpaper = updates.wallpaper end
            save("users", users)
            server.ok(clientId, req, { updated = true })
            return
        end
    end
    server.fail(clientId, req, 404, "User not found")
end)

-- Contact sync
server.route("/contacts/sync", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local userId  = claims.userId
    local incoming = req.body and req.body.contacts

    if incoming then
        contacts[userId] = incoming
        save("contacts", contacts)
    end

    server.ok(clientId, req, { contacts = contacts[userId] or {} })
end)

-- Add friend
server.route("/friends/add", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local userId    = claims.userId
    local targetUsername = req.body and req.body.username
    if not targetUsername then return server.badRequest(clientId, req) end

    if not users[targetUsername] then
        return server.fail(clientId, req, 404, "User not found")
    end

    for uname, u in pairs(users) do
        if u.userId == userId then
            u.friends = u.friends or {}
            -- Avoid duplicates
            local found = false
            for _, f in ipairs(u.friends) do
                if f == targetUsername then found = true end
            end
            if not found then table.insert(u.friends, targetUsername) end
            save("users", users)
            server.ok(clientId, req, { friends = u.friends })
            return
        end
    end
    server.fail(clientId, req, 404, "Your account not found")
end)

-- Lookup user by username (for messaging, marketplace) — case-insensitive
server.route("/account/lookup", function(clientId, req)
    local username = req.body and req.body.username
    if not username then return server.badRequest(clientId, req) end
    username = username:lower()
    local u = users[username]
    if not u then return server.fail(clientId, req, 404, "Not found") end
    server.ok(clientId, req, { userId = u.userId, username = u.username })
end)

server.run()
