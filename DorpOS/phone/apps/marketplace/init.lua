--[[  DorpOS :: phone/apps/marketplace/init.lua
    DorpMarket — Facebook Marketplace style.
    People post items they're selling + what they want in return.
    All listings stored and validated server-side.
]]
local C       = require("shared.constants")
local ui      = require("system.ui.ui")
local Theme   = require("system.theme.theme")
local Storage = require("system.storage.storage")
local net     = require("system.network.network")
local utils   = require("system.utils.utils")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT
local kbComp = require("system.ui.components.keyboard")

-- ─────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────

local userStore  = Storage.open("user_config")
local myUsername = userStore.get("username", "me")

local view       = "browse"  -- "browse"|"detail"|"post"|"mine"
local listings   = {}
local myListings = {}
local scroll     = 1
local selListing = nil
local searchQ    = ""
local sortBy     = "newest"  -- "newest"|"oldest"

-- New listing compose state
local newListing = { title = "", description = "", wantedFor = "" }
local editField  = "title"
local shifted    = false
local kbHits     = nil
local isPosting  = false

-- ─────────────────────────────────────────────────────────────
-- Server calls
-- ─────────────────────────────────────────────────────────────

local function fetchListings(query, sort)
    local ok, resp = net.post(C.HOST_MARKETPLACE, "/market/browse", {
        query    = query or "",
        sort     = sort or "newest",
        page     = 1,
        pageSize = C.MARKET_ITEMS_PER_PAGE * 3,
    })
    if ok and resp.body.listings then
        listings = resp.body.listings
    end
end

local function fetchMyListings()
    local ok, resp = net.post(C.HOST_MARKETPLACE, "/market/mine", {})
    if ok and resp.body.listings then
        myListings = resp.body.listings
    end
end

local function postListing(listing)
    local ok, resp = net.post(C.HOST_MARKETPLACE, "/market/post", {
        title       = listing.title,
        description = listing.description,
        wantedFor   = listing.wantedFor,
        seller      = myUsername,
    })
    return ok, resp
end

local function removeListing(listingId)
    local ok, resp = net.post(C.HOST_MARKETPLACE, "/market/remove", {
        listingId = listingId,
    })
    return ok
end

local function contactSeller(listing)
    -- Send a message to the seller via Messages server
    net.post(C.HOST_MESSAGES, "/messages/start", { with = listing.seller })
    net.post(C.HOST_MESSAGES, "/messages/send", {
        with = listing.seller,
        text = "Hi! I'm interested in your listing: " .. listing.title,
        from = myUsername,
    })
end

-- ─────────────────────────────────────────────────────────────
-- Browse view
-- ─────────────────────────────────────────────────────────────

