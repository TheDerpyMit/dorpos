--[[  DorpOS :: servers/shared/monitor_dashboard.lua
    Server Monitor Dashboard — live display on any attached monitor.

    Attach any monitor (ideally 3x3 Advanced) to the server computer.
    The dashboard auto-detects it and renders per-server panels plus a
    colour-coded activity log.

    ┌ DorpOS Server Monitor ──────────────────── up 00:04:12 ┐
    │ Accounts  │ Messages  │ Market    │ Notifs    │ ...     │
    │ ● Online  │ ● Online  │ ● Online  │ ● Online  │         │
    │ Reqs:  14 │ Reqs:   7 │ Reqs:   3 │ Reqs:  22 │         │
    │ Errs:   0 │ Errs:   0 │ Errs:   0 │ Errs:   0 │         │
    │ /account/ │ /messages │ /market/  │ /notif/   │         │
    ├───────────┴───────────┴───────────┴───────────┴─────────┤
    │  0001s [INFO] Accounts   /account/login             200  │
    │  0012s [ OK ] Messages   /messages/send             200  │
    │  0025s [WARN] Accounts   /friends/request           409  │
    └─────────────────────────────────────────────────────────┘
]]

local dash = {}

-- ─────────────────────────────────────────────────────────────
-- Monitor detection
-- ─────────────────────────────────────────────────────────────

local _mon  = nil
local _monW = 0
local _monH = 0

local function findMonitor()
    -- peripheral.find is the most reliable way in CC:T
    local m = peripheral.find("monitor")
    if m then return m end
    -- fallback: scan sides
    for _, side in ipairs({"top","bottom","left","right","front","back"}) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "monitor" then
            return peripheral.wrap(side)
        end
    end
    return nil
end

local function initMonitor()
    local m = findMonitor()
    if not m then
        _mon = nil
        return false
    end
    _mon  = m
    -- Set smallest scale for maximum resolution on 3x3
    pcall(function() _mon.setTextScale(0.5) end)
    _monW, _monH = _mon.getSize()
    return true
end

-- ─────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────

local _servers   = {}  -- ordered list of registered server names
local _stats     = {}  -- { [name] = { online, requests, errors, lastEndpoint, lastCode, lastTs } }
local _logBuf    = {}  -- ring buffer of log entries
local LOG_MAX    = 300
local _boot      = os.epoch("utc")

-- expose stats for server_base peek
dash._stats = _stats

-- Colour palette
local C = {
    bg        = colors.black,
    headerBg  = colors.gray,
    headerFg  = colors.white,
    accent    = colors.cyan,
    panelBg   = colors.black,
    nameBg    = colors.blue,
    nameFg    = colors.white,
    nameErr   = colors.red,
    online    = colors.lime,
    offline   = colors.red,
    statFg    = colors.white,
    dimFg     = colors.gray,
    sepBg     = colors.gray,
    logBg     = colors.black,
    logInfo   = colors.lightBlue,
    logOk     = colors.lime,
    logWarn   = colors.yellow,
    logErr    = colors.red,
    logDim    = colors.gray,
    logFg     = colors.white,
}

-- ─────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────

function dash.register(name)
    if _stats[name] then return end
    table.insert(_servers, name)
    _stats[name] = {
        online       = true,
        requests     = 0,
        errors       = 0,
        lastEndpoint = "(starting...)",
        lastCode     = nil,
        lastTs       = nil,
    }
end

function dash.log(server, level, message)
    table.insert(_logBuf, {
        ts      = os.epoch("utc"),
        server  = server  or "?",
        level   = level   or "info",
        message = message or "",
    })
    if #_logBuf > LOG_MAX then table.remove(_logBuf, 1) end
    -- Also print to terminal
    print(string.format("[%s][%s] %s", server or "?", (level or "info"):upper(), message or ""))
end

function dash.request(server, endpoint, code)
    local s = _stats[server]
    if not s then return end
    s.requests    = s.requests + 1
    s.lastEndpoint = endpoint or "?"
    s.lastCode    = code
    s.lastTs      = os.epoch("utc")
    if code and code >= 500 then s.errors = s.errors + 1 end

    local level = (code and code >= 500) and "error"
                  or (code and code >= 400) and "warn"
                  or "ok"
    dash.log(server, level,
        string.format("%-24s %3d", (endpoint or "?"):sub(1,24), code or 0))
end

function dash.setOffline(server)
    if _stats[server] then
        _stats[server].online = false
    end
    dash.log(server, "error", "Server OFFLINE / crashed!")
end

