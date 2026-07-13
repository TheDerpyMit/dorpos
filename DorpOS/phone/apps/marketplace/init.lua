--[[  DorpOS :: phone/apps/marketplace/init.lua
    DorpMarket — Facebook Marketplace style.
    People post items they're selling + what they want in return.

    Input: real keyboard only. No on-screen keyboard.
    Search: debounced — only fetches after typing stops (0.5s timer).
    Loading: spinners shown during all network operations.
]]
local C       = require("shared.constants")
local ui      = require("system.ui.ui")
local Theme   = require("system.theme.theme")
local Storage = require("system.storage.storage")
local net     = require("system.network.network")
local utils   = require("system.utils.utils")
local skynet  = require("system.network.skynet")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT

-- ─────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────

local userStore  = Storage.open("user_config")
local myUsername = userStore.get("username", "me")

local view       = "browse"
local listings   = {}
local myListings = {}
local scroll     = 1
local selListing = nil
local searchQ    = ""
local sortBy     = "newest"

-- Post compose state
local newListing = { title = "", description = "", wantedFor = "" }
local editField  = "title"   -- "title" | "wantedFor" | "description"
local FIELDS     = { "title", "wantedFor", "description" }
local FIELD_LABELS = { title = "Selling:", wantedFor = "Want in return:", description = "Description:" }

-- Debounce timer for search
local _searchTimer = nil
local _SEARCH_DELAY = 0.5  -- seconds before search fires

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
    if ok and resp.body and resp.body.listings then
        listings = resp.body.listings
    end
end

local function fetchMyListings()
    local ok, resp = net.post(C.HOST_MARKETPLACE, "/market/mine", {})
    if ok and resp.body and resp.body.listings then
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
    local ok = net.post(C.HOST_MARKETPLACE, "/market/remove", { listingId = listingId })
    return ok
end

local function contactSeller(listing)
    net.post(C.HOST_MESSAGES, "/messages/start", { with = listing.seller })
    local convoOk, convoResp = net.post(C.HOST_MESSAGES, "/messages/start", { with = listing.seller })
    if convoOk and convoResp.body and convoResp.body.convoId then
        net.post(C.HOST_MESSAGES, "/messages/send", {
            convoId = convoResp.body.convoId,
            text    = "Hi! I'm interested in your listing: " .. listing.title,
            from    = myUsername,
        })
    end
end

-- ─────────────────────────────────────────────────────────────
-- Status / loading helpers
-- ─────────────────────────────────────────────────────────────

local function showStatus(msg, row, color)
    local t = Theme.get()
    row = row or H
    term.setCursorPos(1, row)
    term.setBackgroundColor(t.bg)
    term.setTextColor(color or t.textMuted)
    term.write(utils.padRight("  " .. msg, W))
end

-- ─────────────────────────────────────────────────────────────
-- Browse view
-- ─────────────────────────────────────────────────────────────

local _browseHits = {}