local function drawBrowse()
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    local title = " DorpMarket"
    local btn = "[+]"
    term.write(title .. string.rep(" ", W - #title - #btn) .. btn)

    -- Search bar
    term.setCursorPos(1, 2)
    term.setBackgroundColor(t.bgInput)
    term.setTextColor(t.text)
    term.write(utils.padRight("  " .. (searchQ == "" and "Search listings..." or searchQ), W))

    -- Sort toggle
    term.setCursorPos(W - 8, 3)
    term.setBackgroundColor(t.bgCard)
    term.setTextColor(t.textMuted)
    term.write("Sort:" .. sortBy:sub(1,3))

    local listH = H - 5
    local _hits = {}

    if #listings == 0 then
        ui.write(2, 6, "No listings found.", t.textMuted, t.bg)
        ui.write(2, 7, "Be the first to post!", t.text, t.bg)
    else
        for i = scroll, math.min(scroll + listH - 1, #listings) do
            local lst = listings[i]
            local ry  = 4 + (i - scroll) * 2
            if ry + 1 > H - 2 then break end
            -- Title row
            term.setCursorPos(1, ry)
            term.setBackgroundColor(t.bg)
            term.setTextColor(t.text)
            term.write(utils.padRight("  " .. utils.truncate(lst.title or "?", W - 4), W))
            -- Seller + "wanted" row
            term.setCursorPos(1, ry + 1)
            term.setBackgroundColor(t.bg)
            term.setTextColor(t.textMuted)
            local sub = "@" .. (lst.seller or "?") .. "  wants: " .. utils.truncate(lst.wantedFor or "?", 10)
            term.write(utils.padRight("  " .. sub, W))

            local li = lst
            table.insert(_hits, { y1 = ry, y2 = ry + 1, listing = li })
        end
    end

    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
    ui.button({ x = 8, y = H, width = 8, label = "My List", style = "ghost" })
    ui.button({ x = W - 8, y = H, width = 8, label = "Refresh", style = "ghost" })
    return _hits
end

-- ─────────────────────────────────────────────────────────────
-- Detail view
-- ─────────────────────────────────────────────────────────────

local function drawDetail(lst)
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" Listing", W))

    ui.write(2, 3, lst.title or "Untitled", t.text, t.bg)
    ui.write(2, 4, "Seller: @" .. (lst.seller or "?"), t.textMuted, t.bg)
    ui.divider(5)
    ui.write(2, 6, "Description:", t.textMuted, t.bg)

    local descLines = utils.wrap(lst.description or "(none)", W - 3)
    for i, line in ipairs(descLines) do
        ui.write(2, 6 + i, line, t.text, t.bg)
    end

    local wy = 6 + #descLines + 2
    ui.write(2, wy, "Wants in return:", t.textMuted, t.bg)
    ui.write(2, wy + 1, lst.wantedFor or "?", t.accent, t.bg)

    ui.button({ x = 1, y = H - 1, width = 3, label = "<", style = "ghost" })
    if lst.seller ~= myUsername then
        ui.button({ x = 9, y = H - 1, width = 14, label = "Contact Seller" })
    else
        ui.button({ x = 9, y = H - 1, width = 8, label = "Remove", style = "danger" })
    end
end

-- ─────────────────────────────────────────────────────────────
-- Post new listing
-- ─────────────────────────────────────────────────────────────

local function drawPost()
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" New Listing", W))

    local fields   = { "title", "wantedFor", "description" }
    local labels   = { "What are you selling?", "What do you want?", "Description" }
    local values   = { newListing.title, newListing.wantedFor, newListing.description }

    for i, lbl in ipairs(labels) do
        local fy = 2 + (i - 1) * 2
        ui.write(2, fy, lbl .. ":", t.textMuted, t.bg)
        ui.textbox({ x = 2, y = fy + 1, width = W - 3,
                     value = values[i], focused = (editField == fields[i]),
                     placeholder = lbl })
    end

    kbHits = kbComp.draw({
        y = H - 6, shifted = shifted,
        onChar  = function(c)
            newListing[editField] = newListing[editField] .. c
        end,
        onBack  = function()
            local cur = newListing[editField]
            if #cur > 0 then newListing[editField] = cur:sub(1, -2) end
        end,
        onEnter = function()
            local idx = 1
            for i, f in ipairs(fields) do if f == editField then idx = i; break end end
            editField = fields[(idx % #fields) + 1]
        end,
        onShift = function() shifted = not shifted end,
        onClose = function() view = "browse" end,
    })

    -- Post button
    if isPosting then
        ui.button({ x = W - 9, y = H - 8, width = 9, label = "Posting...", style = "ghost" })
    else
        ui.button({ x = W - 7, y = H - 8, width = 7, label = "Post!" })
    end
end

-- ─────────────────────────────────────────────────────────────
-- My listings view
-- ─────────────────────────────────────────────────────────────

local function drawMine()
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" My Listings", W))

    local _hits = {}
    if #myListings == 0 then
        ui.write(2, 4, "You have no listings.", t.textMuted, t.bg)
    else
        for i, lst in ipairs(myListings) do
            local ry = 2 + i
            term.setCursorPos(1, ry)
            term.setBackgroundColor(t.bg)
            term.setTextColor(t.text)
            local status = lst.status == "sold" and " [SOLD]" or ""
            term.write(utils.padRight("  " .. utils.truncate(lst.title, W - 8) .. status, W))
            table.insert(_hits, { y = ry, listing = lst })
        end
    end

    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
    return _hits
