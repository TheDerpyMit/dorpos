--[[  DorpOS :: servers/shared/monitor_dashboard.lua
    Server Monitor Dashboard

    When a 3x3 Advanced Monitor is attached, this module renders a live
    server dashboard on it:

    ┌────────────────────────────────────────────────────────────────────┐
    │  DorpOS Server Monitor                           [uptime]          │
    ├──────────┬──────────┬──────────┬──────────┬──────────┬────────────┤
    │ Accounts │ Messages │ Market   │ Notifs   │ Updates  │ Cloud      │
    │ ● Online │ ● Online │ ● Online │ ● Online │ ● Online │ ● Online   │
    │ Reqs: 14 │ Reqs: 7  │ Reqs: 3  │ Reqs: 22 │ Reqs: 1  │ Reqs: 0    │
    │ Errs:  0 │ Errs: 0  │ Errs: 0  │ Errs: 0  │ Errs: 0  │ Errs: 0    │
    │ Last:    │ Last:    │ Last:    │ Last:    │ Last:    │ Last:       │
    │/account/ │/messages/│/market/  │/notif/   │/updates/ │/cloud/     │
    ├──────────┴──────────┴──────────┴──────────┴──────────┴────────────┤
    │ [INFO ] Accounts  /account/login              OK 200               │
    │ [INFO ] Messages  /messages/send              OK 200               │
    │ [WARN ] Accounts  Handler error on /friends/  500                  │
    │ [INFO ] Market    /market/browse              OK 200               │
    └────────────────────────────────────────────────────────────────────┘

    Usage:
        local dash = require("servers.shared.monitor_dashboard")
        dash.register("Accounts")
        dash.log("Accounts", "info", "Ready and listening...")
        dash.request("Accounts", "/account/login", 200)
        dash.redraw()   -- call periodically or after each log entry
]]

local dash = {}

-- ─────────────────────────────────────────────────────────────
-- Detect monitor
-- ─────────────────────────────────────────────────────────────

local _mon         = nil   -- the monitor peripheral
local _monW        = 0
local _monH        = 0

local function findMonitor()
    -- Look for any monitor peripheral
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            return peripheral.wrap(name)
        end
    end
    return nil
end

local function initMonitor()
    _mon = findMonitor()
    if not _mon then return false end
    _mon.setTextScale(0.5)   -- smallest scale → most characters on 3x3
    _monW, _monH = _mon.getSize()
    return true
end

-- ─────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────

-- Ordered list of registered server names
local _servers     = {}
-- Per-server stats: { name, status, requests, errors, lastEndpoint, lastCode }
local _stats       = {}
-- Ring buffer of recent log lines (max 200 entries)
local _logBuf      = {}
local LOG_BUF_MAX  = 200
-- Boot time
local _bootEpoch   = os.epoch("utc")
-- Scroll offset for log panel
local _logScroll   = 0

-- Colour scheme
local COL = {
    bg       = colors.black,
    title    = colors.cyan,
    border   = colors.gray,
    nameOnline = colors.lime,
    nameOffline = colors.red,
    stat     = colors.white,
    statDim  = colors.lightGray,
    logInfo  = colors.lightBlue,
    logWarn  = colors.yellow,
    logError = colors.red,
    logOk    = colors.lime,
    logMuted = colors.gray,
    panelBg  = colors.black,
    headerBg = colors.blue,
    logBg    = colors.black,
    accent   = colors.cyan,
    rowAlt   = colors.black,
}

-- ─────────────────────────────────────────────────────────────
-- Public: register / log / request
-- ─────────────────────────────────────────────────────────────

--- Register a server so it gets a panel.
---@param name string
function dash.register(name)
    if _stats[name] then return end
    table.insert(_servers, name)
    _stats[name] = {
        name        = name,
        online      = true,
        requests    = 0,
        errors      = 0,
        lastEndpoint= "(waiting...)",
        lastCode    = nil,
        lastTs      = nil,
    }
end

--- Add a log entry.
---@param server  string   Server name (or "All")
---@param level   string   "info"|"warn"|"error"|"ok"
---@param message string
function dash.log(server, level, message)
    local entry = {
        ts      = os.epoch("utc"),
        server  = server,
        level   = level,
        message = message,
    }
    table.insert(_logBuf, entry)
    if #_logBuf > LOG_BUF_MAX then table.remove(_logBuf, 1) end
    -- Print to terminal too
    print(string.format("[%s] [%s] %s", server, level:upper(), message))
end

--- Record an incoming request (called after response is sent).
---@param server   string
---@param endpoint string
---@param code     number   HTTP-style response code
function dash.request(server, endpoint, code)
    local s = _stats[server]
    if not s then return end
    s.requests    = s.requests + 1
    s.lastEndpoint = endpoint
    s.lastCode    = code
    s.lastTs      = os.epoch("utc")
    if code and code >= 500 then
        s.errors = s.errors + 1
    end
    local level = (code and code >= 500) and "error"
                  or (code and code >= 400) and "warn"
                  or "ok"
    dash.log(server, level,
        string.format("%-22s %s %d",
            endpoint:sub(1, 22),
            (code and code < 300) and "OK" or "ERR",
            code or 0))
