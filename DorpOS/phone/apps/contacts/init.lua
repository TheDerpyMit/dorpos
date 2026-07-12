--[[  DorpOS :: phone/apps/contacts/init.lua
    Contacts app — local address book synced with Accounts server.
]]
local C       = require("shared.constants")
local ui      = require("system.ui.ui")
local Theme   = require("system.theme.theme")
local Storage = require("system.storage.storage")
local net     = require("system.network.network")
local utils   = require("system.utils.utils")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT
local kbComp = require("system.ui.components.keyboard")

local store    = Storage.open("contacts")
local contacts = store.get("list", {})
local scroll   = 1
local selIdx   = 1
local searchQ  = ""
local shifted  = false

local function saveContacts()
    store.set("list", contacts)
    store.save()
end

local function sortedContacts()
    local list = {}
    for i, c in ipairs(contacts) do
        table.insert(list, { idx = i, c = c })
    end
    table.sort(list, function(a, b)
        return (a.c.name or "") < (b.c.name or "")
    end)
    local out = {}
    for _, e in ipairs(list) do table.insert(out, e.c) end
    return out
end

local function filtered()
    local all = sortedContacts()
    if searchQ == "" then return all end
    local q = searchQ:lower()
    local out = {}
    for _, c in ipairs(all) do
        if (c.name or ""):lower():find(q, 1, true) then
            table.insert(out, c)
        end
    end
    return out
end

-- ─── Contact editor ──────────────────────────────────────────
local function editContact(c)
    c = c or { name = "", username = "", note = "" }
    local t = Theme.get()
    local fields = { "name", "username", "note" }
    local labels = { "Name", "Username", "Note" }
    local values = { c.name or "", c.username or "", c.note or "" }
    local focusIdx = 1
    local kbHits = nil

    local function redraw()
        ui.clear()
        term.setCursorPos(1, 1)
        term.setBackgroundColor(t.accent)
        term.setTextColor(t.textOnAccent)
        term.write(utils.padRight(" Contact   [Save]", W))

        for i, lbl in ipairs(labels) do
            ui.write(2, 1 + i * 2, lbl .. ":", t.textMuted, t.bg)
            ui.textbox({ x = 2, y = 2 + i * 2, width = W - 3,
                         value = values[i], focused = (i == focusIdx),
                         placeholder = "Enter " .. lbl:lower() })
        end

        kbHits = kbComp.draw({
            y = H - 6, shifted = shifted,
            onChar  = function(ch) values[focusIdx] = values[focusIdx] .. ch end,
            onBack  = function()
                if #values[focusIdx] > 0 then
                    values[focusIdx] = values[focusIdx]:sub(1, -2)
                end
            end,
            onEnter = function()
                focusIdx = (focusIdx % #fields) + 1
            end,
            onShift = function() shifted = not shifted end,
            onClose = function() end,
        })
    end

    redraw()

    while true do
        local ev = { os.pullEvent() }
        local name = ev[1]

        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]
            if my == 1 and mx >= W - 5 then
                -- Save
                return { name = values[1], username = values[2], note = values[3] }
            end
            -- Field focus
            for i = 1, #fields do
                if my == 2 + i * 2 then focusIdx = i end
            end
            if kbHits then kbComp.handleClick(kbHits, mx, my) end
            redraw()
        elseif name == "char" then
            values[focusIdx] = values[focusIdx] .. ev[2]; redraw()
        elseif name == "key" then
            local key = ev[2]
            if key == keys.backspace and #values[focusIdx] > 0 then
                values[focusIdx] = values[focusIdx]:sub(1, -2); redraw()
            elseif key == keys.tab then
                focusIdx = (focusIdx % #fields) + 1; redraw()
            end
        end
    end
end

-- ─── Sync with server ────────────────────────────────────────
local function syncContacts()
    local ok, resp = net.post(C.HOST_ACCOUNTS, "/contacts/sync", {
        contacts = contacts,
    })
    if ok and resp.body.contacts then
        contacts = resp.body.contacts
        saveContacts()
    end
end

-- ─── List ────────────────────────────────────────────────────
local function drawList()
    local t    = Theme.get()
    local list = filtered()
    ui.clear()

    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    local title = " Contacts"
    local btn = "[sync] [+]"
    term.write(title .. string.rep(" ", W - #title - #btn) .. btn)

    term.setCursorPos(1, 2)
    term.setBackgroundColor(t.bgInput)
    term.setTextColor(t.text)
    term.write(utils.padRight("  " .. (searchQ == "" and "Search..." or searchQ), W))

    local listH = H - 3
    local _hits = {}
    for i = scroll, math.min(scroll + listH - 1, #list) do
        local c   = list[i]
        local ry  = 3 + (i - scroll)
        local isSel = (i == selIdx)
        local bg  = isSel and t.accent or t.bg
        local fg  = isSel and t.textOnAccent or t.text
        term.setCursorPos(1, ry)
        term.setBackgroundColor(bg)
        term.setTextColor(fg)
        local sub = c.username and ("@" .. c.username) or ""
        term.write(utils.padRight("  " .. utils.truncate(c.name or "?", W - 6) .. "  " .. utils.truncate(sub, 6), W))
        table.insert(_hits, { y = ry, idx = i })
    end

    if #list == 0 then
        ui.write(2, 6, "No contacts.", t.textMuted, t.bg)
    end

    ui.button({ x = 1, y = H, width = 3, label = "<", style = "ghost" })
    return _hits, list
end

local _hits, list = drawList()

while true do
    local ev = { os.pullEvent() }
    local name = ev[1]

    if name == "mouse_click" then
        local mx, my = ev[3], ev[4]
        if my == H and mx <= 3 then return end
        if my == 1 then
            if mx >= W - 9 and mx <= W - 4 then
                -- Sync
                syncContacts()
                list = filtered()
                _hits, list = drawList()
            elseif mx >= W - 2 then
                -- New contact
                local result = editContact(nil)
                if result and #(result.name or "") > 0 then
                    table.insert(contacts, result)
                    saveContacts()
                end
                _hits, list = drawList()
            end
        else
            for _, h in ipairs(_hits) do
                if my == h.y then
                    selIdx = h.idx
                    local result = editContact(list[h.idx])
                    if result then
                        -- Find original and update
                        local orig = list[h.idx]
                        for j, c in ipairs(contacts) do
                            if c == orig then contacts[j] = result; break end
                        end
                        saveContacts()
                    end
                    _hits, list = drawList()
                    break
                end
            end
        end
    elseif name == "char" then
        searchQ = searchQ .. ev[2]
        _hits, list = drawList()
    elseif name == "key" then
        if ev[2] == keys.backspace and #searchQ > 0 then
            searchQ = searchQ:sub(1, -2)
            _hits, list = drawList()
        end
    elseif name == "mouse_scroll" then
        scroll = math.max(1, scroll + ev[2])
        _hits, list = drawList()
    end
end