end

-- ─────────────────────────────────────────────────────────────
-- Main loop
-- ─────────────────────────────────────────────────────────────

fetchListings()
local _hits = drawBrowse()

while true do
    local ev = { os.pullEvent() }
    local name = ev[1]

    if view == "browse" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if my == H and mx <= 3 then return end
            if my == H and mx >= 8 and mx <= 15 then
                view = "mine"; fetchMyListings()
                _hits = drawMine()
            elseif my == H and mx >= W - 8 then
                fetchListings(searchQ, sortBy); _hits = drawBrowse()
            elseif my == 1 and mx >= W - 2 then
                -- Post new
                newListing = { title = "", description = "", wantedFor = "" }
                editField  = "title"
                view = "post"; drawPost()
            elseif my == 3 and mx >= W - 8 then
                sortBy = sortBy == "newest" and "oldest" or "newest"
                fetchListings(searchQ, sortBy); _hits = drawBrowse()
            else
                for _, h in ipairs(_hits) do
                    if my >= h.y1 and my <= h.y2 then
                        selListing = h.listing
                        view = "detail"; drawDetail(selListing)
                        break
                    end
                end
            end
        elseif name == "char" then
            searchQ = searchQ .. ev[2]
            fetchListings(searchQ, sortBy); _hits = drawBrowse()
        elseif name == "key" then
            if ev[2] == keys.backspace and #searchQ > 0 then
                searchQ = searchQ:sub(1, -2)
                fetchListings(searchQ, sortBy); _hits = drawBrowse()
            end
        elseif name == "mouse_scroll" then
            scroll = math.max(1, scroll + ev[2]); _hits = drawBrowse()
        end

    elseif view == "detail" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if my == H - 1 and mx <= 3 then
                view = "browse"; _hits = drawBrowse()
            elseif my == H - 1 and mx >= 9 then
                if selListing.seller ~= myUsername then
                    contactSeller(selListing)
                    ui.toast({ text = "Message sent!", type = "success", y = H })
                    os.sleep(1)
                else
                    if removeListing(selListing.id) then
                        view = "browse"; fetchListings(); _hits = drawBrowse()
                    end
                end
            end
        end

    elseif view == "post" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if kbHits and kbComp.handleClick(kbHits, mx, my) then
                drawPost()
            elseif my == H - 8 and mx >= W - 7 then
                -- Submit
                if isPosting then return end
                if #newListing.title > 0 and #newListing.wantedFor > 0 then
                    -- Save a copy for submission
                    local toPost = {
                        title = newListing.title,
                        description = newListing.description,
                        wantedFor = newListing.wantedFor
                    }
                    isPosting = true
                    drawPost()
                    
                    ui.toast({ text = "Posting...", type = "info", y = H })
                    os.sleep(0.5)

                    local ok, resp = postListing(toPost)
                    isPosting = false
                    if ok then
                        -- Immediately clear the form
                        newListing = { title = "", description = "", wantedFor = "" }
                        view = "browse"
                        fetchListings(); _hits = drawBrowse()
                    else
                        ui.toast({ text = "Post failed. Try again.", type = "error", y = H })
                        os.sleep(1)
                        drawPost()
                    end
                else
                    ui.toast({ text = "Fill in required fields.", type = "warning", y = H })
                    os.sleep(1); drawPost()
                end
            else
                -- Field focus
                local flds = { "title", "wantedFor", "description" }
                for i, f in ipairs(flds) do
                    local fy = 2 + (i - 1) * 2
                    if my == fy + 1 then editField = f end
                end
                drawPost()
            end
        elseif name == "char" then
            newListing[editField] = newListing[editField] .. ev[2]
            drawPost()
        elseif name == "key" then
            if ev[2] == keys.backspace then
                local cur = newListing[editField]
                if #cur > 0 then newListing[editField] = cur:sub(1, -2) end
                drawPost()
            end
        end

    elseif view == "mine" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if my == H and mx <= 3 then
                view = "browse"; _hits = drawBrowse()
            end
        end
    end
end