-- ─────────────────────────────────────────────────────────────
-- Safe monitor writes (all output goes through here)
-- ─────────────────────────────────────────────────────────────

local function mpos(x, y)       _mon.setCursorPos(x, y)                    end
local function mfg(col)         _mon.setTextColor(col)                     end
local function mbg(col)         _mon.setBackgroundColor(col)               end
local function mwrite(text)     _mon.write(text)                           end
local function mpad(x, y, w, bg)
    mbg(bg)
    mpos(x, y)
    mwrite(string.rep(" ", w))
end
local function mtext(x, y, w, fg, bg, text)
    mpad(x, y, w, bg)
    mpos(x, y)
    mfg(fg); mbg(bg)
    if #text > w then text = text:sub(1, w) end
    mwrite(text)
end

-- ─────────────────────────────────────────────────────────────
-- Layout
-- ─────────────────────────────────────────────────────────────

local PANEL_H    = 7   -- rows per server panel
local HEADER_H   = 2   -- title + divider
local SEP_W      = 1   -- column separator width
local MIN_PANEL_W= 12  -- minimum panel width in chars

local function computeLayout()
    local n = #_servers
    if n == 0 then return nil end

    local cols = math.min(n, math.max(1, math.floor((_monW + SEP_W) / (MIN_PANEL_W + SEP_W))))
    local rows = math.ceil(n / cols)
    local panelW = math.floor((_monW - (cols-1)*SEP_W) / cols)

    local panelArea = HEADER_H + rows * PANEL_H
    local logY = panelArea + 1
    local logH = _monH - logY + 1

    return {
        n=n, cols=cols, rows=rows,
        panelW=panelW,
        panelArea=panelArea,
        logY=logY, logH=logH,
    }
end

-- ─────────────────────────────────────────────────────────────
-- Draw routines
-- ─────────────────────────────────────────────────────────────