end

--- Mark a server as crashed / offline.
---@param server string
function dash.setOffline(server)
    if _stats[server] then
        _stats[server].online = false
        dash.log(server, "error", "Server went offline!")
    end
end

-- ─────────────────────────────────────────────────────────────
-- Drawing helpers (all write to _mon)
-- ─────────────────────────────────────────────────────────────

local function mset(x, y, fg, bg, text)
    if not _mon then return end
    _mon.setCursorPos(x, y)
    _mon.setTextColor(fg)
    _mon.setBackgroundColor(bg)
    _mon.write(text)
end

local function mfill(x, y, w, bg)
    mset(x, y, COL.stat, bg, string.rep(" ", w))
end

local function mwrite(x, y, w, fg, bg, text)
    -- Truncate/pad to exactly w characters
    if #text > w then text = text:sub(1, w) end
    mset(x, y, fg, bg, text)
    local rem = w - #text
    if rem > 0 then
        _mon.setBackgroundColor(bg)
        _mon.write(string.rep(" ", rem))
    end
end

local function hline(y, bg)
    mfill(1, y, _monW, bg or COL.border)
end

local function vline(x, y1, y2, bg)
    for y = y1, y2 do
        _mon.setCursorPos(x, y)
        _mon.setBackgroundColor(bg or COL.border)
        _mon.write(" ")
    end
end

local function box(x, y, w, h, bg)
    for row = y, y + h - 1 do
        mfill(x, row, w, bg or COL.panelBg)
    end
end

-- ─────────────────────────────────────────────────────────────
-- Layout computation
-- ─────────────────────────────────────────────────────────────

local HEADER_H   = 2    -- title bar rows
local PANEL_ROWS = 7    -- rows per server panel
local LOG_MIN_H  = 6    -- minimum rows for log area
local SEPARATOR  = 1    -- 1-char wide column separator