local function drawBrowse()
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    local title = " DorpMarket"
    local btn = "[+]"
    term.write(title .. string.rep(" ", W - #title - #btn) .. btn)

    -- Search bar (row 2)
    term.setCursorPos(1, 2)
    term.setBackgroundColor(t.bgInput)
    term.setTextColor(t.text)
    term.write(utils.padRight("  " .. (searchQ == "" and "Search listings..." or searchQ), W))

    -- Sort toggle (row 3)
    term.setCursorPos(1, 3)
    term.setBackgroundColor(t.bg)
    term.setTextColor(t.textMuted)
    term.write(string.rep(" ", W))
    term.setCursorPos(W - 9, 3)
    term.setBackgroundColor(t.bgCard)
    term.write(" Sort:" .. sortBy:sub(1, 3) .. " ")

    local listH = H - 5
    _browseHits = {}

    if #listings == 0 then
        ui.write(2, 6, "No listings found.", t.textMuted, t.bg)
        ui.write(2, 7, "Be the first to post! [+]", t.text, t.bg)
    else
        for i = scroll, math.min(scroll + listH - 1, #listings) do
            local lst = listings[i]
            local ry  = 4 + (i - scroll) * 2
            if ry + 1 > H - 2 then break end
            term.setCursorPos(1, ry)
            term.setBackgroundColor(t.bg)
            term.setTextColor(t.text)
            term.write(utils.padRight("  " .. utils.truncate(lst.title or "?", W - 4), W))
            term.setCursorPos(1, ry + 1)
            term.setBackgroundColor(t.bg)
            term.setTextColor(t.textMuted)
            local sub = "@" .. (lst.seller or "?") .. "  \7 " .. utils.truncate(lst.wantedFor or "?", 12)
            term.write(utils.padRight("  " .. sub, W))
            table.insert(_browseHits, { y1 = ry, y2 = ry + 1, listing = lst })
        end
    end

    ui.button({ x = 1,     y = H, width = 3, label = "<",       style = "ghost" })
    ui.button({ x = 8,     y = H, width = 8, label = "My List",  style = "ghost" })
    ui.button({ x = W - 8, y = H, width = 8, label = "Refresh",  style = "ghost" })
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
    term.write(utils.padRight(" < Listing", W))

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

    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
    if lst.seller ~= myUsername then
        ui.button({ x = 8, y = H, width = 14, label = "Contact Seller" })
    else
        ui.button({ x = 8, y = H, width = 8, label = "Remove", style = "danger" })
    end
end

-- ─────────────────────────────────────────────────────────────
-- Post new listing — keyboard driven
-- ─────────────────────────────────────────────────────────────

local function drawPost()
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" < New Listing", W))

    ui.write(2, 3, "Tab / Enter = next field", t.textMuted, t.bg)

    local fieldOrder = { "title", "wantedFor", "description" }
    local fieldY     = { title = 5, wantedFor = 8, description = 11 }

    for _, f in ipairs(fieldOrder) do
        local fy = fieldY[f]
        ui.write(2, fy, FIELD_LABELS[f], t.textMuted, t.bg)
        ui.textbox({
            x = 2, y = fy + 1, width = W - 3,
            value   = newListing[f],
            focused = (editField == f),
            placeholder = FIELD_LABELS[f]:lower():gsub(":$", ""),
        })
    end

    ui.write(2, H - 2, "Enter on Description = Post!", t.textMuted, t.bg)
    ui.button({ x = W - 7, y = H, width = 7, label = "Post!" })
    ui.button({ x = 1,     y = H, width = 3, label = "<", style = "ghost" })
end

local function nextField()
    for i, f in ipairs(FIELDS) do
        if f == editField then
            editField = FIELDS[(i % #FIELDS) + 1]
            return
        end
    end
end

local function submitPost()
    if #newListing.title == 0 or #newListing.wantedFor == 0 then
        ui.toast({ text = "Fill in Title and Want fields.", type = "warning", y = H - 1 })
        os.sleep(1)
        drawPost()
        return
    end
    local t = Theme.get()
    showStatus("/ Posting listing...", H - 1, t.textMuted)
    local ok, resp = postListing(newListing)
    if ok then
        newListing = { title = "", description = "", wantedFor = "" }
        editField  = "title"
        view = "browse"
        showStatus("/ Loading...", H - 1, t.textMuted)
        
        -- Broadcast new listing notification via Skynet in real-time
        pcall(function()
            skynet.send("dorpos-marketplace-updates", { type = "new_listing" })
        end)

        fetchListings(searchQ, sortBy)
        drawBrowse()
    else
        ui.toast({ text = "Post failed. Try again.", type = "error", y = H - 1 })
        os.sleep(1)
        drawPost()
    end
end

-- ─────────────────────────────────────────────────────────────
-- My listings view
-- ─────────────────────────────────────────────────────────────

local _mineHits = {}

local function drawMine()
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" < My Listings", W))

    _mineHits = {}
    if #myListings == 0 then
        ui.write(2, 4, "You have no listings yet.", t.textMuted, t.bg)
    else
        for i, lst in ipairs(myListings) do
            local ry = 2 + i
            if ry > H - 2 then break end
            term.setCursorPos(1, ry)
            term.setBackgroundColor(t.bg)
            term.setTextColor(t.text)
            local status = lst.status == "sold" and " [SOLD]" or ""
            term.write(utils.padRight("  " .. utils.truncate(lst.title, W - 8) .. status, W))
            table.insert(_mineHits, { y = ry, listing = lst })
        end
    end

    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
end

-- ─────────────────────────────────────────────────────────────
-- Main loop — initial load and Skynet registration
-- ─────────────────────────────────────────────────────────────

showStatus("/ Loading listings...", H)
fetchListings()

-- Connect to Skynet marketplace channel
pcall(function()
    skynet.connect()
    skynet.open("dorpos-marketplace-updates")
end)

drawBrowse()

while true do
    local ev = { os.pullEvent() }
    local name = ev[1]

    -- ── Real-time Skynet Notifications ───────────────────────
    if name == "skynet_message" then
        local chan, msg = ev[2], ev[3]
        if chan == "dorpos-marketplace-updates" then
            -- Silent background update
            fetchListings(searchQ, sortBy)
            if view == "browse" then
                drawBrowse()
                ui.toast({ text = "Marketplace updated in real-time!", type = "info", y = H - 1 })
            end
        end
    end

    -- ── Debounced search timer fires ─────────────────────────
    if name == "timer" and ev[2] == _searchTimer then
        _searchTimer = nil
        local t = Theme.get()
        showStatus("/ Searching...", H, t.textMuted)
        fetchListings(searchQ, sortBy)
        drawBrowse()
    end

    -- ── BROWSE ───────────────────────────────────────────────
    if view == "browse" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if my == H and mx <= 3 then return end
            if my == H and mx >= 8 and mx <= 15 then
                local t = Theme.get()
                showStatus("/ Loading your listings...", H, t.textMuted)
                fetchMyListings()
                view = "mine"
                drawMine()
            elseif my == H and mx >= W - 8 then
                local t = Theme.get()
                showStatus("/ Refreshing...", H, t.textMuted)
                fetchListings(searchQ, sortBy)
                drawBrowse()
            elseif my == 1 and mx >= W - 2 then
                newListing = { title = "", description = "", wantedFor = "" }
                editField  = "title"
                view = "post"
                drawPost()
            elseif my == 3 and mx >= W - 9 then
                sortBy = sortBy == "newest" and "oldest" or "newest"
                local t = Theme.get()
                showStatus("/ Sorting...", H, t.textMuted)
                fetchListings(searchQ, sortBy)
                drawBrowse()
            else
                for _, h in ipairs(_browseHits) do
                    if my >= h.y1 and my <= h.y2 then
                        selListing = h.listing
                        view = "detail"
                        drawDetail(selListing)
                        break
                    end
                end
            end
        elseif name == "char" then
            -- Debounce: reset timer on every keystroke
            searchQ = searchQ .. ev[2]
            if _searchTimer then _searchTimer = nil end
            _searchTimer = os.startTimer(_SEARCH_DELAY)
            -- Redraw immediately to show current query text
            drawBrowse()
        elseif name == "key" then
            if ev[2] == keys.backspace and #searchQ > 0 then
                searchQ = searchQ:sub(1, -2)
                if _searchTimer then _searchTimer = nil end
                _searchTimer = os.startTimer(_SEARCH_DELAY)
                drawBrowse()
            end
        elseif name == "mouse_scroll" then
            scroll = math.max(1, scroll + ev[2])
            drawBrowse()
        end

    -- ── DETAIL ───────────────────────────────────────────────
    elseif view == "detail" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if my == H and mx <= 3 then
                view = "browse"; drawBrowse()
            elseif my == H and mx >= 8 then
                if selListing.seller ~= myUsername then
                    local t = Theme.get()
                    showStatus("/ Contacting seller...", H, t.textMuted)
                    contactSeller(selListing)
                    ui.toast({ text = "Message sent to seller!", type = "success", y = H - 1 })
                    os.sleep(1)
                    view = "browse"; drawBrowse()
                else
                    local t = Theme.get()
                    showStatus("/ Removing listing...", H, t.textMuted)
                    if removeListing(selListing.id) then
                        fetchListings(searchQ, sortBy)
                        view = "browse"; drawBrowse()
                    end
                end
            end
        end

    -- ── POST ─────────────────────────────────────────────────
    elseif view == "post" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if my == H and mx <= 3 then
                view = "browse"; drawBrowse()
            elseif my == H and mx >= W - 7 then
                submitPost()
            else
                -- Click on a field box to focus it
                local fieldY = { title = 6, wantedFor = 9, description = 12 }
                for _, f in ipairs(FIELDS) do
                    if my == fieldY[f] then editField = f; drawPost() end
                end
            end
        elseif name == "char" then
            newListing[editField] = newListing[editField] .. ev[2]
            drawPost()
        elseif name == "key" then
            local key = ev[2]
            if key == keys.backspace then
                local cur = newListing[editField]
                if #cur > 0 then newListing[editField] = cur:sub(1, -2) end
                drawPost()
            elseif key == keys.tab or key == keys.enter then
                -- Tab/Enter on last field = submit; otherwise next field
                if editField == "description" then
                    submitPost()
                else
                    nextField()
                    drawPost()
                end
            end
        end

    -- ── MINE ─────────────────────────────────────────────────
    elseif view == "mine" then
        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if my == H and mx <= 3 then
                view = "browse"; drawBrowse()
            else
                for _, h in ipairs(_mineHits) do
                    if my == h.y then
                        selListing = h.listing
                        view = "detail"
                        drawDetail(selListing)
                        break
                    end
                end
            end
        end
    end
end