local function drawHeader()
    -- Row 1: title
    mpad(1, 1, _monW, C.headerBg)
    mtext(1, 1, 22, C.accent, C.headerBg, " DorpOS Server Monitor")
    -- Uptime
    local sec  = math.floor((os.epoch("utc") - _boot) / 1000)
    local up   = string.format("up %02d:%02d:%02d", math.floor(sec/3600), math.floor(sec%3600/60), sec%60)
    mtext(_monW - #up, 1, #up, C.dimFg, C.headerBg, up)
    -- Row 2: separator
    mpad(1, 2, _monW, C.sepBg)
    mfg(C.accent); mbg(C.sepBg)
    mpos(1, 2)
    mwrite(string.rep("\140", _monW))  -- solid line char
end

local function drawPanel(idx, L)
    local name = _servers[idx]
    local s    = _stats[name]
    if not s then return end

    local col  = (idx-1) % L.cols
    local row  = math.floor((idx-1) / L.cols)
    local px   = 1 + col * (L.panelW + SEP_W)
    local py   = HEADER_H + 1 + row * PANEL_H
    local pw   = L.panelW

    -- Row 1: server name (coloured header)
    local nbg = s.online and C.nameBg or C.nameErr
    mpad(px, py, pw, nbg)
    mfg(C.nameFg); mbg(nbg); mpos(px+1, py)
    local label = name:sub(1, pw-2)
    mwrite(label)

    -- Row 2: online dot + status
    mpad(px, py+1, pw, C.panelBg)
    local dot    = s.online and "\4" or "x"
    local dotcol = s.online and C.online or C.offline
    local statTxt = s.online and "Online" or "Offline"
    mfg(dotcol);   mbg(C.panelBg); mpos(px+1, py+1); mwrite(dot)
    mfg(dotcol);   mbg(C.panelBg); mpos(px+3, py+1); mwrite(statTxt:sub(1, pw-4))

    -- Row 3: requests
    mpad(px, py+2, pw, C.panelBg)
    mfg(C.dimFg);  mbg(C.panelBg); mpos(px+1, py+2); mwrite("Req")
    mfg(C.statFg); mbg(C.panelBg); mpos(px+5, py+2)
    mwrite(tostring(s.requests):sub(1, pw-6))

    -- Row 4: errors
    mpad(px, py+3, pw, C.panelBg)
    local ecol = s.errors > 0 and C.logErr or C.dimFg
    mfg(C.dimFg); mbg(C.panelBg); mpos(px+1, py+3); mwrite("Err")
    mfg(ecol);    mbg(C.panelBg); mpos(px+5, py+3)
    mwrite(tostring(s.errors):sub(1, pw-6))

    -- Row 5: last endpoint label
    mpad(px, py+4, pw, C.panelBg)
    mfg(C.dimFg); mbg(C.panelBg); mpos(px+1, py+4); mwrite("Last:")

    -- Row 6: endpoint text (colour by code)
    mpad(px, py+5, pw, C.panelBg)
    if s.lastEndpoint then
        local epcol = C.statFg
        if s.lastCode then
            epcol = s.lastCode >= 500 and C.logErr
                    or s.lastCode >= 400 and C.logWarn
                    or C.logOk
        end
        local ep = s.lastEndpoint:sub(1, pw-2)
        mfg(epcol); mbg(C.panelBg); mpos(px+1, py+5); mwrite(ep)
    end

    -- Row 7: code + bottom separator
    mpad(px, py+6, pw, C.sepBg)
    if s.lastCode then
        local ccol = s.lastCode >= 500 and C.logErr
                     or s.lastCode >= 400 and C.logWarn
                     or C.logOk
        mfg(ccol); mbg(C.sepBg); mpos(px+1, py+6)
        mwrite(tostring(s.lastCode))
    end

    -- Vertical separator on right edge (except last col)
    if col < L.cols - 1 then
        for ry = py, py+PANEL_H-1 do
            mbg(C.sepBg); mpos(px+pw, ry); mwrite(" ")
        end
    end
end

local LOG_TAGS = { info="INFO", ok=" OK ", warn="WARN", error="ERR!" }
local LOG_COLS = { info=C.logInfo, ok=C.logOk, warn=C.logWarn, error=C.logErr }

local function drawLog(L)
    if L.logH < 2 then return end

    -- Log header
    mpad(1, L.logY, _monW, C.headerBg)
    mfg(C.accent); mbg(C.headerBg); mpos(1, L.logY)
    local hdr = string.format(" Activity Log  (%d entries) ", #_logBuf)
    mwrite(hdr:sub(1, _monW))

    -- Entries: show most recent, bottom-aligned
    local visible = L.logH - 1
    local startIdx = math.max(1, #_logBuf - visible + 1)
    local row = L.logY + 1

    for i = startIdx, #_logBuf do
        local e = _logBuf[i]
        if not e or row > _monH then break end

        mpad(1, row, _monW, C.logBg)

        -- Timestamp
        local sec = math.floor((e.ts - _boot) / 1000)
        local ts  = string.format("%5ds", sec)
        mfg(C.logDim); mbg(C.logBg); mpos(1, row); mwrite(ts)

        -- Level badge [XXXX]
        local tag    = LOG_TAGS[e.level] or "INFO"
        local tagcol = LOG_COLS[e.level] or C.logInfo
        mfg(tagcol); mbg(C.logBg); mpos(7, row)
        mwrite("[" .. tag .. "]")

        -- Server name (9 chars)
        mfg(C.dimFg); mbg(C.logBg); mpos(14, row)
        mwrite(string.format("%-9s", (e.server or "?"):sub(1,9)))

        -- Message
        local msgX = 24
        local msgW = _monW - msgX
        if msgW > 0 then
            mfg(C.logFg); mbg(C.logBg); mpos(msgX, row)
            mwrite((e.message or ""):sub(1, msgW))
        end

        row = row + 1
    end
end

-- ─────────────────────────────────────────────────────────────
-- Public: redraw
-- ─────────────────────────────────────────────────────────────

function dash.redraw()
    -- Try to (re)acquire monitor every call in case it was connected late
    if not _mon then
        if not initMonitor() then return end
    end

    -- Wrap all drawing in pcall so a monitor disconnect doesn't crash everything
    local ok, err = pcall(function()
        _monW, _monH = _mon.getSize()
        mbg(C.bg)
        _mon.clear()

        local L = computeLayout()
        if not L then
            mfg(C.logWarn); mbg(C.bg)
            mpos(1,1); mwrite(" No servers registered yet.")
            return
        end

        drawHeader()
        for i = 1, L.n do drawPanel(i, L) end
        drawLog(L)
    end)

    if not ok then
        -- Monitor probably disconnected; reset so next call re-detects
        _mon = nil
    end
end

--- Call once at startup.
function dash.init()
    if initMonitor() then
        mbg(C.bg); _mon.clear()
        mfg(C.accent); mbg(C.bg); mpos(1,1)
        mwrite(" DorpOS Monitor — starting up...")
        print("[Dashboard] Monitor found: " .. _monW .. "x" .. _monH)
    else
        print("[Dashboard] No monitor found — will retry on each redraw.")
    end
end

return dash
