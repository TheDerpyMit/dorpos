--[[  DorpOS :: phone/apps/notes/init.lua
    Notes app — create, edit, delete, search notes stored locally.
]]
local C       = require("shared.constants")
local ui      = require("system.ui.ui")
local Theme   = require("system.theme.theme")
local Storage = require("system.storage.storage")
local utils   = require("system.utils.utils")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT

local store     = Storage.open("notes")
local notes     = store.get("list", {})
local view      = "list"   -- "list" | "edit" | "new"
local selIdx    = 1
local editNote  = nil
local scroll    = 1
local searchQ   = ""

local kbComp = require("system.ui.components.keyboard")

local function saveNotes()
    store.set("list", notes)
    store.save()
end

-- ─── Editor ──────────────────────────────────────────────────

local function runEditor(note)
    -- note = { title, body, created, modified }
    local t       = Theme.get()
    local title   = note.title or ""
    local body    = note.body  or ""
    local focused = "title"  -- "title" | "body"
    local shifted = false
    local kbHits  = nil
    local bodyScroll = 0
    local bodyLines  = {}

    local function rebuildLines()
        bodyLines = {}
        for _, line in ipairs(utils.wrap(body, W - 2)) do
            table.insert(bodyLines, line)
        end
        if #bodyLines == 0 then bodyLines = {""} end
    end

    rebuildLines()

    local function redraw()
        ui.clear()
        -- Header
        term.setCursorPos(1, 1)
        term.setBackgroundColor(t.accent)
        term.setTextColor(t.textOnAccent)
        term.write(utils.padRight(" Note Editor   [Save]", W))
        -- Title field
        ui.write(2, 2, "Title:", t.textMuted, t.bg)
        ui.textbox({ x = 2, y = 3, width = W - 3, value = title,
                     focused = (focused == "title"), placeholder = "Note title" })
        ui.divider(4)
        -- Body area
        local bodyH = H - 4 - 7
        local visLines = {}
        for i = bodyScroll + 1, math.min(bodyScroll + bodyH, #bodyLines) do
            table.insert(visLines, bodyLines[i])
        end
        for i, line in ipairs(visLines) do
            term.setCursorPos(2, 4 + i)
            term.setBackgroundColor(t.bgInput)
            term.setTextColor(t.text)
            term.write(utils.padRight(line, W - 3))
        end
        -- Keyboard
        kbHits = kbComp.draw({
            y = H - 6, shifted = shifted,
            onChar  = function(c)
                if focused == "title" then
                    title = title .. c
                else
                    body = body .. c; rebuildLines()
                end
            end,
            onBack = function()
                if focused == "title" and #title > 0 then
                    title = title:sub(1, -2)
                elseif focused == "body" and #body > 0 then
                    body = body:sub(1, -2); rebuildLines()
                end
            end,
            onEnter = function()
                if focused == "title" then focused = "body"
                else body = body .. "\n"; rebuildLines() end
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
            -- Save button
            if my == 1 and mx >= W - 5 then
                note.title    = title
                note.body     = body
                note.modified = os.epoch("utc")
                return note
            end
            -- Field focus
            if my == 3 then focused = "title"; redraw()
            elseif my >= 5 and my <= H - 8 then focused = "body"; redraw()
            elseif kbHits and kbComp.handleClick(kbHits, mx, my) then
                rebuildLines(); redraw()
            end
        elseif name == "char" then
            if focused == "title" then title = title .. ev[2]
            else body = body .. ev[2]; rebuildLines() end
            redraw()
        elseif name == "key" then
            local key = ev[2]
            if key == keys.backspace then
                if focused == "title" and #title > 0 then title = title:sub(1, -2)
                elseif focused == "body" and #body > 0 then body = body:sub(1, -2); rebuildLines() end
                redraw()
            elseif key == keys.tab then
                focused = focused == "title" and "body" or "title"; redraw()
            end
        end
    end
end

-- ─── List view ───────────────────────────────────────────────

local function filteredNotes()
    if searchQ == "" then return notes end
    local q = searchQ:lower()
    local out = {}
    for _, n in ipairs(notes) do
        if (n.title or ""):lower():find(q, 1, true)
        or (n.body  or ""):lower():find(q, 1, true) then
            table.insert(out, n)
        end
    end
    return out
end

local function drawList()
    local t      = Theme.get()
    local fnotes = filteredNotes()
    ui.clear()

    -- Header
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    local title = " Notes"
    local btn = "[+]"
    term.write(title .. string.rep(" ", W - #title - #btn) .. btn)

    -- Search bar
    term.setCursorPos(1, 2)
    term.setBackgroundColor(t.bgInput)
    term.setTextColor(t.text)
    term.write(utils.padRight("  " .. (searchQ == "" and "Search..." or searchQ), W))

    -- Notes list
    local listH = H - 3
    local _hits = {}
    for i = scroll, math.min(scroll + listH - 1, #fnotes) do
        local n  = fnotes[i]
        local ry = 3 + (i - scroll)
        local isSel = (i == selIdx)
        local bg = isSel and t.accent or t.bg
        local fg = isSel and t.textOnAccent or t.text

        term.setCursorPos(1, ry)
        term.setBackgroundColor(bg)
        term.setTextColor(fg)
        term.write(utils.padRight(utils.truncate("  " .. (n.title or "Untitled"), W - 1), W))

        local ni = i
        table.insert(_hits, { y = ry, idx = ni })
    end

    if #fnotes == 0 then
        ui.write(2, 6, "No notes yet.", t.textMuted, t.bg)
        ui.write(2, 7, "Tap [+] to create one.", t.textMuted, t.bg)
    end

    -- Back
    ui.button({ x = 1, y = H, width = 6, label = "Back", style = "ghost" })
    return _hits
end

local function run()
    local _hits = drawList()

    while true do
        local ev = { os.pullEvent() }
        local name = ev[1]

        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]

            -- Header: back or new
            if my == 1 then
                if mx >= W - 2 then
                    -- New note
                    local newNote = { title = "", body = "", created = os.epoch("utc"), modified = os.epoch("utc") }
                    local result  = runEditor(newNote)
                    if result and #result.title > 0 then
                        table.insert(notes, result)
                        saveNotes()
                    end
                    _hits = drawList()
                end
            elseif my == H and mx <= 6 then
                return  -- back to home
            elseif my == 2 then
                -- Search focus handled via char events below
            else
                for _, h in ipairs(_hits) do
                    if my == h.y then
                        selIdx = h.idx
                        local fn = filteredNotes()
                        local result = runEditor(fn[h.idx])
                        if result then
                            -- Update original note in notes list
                            for j, n in ipairs(notes) do
                                if n == fn[h.idx] then notes[j] = result; break end
                            end
                            saveNotes()
                        end
                        _hits = drawList()
                        break
                    end
                end
            end

        elseif name == "char" then
            searchQ = searchQ .. ev[2]
            _hits = drawList()
        elseif name == "key" then
            local key = ev[2]
            if key == keys.backspace and #searchQ > 0 then
                searchQ = searchQ:sub(1, -2)
                _hits = drawList()
            end
        elseif name == "mouse_scroll" then
            scroll = math.max(1, scroll + ev[2])
            _hits = drawList()
        end
    end
end

run()
