--[[  DorpOS :: phone/apps/files/init.lua
    File manager — browse, read, delete files on the CC filesystem.
]]
local C     = require("shared.constants")
local ui    = require("system.ui.ui")
local Theme = require("system.theme.theme")
local utils = require("system.utils.utils")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT

local cwd    = "/"
local scroll = 1
local selIdx = 1

local function listDir(path)
    local items = {}
    if path ~= "/" then
        table.insert(items, { name = "..", isDir = true, path = fs.getDir(path) })
    end
    local ok, list = pcall(fs.list, path)
    if not ok then return items end
    table.sort(list)
    for _, name in ipairs(list) do
        local full  = fs.combine(path, name)
        local isDir = fs.isDir(full)
        local size  = (not isDir) and fs.getSize(full) or nil
        table.insert(items, { name = name, isDir = isDir, path = full, size = size })
    end
    return items
end

local function formatSize(bytes)
    if not bytes then return "" end
    if bytes < 1024 then return bytes .. "B" end
    return math.floor(bytes / 1024) .. "K"
end

local function viewFile(path)
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" " .. fs.getName(path), W))

    local f = io.open(path, "r")
    if not f then
        ui.write(2, 4, "Cannot read file.", t.danger, t.bg)
    else
        local content = f:read("*a")
        f:close()
        local lines = {}
        for line in (content .. "\n"):gmatch("([^\n]*)\n") do
            for _, wl in ipairs(utils.wrap(line == "" and " " or line, W - 2)) do
                table.insert(lines, wl)
            end
        end

        local fileScroll = 0
        local visH = H - 2

        local function drawFile()
            for row = 1, visH do
                term.setCursorPos(1, row + 1)
                term.setBackgroundColor(t.bg)
                term.setTextColor(t.text)
                local li = fileScroll + row
                term.write(utils.padRight(lines[li] or "", W))
            end
            -- Scrollbar
            if #lines > visH then
                local ratio = visH / #lines
                local barH  = math.max(1, math.floor(visH * ratio))
                local barY  = 2 + math.floor(fileScroll / (#lines - visH) * (visH - barH))
                term.setBackgroundColor(t.accent)
                for r = barY, barY + barH - 1 do
                    term.setCursorPos(W, r)
                    term.write(" ")
                end
            end
        end

        drawFile()
        while true do
            local ev = { os.pullEvent() }
            if ev[1] == "mouse_scroll" then
                fileScroll = math.max(0, math.min(fileScroll + ev[2], math.max(0, #lines - visH)))
                drawFile()
            elseif ev[1] == "mouse_click" or ev[1] == "key" then
                return
            end
        end
    end

    os.pullEvent("mouse_click")
end

local function confirmDelete(path)
    return ui.dialog({
        title   = "Delete?",
        message = "Delete " .. fs.getName(path) .. "?",
        buttons = {
            { label = "Delete", style = "danger", value = true },
            { label = "Cancel", value = false },
        },
    })
end

local function drawBrowser(items)
    local t = Theme.get()
    ui.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" " .. utils.truncate(cwd, W - 2), W))

    local listH = H - 2
    local _hits = {}

    for i = scroll, math.min(scroll + listH - 1, #items) do
        local item = items[i]
        local ry   = 2 + (i - scroll)
        local isSel = (i == selIdx)
        local bg   = isSel and t.accent or t.bg
        local fg   = isSel and t.textOnAccent or t.text

        term.setCursorPos(1, ry)
        term.setBackgroundColor(bg)
        term.setTextColor(fg)

        local icon = item.isDir and ">" or " "
        local size = item.size and (" " .. formatSize(item.size)) or ""
        local avail = W - 3 - #size
        local name  = utils.padRight(icon .. " " .. utils.truncate(item.name, avail), W - #size)
        term.write(name)
        if #size > 0 then
            term.setTextColor(isSel and t.textOnAccent or t.textMuted)
            term.write(size)
        end

        table.insert(_hits, { y = ry, idx = i })
    end

    ui.button({ x = 1, y = H, width = 6, label = "Back", style = "ghost" })
    if selIdx > 1 then
        local sel = items[selIdx]
        if sel and not sel.isDir then
            ui.button({ x = W - 7, y = H, width = 7, label = "Delete", style = "danger" })
        end
    end
    return _hits
end

local function run()
    local items = listDir(cwd)
    local _hits = drawBrowser(items)

    while true do
        local ev = { os.pullEvent() }
        local name = ev[1]

        if name == "mouse_click" then
            local mx, my = ev[3], ev[4]

            if my == H then
                if mx <= 6 then return end
                if mx >= W - 7 and selIdx > 1 then
                    local sel = items[selIdx]
                    if sel and not sel.isDir then
                        if confirmDelete(sel.path) then
                            fs.delete(sel.path)
                        end
                        items = listDir(cwd)
                        selIdx = math.max(1, math.min(selIdx, #items))
                        _hits  = drawBrowser(items)
                    end
                end
            else
                for _, h in ipairs(_hits) do
                    if my == h.y then
                        selIdx = h.idx
                        local item = items[selIdx]
                        if item then
                            if item.isDir then
                                cwd    = item.path
                                scroll = 1; selIdx = 1
                                items  = listDir(cwd)
                                _hits  = drawBrowser(items)
                            else
                                viewFile(item.path)
                                _hits = drawBrowser(items)
                            end
                        end
                        break
                    end
                end
            end

        elseif name == "mouse_scroll" then
            scroll = math.max(1, math.min(scroll + ev[2], math.max(1, #items - (H - 3))))
            _hits  = drawBrowser(items)
        end
    end
end

run()
