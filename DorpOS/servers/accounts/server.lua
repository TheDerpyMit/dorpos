--[[
    DorpOS :: servers/accounts/server.lua
    ──────────────────────────────────────
    Accounts Server — user profiles, authentication, friend system.

    Friend system uses mutual requests:
        A sends request → B gets pending invite
        B accepts       → both become friends
        Either can remove at any time
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

local users    = load("users")     -- { username -> { passHash, userId, friends, friendRequests, ... } }
local settings = load("settings")  -- { userId -> settings table }

-- Helper: get user record by userId
local function getUserByIdent(userId)
    for uname, u in pairs(users) do
        if u.userId == userId then return uname, u end
    end
    return nil, nil
end

-- ─────────────────────────────────────────────────────────────
-- Auth routes
-- ─────────────────────────────────────────────────────────────

-- Create new account
server.route("/account/create", function(clientId, req)
    local username = req.body and req.body.username
    local passHash = req.body and req.body.passHash
    local deviceId = req.body and req.body.deviceId

    if not username or not passHash then
        return server.badRequest(clientId, req, "missing username or passHash")
    end
    username = username:lower()
    if #username < 3 then
        return server.badRequest(clientId, req, "username too short")
    end
    if not username:match("^[a-z0-9_]+$") then
        return server.badRequest(clientId, req, "username may only contain letters, digits and underscores")
    end
    if users[username] then
        return server.fail(clientId, req, 409, "Username already taken")
    end

    local userId = sha.hash(username .. tostring(os.epoch("utc"))):sub(1, 12)
    users[username] = {
        username       = username,
        userId         = userId,
        passHash       = passHash,
        deviceId       = deviceId,
        createdAt      = os.epoch("utc"),
        friends        = {},          -- list of accepted friend usernames
        friendRequests = {},          -- list of incoming request usernames (pending)
    }
    save("users", users)

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
    username = username:lower()

    local user = users[username]
    if not user then return server.fail(clientId, req, 401, "Invalid credentials") end
    if not sha.equal(user.passHash, passHash) then
        return server.fail(clientId, req, 401, "Invalid credentials")
    end

    local token = tok.create(server._secret, tostring(deviceId or user.userId),
                              user.userId, os.epoch("utc"))
    server.ok(clientId, req, { userId = user.userId, token = token, username = user.username })
end)

-- Lookup user by username — case-insensitive, public (no auth needed)
server.route("/account/lookup", function(clientId, req)
    local username = req.body and req.body.username
    if not username then return server.badRequest(clientId, req) end
    username = username:lower()
    local u = users[username]
    if not u then return server.fail(clientId, req, 404, "Not found") end
    server.ok(clientId, req, { userId = u.userId, username = u.username })
end)

-- ─────────────────────────────────────────────────────────────
-- Profile routes
-- ─────────────────────────────────────────────────────────────

server.route("/profile/get", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local uname, u = getUserByIdent(claims.userId)
    if not u then return server.fail(clientId, req, 404, "User not found") end

    server.ok(clientId, req, {
        username       = u.username,
        userId         = u.userId,
        friends        = u.friends or {},
        friendRequests = u.friendRequests or {},
        createdAt      = u.createdAt,
    })
end)

server.route("/profile/update", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local uname, u = getUserByIdent(claims.userId)
    if not u then return server.fail(clientId, req, 404, "User not found") end

    local updates = req.body or {}
    if updates.theme     then users[uname].theme     = updates.theme     end
    if updates.wallpaper then users[uname].wallpaper = updates.wallpaper end
    save("users", users)
    server.ok(clientId, req, { updated = true })
end)

-- ─────────────────────────────────────────────────────────────
-- Friend system routes
-- ─────────────────────────────────────────────────────────────

-- Get friends list + pending incoming requests
server.route("/friends/list", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local _, me = getUserByIdent(claims.userId)
    if not me then return server.fail(clientId, req, 404, "User not found") end

    me.friends        = me.friends        or {}
    me.friendRequests = me.friendRequests or {}

    -- Enrich friends with userId for display
    local enriched = {}
    for _, fname in ipairs(me.friends) do
        local fu = users[fname]
        table.insert(enriched, {
            username = fname,
            userId   = fu and fu.userId or nil,
        })
    end

    -- Enrich incoming requests
    local requests = {}
    for _, rname in ipairs(me.friendRequests) do
        local ru = users[rname]
        table.insert(requests, {
            username = rname,
            userId   = ru and ru.userId or nil,
        })
    end

    server.ok(clientId, req, {
        friends  = enriched,
        requests = requests,
    })
end)

-- Send a friend request
server.route("/friends/request", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local myUname, me = getUserByIdent(claims.userId)
    if not me then return server.fail(clientId, req, 404, "Your account not found") end

    local targetName = req.body and req.body.username
    if not targetName then return server.badRequest(clientId, req, "missing username") end
    targetName = targetName:lower()

    if targetName == myUname then
        return server.badRequest(clientId, req, "Cannot add yourself")
    end

    local target = users[targetName]
    if not target then return server.fail(clientId, req, 404, "User not found") end

    -- Check not already friends
    me.friends = me.friends or {}
    for _, f in ipairs(me.friends) do
        if f == targetName then
            return server.fail(clientId, req, 409, "Already friends")
        end
    end

    -- Check not already requested
    target.friendRequests = target.friendRequests or {}
    for _, r in ipairs(target.friendRequests) do
        if r == myUname then
            return server.fail(clientId, req, 409, "Request already sent")
        end
    end

    -- If the target already sent us a request — auto-accept (mutual)
    me.friendRequests = me.friendRequests or {}
    for i, r in ipairs(me.friendRequests) do
        if r == targetName then
            -- Auto-accept mutual request
            table.remove(me.friendRequests, i)
            table.insert(me.friends, targetName)
            target.friends = target.friends or {}
            table.insert(target.friends, myUname)
            save("users", users)
            return server.ok(clientId, req, { status = "accepted", mutual = true })
        end
    end

    -- Add to target's pending requests
    table.insert(target.friendRequests, myUname)
    save("users", users)
    print("[accounts] Friend request: " .. myUname .. " → " .. targetName)
    server.ok(clientId, req, { status = "requested" })
end)

-- Accept a friend request
server.route("/friends/accept", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local myUname, me = getUserByIdent(claims.userId)
    if not me then return server.fail(clientId, req, 404, "Your account not found") end

    local fromName = req.body and req.body.username
    if not fromName then return server.badRequest(clientId, req, "missing username") end
    fromName = fromName:lower()

    -- Remove from pending requests
    me.friendRequests = me.friendRequests or {}
    local found = false
    for i, r in ipairs(me.friendRequests) do
        if r == fromName then
            table.remove(me.friendRequests, i)
            found = true
            break
        end
    end
    if not found then return server.fail(clientId, req, 404, "No such request") end

    -- Add mutual friendship
    me.friends = me.friends or {}
    table.insert(me.friends, fromName)

    local requester = users[fromName]
    if requester then
        requester.friends = requester.friends or {}
        table.insert(requester.friends, myUname)
    end

    save("users", users)
    print("[accounts] Friend accepted: " .. myUname .. " ↔ " .. fromName)
    server.ok(clientId, req, { status = "accepted" })
end)

-- Decline a friend request
server.route("/friends/decline", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local myUname, me = getUserByIdent(claims.userId)
    if not me then return server.fail(clientId, req, 404, "Your account not found") end

    local fromName = req.body and req.body.username
    if not fromName then return server.badRequest(clientId, req, "missing username") end
    fromName = fromName:lower()

    me.friendRequests = me.friendRequests or {}
    for i, r in ipairs(me.friendRequests) do
        if r == fromName then
            table.remove(me.friendRequests, i)
            save("users", users)
            return server.ok(clientId, req, { status = "declined" })
        end
    end
    server.fail(clientId, req, 404, "No such request")
end)

-- Remove a friend
server.route("/friends/remove", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local myUname, me = getUserByIdent(claims.userId)
    if not me then return server.fail(clientId, req, 404, "Your account not found") end

    local targetName = req.body and req.body.username
    if not targetName then return server.badRequest(clientId, req, "missing username") end
    targetName = targetName:lower()

    -- Remove from my friends
    me.friends = me.friends or {}
    for i, f in ipairs(me.friends) do
        if f == targetName then table.remove(me.friends, i); break end
    end

    -- Remove from their friends too (mutual)
    local target = users[targetName]
    if target then
        target.friends = target.friends or {}
        for i, f in ipairs(target.friends) do
            if f == myUname then table.remove(target.friends, i); break end
        end
    end

    save("users", users)
    server.ok(clientId, req, { status = "removed" })
end)

-- Legacy compat: old /friends/add endpoint redirects to request
server.route("/friends/add", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local myUname, me = getUserByIdent(claims.userId)
    if not me then return server.fail(clientId, req, 404, "Your account not found") end

    local targetName = req.body and req.body.username
    if not targetName then return server.badRequest(clientId, req) end
    targetName = targetName:lower()

    if not users[targetName] then return server.fail(clientId, req, 404, "User not found") end

    me.friends = me.friends or {}
    local found = false
    for _, f in ipairs(me.friends) do if f == targetName then found = true end end
    if not found then table.insert(me.friends, targetName) end
    save("users", users)
    server.ok(clientId, req, { friends = me.friends })
end)

-- ─────────────────────────────────────────────────────────────
-- Cloud Backup & Restore
-- ─────────────────────────────────────────────────────────────

server.route("/account/backup", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local backupData = req.body and req.body.data
    if not backupData or type(backupData) ~= "table" then
        return server.badRequest(clientId, req, "missing or invalid backup data")
    end

    if not fs.exists("/data/backups") then fs.makeDir("/data/backups") end
    local f = io.open("/data/backups/" .. claims.userId .. ".dat", "w")
    if not f then return server.fail(clientId, req, 500, "could not write backup") end
    f:write(textutils.serialise(backupData))
    f:close()

    print("[accounts] Backed up data for " .. claims.userId)
    server.ok(clientId, req, { status = "backed_up" })
end)

server.route("/account/restore", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local path = "/data/backups/" .. claims.userId .. ".dat"
    if not fs.exists(path) then
        return server.fail(clientId, req, 404, "no backup found")
    end

    local f = io.open(path, "r")
    if not f then return server.fail(clientId, req, 500, "could not read backup") end
    local raw = f:read("*a")
    f:close()

    local success, parsed = pcall(textutils.unserialise, raw)
    if not success or type(parsed) ~= "table" then
        return server.fail(clientId, req, 500, "backup corrupted")
    end

    print("[accounts] Restored data for " .. claims.userId)
    server.ok(clientId, req, { data = parsed })
end)

server.run()