local function layout()
    -- How many servers? Cap at 8
    local n = math.min(#_servers, 8)
    if n == 0 then return nil end

    -- How many columns of panels? Try to fit them across the width.
    -- Each panel needs at least 10 chars wide.
    local MIN_PANEL_W = 10
    local cols = math.min(n, math.floor((_monW + 1) / (MIN_PANEL_W + SEPARATOR)))
    cols = math.max(cols, 1)
    local rows = math.ceil(n / cols)
    local panelW = math.floor((_monW - (cols - 1) * SEPARATOR) / cols)

    -- Panels occupy: HEADER_H + rows * PANEL_ROWS
    local panelEndY = HEADER_H + rows * PANEL_ROWS
    local logY = panelEndY + 1
    local logH = _monH - logY + 1

    return {
        n       = n,
        cols    = cols,
        rows    = rows,
        panelW  = panelW,
        panelEndY = panelEndY,
        logY    = logY,
        logH    = logH,
    }
end

-- ─────────────────────────────────────────────────────────────
-- Main draw
-- ─────────────────────────────────────────────────────────────

local function drawHeader(L)
    -- Title bar
    mfill(1, 1, _monW, COL.headerBg)
    local title = " DorpOS Server Monitor"
    mset(1, 1, COL.title, COL.headerBg, title)

    -- Uptime
    local upSec = math.floor((os.epoch("utc") - _bootEpoch) / 1000)
    local upH = math.floor(upSec / 3600)
    local upM = math.floor((upSec % 3600) / 60)
    local upS = upSec % 60
    local upStr = string.format("up %02d:%02d:%02d", upH, upM, upS)
    mset(_monW - #upStr, 1, COL.statDim, COL.headerBg, upStr)

    -- Divider row
    mfill(1, 2, _monW, COL.border)
    mset(1, 2, COL.accent, COL.border,
        string.rep(" ", _monW))
end

local function drawPanel(serverName, panelX, panelY, panelW)
    local s = _stats[serverName]
    if not s then return end

    local bg = COL.panelBg

    -- Row 1: Server name bar
    local nameBg = s.online and colors.blue or colors.red
    mfill(panelX, panelY, panelW, nameBg)
    local nameLabel = serverName
    if #nameLabel > panelW - 2 then nameLabel = nameLabel:sub(1, panelW - 2) end
    mset(panelX + 1, panelY, colors.white, nameBg, nameLabel)

    -- Row 2: Status indicator
    local dot = s.online and "\7" or "x"
    local dotColor = s.online and COL.nameOnline or COL.nameOffline
    local statusText = s.online and "Online" or "Offline"
    mfill(panelX, panelY + 1, panelW, bg)
    mset(panelX + 1, panelY + 1, dotColor, bg, dot)
    mset(panelX + 3, panelY + 1, s.online and COL.nameOnline or COL.nameOffline, bg, statusText)

    -- Row 3: Request count
    mfill(panelX, panelY + 2, panelW, bg)
    mset(panelX + 1, panelY + 2, COL.statDim, bg, "Reqs:")
    mset(panelX + 7, panelY + 2, COL.stat, bg, tostring(s.requests))

    -- Row 4: Error count
    mfill(panelX, panelY + 3, panelW, bg)
    local errColor = s.errors > 0 and COL.logError or COL.statDim
    mset(panelX + 1, panelY + 3, COL.statDim, bg, "Errs:")
    mset(panelX + 7, panelY + 3, errColor, bg, tostring(s.errors))

    -- Row 5: "Last:" label
    mfill(panelX, panelY + 4, panelW, bg)
    mset(panelX + 1, panelY + 4, COL.statDim, bg, "Last:")

    -- Row 6: last endpoint (truncated)
    mfill(panelX, panelY + 5, panelW, bg)
    if s.lastEndpoint then
        local ep = s.lastEndpoint
        if #ep > panelW - 2 then ep = ep:sub(1, panelW - 2) end
        local epColor = (s.lastCode and s.lastCode >= 400) and COL.logError
                        or COL.logOk
        mset(panelX + 1, panelY + 5, epColor, bg, ep)
    end

    -- Row 7: code + separator line
    mfill(panelX, panelY + 6, panelW, COL.border)
    if s.lastCode then
        local codeColor = s.lastCode >= 500 and COL.logError
                          or s.lastCode >= 400 and COL.logWarn
                          or COL.logOk
        mset(panelX + 1, panelY + 6, codeColor, COL.border,
            tostring(s.lastCode))
    end
end

local function drawPanels(L)
    for i, sname in ipairs(_servers) do
        if i > L.n then break end
        local col = (i - 1) % L.cols
        local row = math.floor((i - 1) / L.cols)
        local panelX = 1 + col * (L.panelW + SEPARATOR)
        local panelY = HEADER_H + 1 + row * PANEL_ROWS
        drawPanel(sname, panelX, panelY, L.panelW)
        -- Separator column (right of panel, except last column)
        if col < L.cols - 1 then
            vline(panelX + L.panelW, panelY, panelY + PANEL_ROWS - 1, COL.border)
        end
    end
end

-- Log entry colour
local function logColour(level)
    if level == "error" then return COL.logError
    elseif level == "warn"  then return COL.logWarn
    elseif level == "ok"    then return COL.logOk
    else return COL.logInfo end
end

-- Log level tag (fixed 4 chars)
local function logTag(level)
    if level == "error" then return "ERR!"
    elseif level == "warn"  then return "WARN"
    elseif level == "ok"    then return " OK "
    else return "INFO" end
end

local function drawLogPanel(L)
    if L.logH < 2 then return end

    -- Header bar for log panel
    mfill(1, L.logY, _monW, COL.headerBg)
    mset(1, L.logY, COL.accent, COL.headerBg,
        string.format(" Recent Activity  (%d entries total) ", #_logBuf))

    -- Log lines
    local start = math.max(1, #_logBuf - (L.logH - 2) + 1 - _logScroll)
    local row = L.logY + 1
    for i = start, math.min(start + L.logH - 2, #_logBuf) do
        local e = _logBuf[i]
        if not e then break end
        mfill(1, row, _monW, COL.logBg)
        -- Timestamp (seconds since boot)
        local sec = math.floor((e.ts - _bootEpoch) / 1000)
        local tsStr = string.format("%5ds", sec)
        mset(1, row, COL.logMuted, COL.logBg, tsStr)
        -- Level badge
        local badge = "[" .. logTag(e.level) .. "]"
        mset(7, row, logColour(e.level), COL.logBg, badge)
        -- Server name (8 chars padded)
        local sname = e.server or "?"
        if #sname > 8 then sname = sname:sub(1, 8) end
        mset(14, row, COL.statDim, COL.logBg,
            string.format("%-8s", sname))
        -- Message
        local msgX = 23
        local msgW = _monW - msgX
        local msg  = e.message or ""
        if #msg > msgW then msg = msg:sub(1, msgW) end
        mset(msgX, row, colors.white, COL.logBg, msg)

        row = row + 1
    end
end

-- ─────────────────────────────────────────────────────────────
-- Public: redraw
-- ─────────────────────────────────────────────────────────────

--- Redraw the entire monitor dashboard.
--- Call this after every log entry or on a timer.
function dash.redraw()
    if not _mon then
        if not initMonitor() then return end
    end

    -- Re-check size (monitor may have been resized)
    _monW, _monH = _mon.getSize()

    _mon.setBackgroundColor(COL.bg)
    _mon.clear()

    local L = layout()
    if not L then
        mset(1, 1, COL.logWarn, COL.bg, "No servers registered yet.")
        return
    end

    drawHeader(L)
    drawPanels(L)
    drawLogPanel(L)
end

--- Scroll the log panel up/down. dir = +1 (up) or -1 (down).
function dash.scroll(dir)
    _logScroll = math.max(0, _logScroll + dir)
end

--- Call once at startup to initialise monitor.
function dash.init()
    initMonitor()
    if _mon then
        _mon.setBackgroundColor(COL.bg)
        _mon.clear()
        mset(1, 1, COL.accent, COL.bg,
            " DorpOS Server Monitor — starting up...")
    end
end

return dash
