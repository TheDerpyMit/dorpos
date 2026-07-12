--[[
    DorpOS :: servers/marketplace/server.lua
    ─────────────────────────────────────────
    Marketplace Server — Facebook Marketplace style.
    Server-side storage and validation. Never trusts client data.
]]

if package then
    package.path = "/?.lua;/?/init.lua;/shared/?.lua;/system/?.lua;/servers/?.lua;" .. (package.path or "")
else
    pcall(dofile, "/shared/shim.lua")
end

local Base = require("servers.shared.server_base")
local C    = require("shared.constants")
local sha  = require("system.crypto.sha256")

local server = Base.new(C.HOST_MARKETPLACE, "Marketplace")

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

-- listings[id] = { id, title, description, wantedFor, seller, status, createdAt, views }
local listings = load("listings")
local _listId  = 0

local function nextId()
    _listId = _listId + 1
    return "L" .. string.format("%06d", _listId)
end

-- ─────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────

local function filterListings(query, sort, status)
    query  = query  or ""
    sort   = sort   or "newest"
    status = status or C.MARKET_STATUS_ACTIVE
    local q = query:lower()

    local out = {}
    for _, lst in pairs(listings) do
        if lst.status == status then
            if q == "" or
               (lst.title or ""):lower():find(q, 1, true) or
               (lst.description or ""):lower():find(q, 1, true) then
                table.insert(out, lst)
            end
        end
    end

    if sort == "oldest" then
        table.sort(out, function(a, b) return a.createdAt < b.createdAt end)
    else
        table.sort(out, function(a, b) return a.createdAt > b.createdAt end)
    end

    return out
end

-- ─────────────────────────────────────────────────────────────
-- Routes
-- ─────────────────────────────────────────────────────────────

-- Browse listings
server.route("/market/browse", function(clientId, req)
    local query    = req.body and req.body.query    or ""
    local sort     = req.body and req.body.sort     or "newest"
    local page     = req.body and req.body.page     or 1
    local pageSize = req.body and req.body.pageSize or C.MARKET_ITEMS_PER_PAGE

    local all    = filterListings(query, sort)
    local start  = (page - 1) * pageSize + 1
    local slice  = {}
    for i = start, math.min(start + pageSize - 1, #all) do
        table.insert(slice, all[i])
    end

    server.ok(clientId, req, {
        listings = slice,
        total    = #all,
        page     = page,
        pages    = math.ceil(#all / pageSize),
    })
end)

-- Get single listing
server.route("/market/listing", function(clientId, req)
    local id = req.body and req.body.listingId
    if not id or not listings[id] then
        return server.fail(clientId, req, 404, "Listing not found")
    end
    listings[id].views = (listings[id].views or 0) + 1
    save("listings", listings)
    server.ok(clientId, req, { listing = listings[id] })
end)

-- Post a new listing
server.route("/market/post", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local title       = req.body and req.body.title
    local description = req.body and req.body.description
    local wantedFor   = req.body and req.body.wantedFor

    if not title or #title < 3 then
        return server.badRequest(clientId, req, "title too short")
    end
    if not wantedFor or #wantedFor < 1 then
        return server.badRequest(clientId, req, "wantedFor is required")
    end
    if #title > C.MARKET_TITLE_MAX_LEN then
        return server.badRequest(clientId, req, "title too long")
    end

    local id = nextId()
    listings[id] = {
        id          = id,
        title       = title:sub(1, C.MARKET_TITLE_MAX_LEN),
        description = (description or ""):sub(1, C.MARKET_DESC_MAX_LEN),
        wantedFor   = wantedFor:sub(1, C.MARKET_PRICE_MAX_LEN),
        seller      = claims.userId,
        status      = C.MARKET_STATUS_ACTIVE,
        createdAt   = os.epoch("utc"),
        views       = 0,
    }
    save("listings", listings)
    print("[market] New listing " .. id .. " from " .. claims.userId)

    server.created(clientId, req, { listingId = id, listing = listings[id] })
end)

-- Remove a listing (seller only)
server.route("/market/remove", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local id = req.body and req.body.listingId
    if not id or not listings[id] then
        return server.fail(clientId, req, 404, "Listing not found")
    end
    if listings[id].seller ~= claims.userId then
        return server.fail(clientId, req, 403, "Not your listing")
    end

    listings[id].status = C.MARKET_STATUS_REMOVED
    save("listings", listings)
    server.ok(clientId, req, { removed = true })
end)

-- Mark listing as sold
server.route("/market/sold", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local id = req.body and req.body.listingId
    if not id or not listings[id] then
        return server.fail(clientId, req, 404, "Listing not found")
    end
    if listings[id].seller ~= claims.userId then
        return server.fail(clientId, req, 403, "Not your listing")
    end

    listings[id].status = C.MARKET_STATUS_SOLD
    listings[id].soldAt = os.epoch("utc")
    save("listings", listings)
    server.ok(clientId, req, { sold = true })
end)

-- My listings
server.route("/market/mine", function(clientId, req)
    local ok, claims = server.verifySession(req)
    if not ok then return server.unauthorized(clientId, req) end

    local userId = claims.userId
    local mine   = {}
    for _, lst in pairs(listings) do
        if lst.seller == userId then table.insert(mine, lst) end
    end
    table.sort(mine, function(a, b) return a.createdAt > b.createdAt end)
    server.ok(clientId, req, { listings = mine, count = #mine })
end)

-- Admin: all listings
server.route("/market/admin/all", function(clientId, req)
    local list = {}
    for _, l in pairs(listings) do table.insert(list, l) end
    server.ok(clientId, req, { listings = list, count = #list })
end)

server.run()
