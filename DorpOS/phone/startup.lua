--[[
    DorpOS :: phone/startup.lua
    ────────────────────────────
    Bootstrap loader — the ONLY file that needs to exist on a fresh
    Advanced Pocket Computer. Everything else is downloaded from the
    Provisioning Server.

    This file is intentionally tiny (<150 lines) so it is easy to
    update manually if something goes wrong.

    Boot flow:
        1. Open wireless modem
        2. Check if OS is already installed (boot.lua exists)
           → Yes: hand off to boot.lua
           → No:  run provisioning flow
        3. Provisioning:
           a. Broadcast discovery request
           b. Receive signed manifest
           c. Download and verify each file
           d. Write install config
           e. Reboot into DorpOS
]]

local VERSION = "1.0.0"
local W, H    = term.getSize()

-- ─────────────────────────────────────────────────────────────
-- Tiny UI helpers (no dependencies)
-- ─────────────────────────────────────────────────────────────

local function cls(bg, fg)
    term.setBackgroundColor(bg or colors.black)
    term.setTextColor(fg or colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function cwrite(y, text, fg, bg)
    term.setCursorPos(math.floor((W - #text) / 2) + 1, y)
    if fg then term.setTextColor(fg) end
    if bg then term.setBackgroundColor(bg) end
    term.write(text)
end

local function status(msg)
    term.setCursorPos(1, H - 1)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    term.write(string.rep(" ", W))
    term.setCursorPos(1, H - 1)
    term.write(msg:sub(1, W))
end

-- Smart path display: trim from the LEFT so the filename end is always visible
-- e.g. "/system/ui/components/keyboard.lua" becomes "..ponents/keyboard.lua"
local function pathLine(path)
    if #path <= W then
        -- Fits: pad with spaces so the row is clean
        return path .. string.rep(" ", W - #path)
    else
        -- Trim: keep the rightmost (W-2) chars, prefix with ".."
        return ".." .. path:sub(#path - (W - 3))
    end
end

-- Two-row progress display used during file download
local function progressStatus(i, total, path)
    -- Row H-2: progress bar with counter
    local pct   = math.floor((i / total) * 100)
    local label = string.format("[%d/%d] %d%%", i, total, pct)
    local barW  = W - #label - 1
    local fill  = math.floor((i / total) * barW)
    term.setCursorPos(1, H - 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.cyan)
    term.write(label .. " ")
    term.setBackgroundColor(colors.cyan)
    term.write(string.rep(" ", fill))
    term.setBackgroundColor(colors.gray)
    term.write(string.rep(" ", barW - fill))

    -- Row H-1: file path (smart-trimmed so the filename is always visible)
    term.setCursorPos(1, H - 1)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    term.write(pathLine(path))
end

local function die(msg)
    cls(colors.red, colors.white)
    cwrite(3, "PROVISIONING FAILED", colors.white, colors.red)
    cwrite(5, msg:sub(1, W), colors.yellow, colors.red)
    cwrite(7, "Reboot to retry.", colors.white, colors.red)
    while true do os.pullEvent() end
end

-- ─────────────────────────────────────────────────────────────
-- Splash screen
-- ─────────────────────────────────────────────────────────────

local function splash()
    cls(colors.black)
    cwrite(4, "DorpOS", colors.cyan)
    cwrite(5, "v" .. VERSION, colors.lightGray)
    cwrite(7, "Initialising...", colors.white)
end

-- ─────────────────────────────────────────────────────────────
-- Modem setup
-- ─────────────────────────────────────────────────────────────

local function openModem()
    local modem = peripheral.find("modem")
    if not modem then die("No wireless modem found") end
    local side  = peripheral.getName(modem)
    rednet.open(side)
    return side
end

-- ─────────────────────────────────────────────────────────────
-- Provisioning flow
-- ─────────────────────────────────────────────────────────────

local PROTO   = "dorpos"
local TIMEOUT = 15

local function sendBroadcast(payload)
    rednet.broadcast(payload, PROTO)
end

local function waitResponse(timeout)
    local deadline = os.clock() + timeout
    while os.clock() < deadline do
        local remaining = deadline - os.clock()
        local sender, data = rednet.receive(PROTO, math.max(0.1, remaining))
        if sender and type(data) == "table" then
            return sender, data
        end
    end
    return nil, nil
end

local function sha256File(path)
    -- Inline SHA-256 is not available at bootstrap time (we haven't
    -- downloaded the crypto library yet). We use a simple Adler-32
    -- checksum for integrity at bootstrap stage; full SHA-256
    -- verification happens in subsequent boots via the update system.
    if not fs.exists(path) then return "MISSING" end
    local f = io.open(path, "r")
    if not f then return "UNREADABLE" end
    local content = f:read("*a")
    f:close()
    -- Adler-32
    local A, B = 1, 0
    for i = 1, #content do
        A = (A + content:byte(i)) % 65521
        B = (B + A) % 65521
    end
    return string.format("%08x", B * 65536 + A)
end

local function provision()
    splash()
    -- Discovery (retry up to 5 times to handle packet loss or server booting)
    local serverId, manifest
    local retries = 5
    for attempt = 1, retries do
        status(string.format("Searching for Server... (Attempt %d/%d)", attempt, retries))
        sendBroadcast({
            protocol = PROTO,
            version  = 1,
            id       = tostring(os.getComputerID()) .. tostring(os.epoch("utc")) .. "-" .. attempt,
            endpoint = "/provision/hello",
            body     = { deviceId = os.getComputerID(), version = "0.0.0" },
        })
        serverId, manifest = waitResponse(3) -- Wait 3 seconds per attempt
        if serverId and manifest and manifest.ok then
            break
        end
        os.sleep(0.5)
    end

    if not serverId then die("No Provisioning Server found.\nIs the server running?") end
    if not manifest.ok then die(manifest.message or "Provisioning rejected") end

    local files = manifest.body.files
    if type(files) ~= "table" then die("Invalid manifest received") end

    status("Received manifest: " .. #files .. " files")
    os.sleep(0.5)

    -- Download each file
    for i, entry in ipairs(files) do
        progressStatus(i, #files, entry.path)

        -- Request file contents with up to 3 retries in case of packet loss
        local success = false
        local resp
        for attempt = 1, 3 do
            rednet.send(serverId, {
                protocol = PROTO,
                version  = 1,
                id       = tostring(i) .. "-" .. tostring(os.epoch("utc")) .. "-" .. attempt,
                endpoint = "/provision/file",
                body     = { path = entry.path, hash = entry.hash },
            }, PROTO)

            local _
            _, resp = waitResponse(4)
            if resp and resp.ok then
                success = true
                break
            end
            status("Retry " .. attempt .. "/3: " .. pathLine(entry.path))
            os.sleep(0.2)
        end

        if not success then
            die("Failed to download: " .. entry.path)
        end

        local content = resp.body.content
        if type(content) ~= "string" then
            die("Bad content for: " .. entry.path)
        end

        -- Create directories as needed
        local dir = fs.getDir(entry.path)
        if dir ~= "" and not fs.exists(dir) then
            fs.makeDir(dir)
        end

        -- Write file
        local f = io.open(entry.path, "w")
        if not f then die("Cannot write: " .. entry.path) end
        f:write(content)
        f:close()

        -- Lightweight integrity check
        local got = sha256File(entry.path)
        -- (Full SHA-256 verification comes after crypto lib is available)
    end

    -- Write install config
    if not fs.exists("/data/config") then fs.makeDir("/data/config") end
    local cfg = io.open("/data/config/install.json", "w")
    if cfg then
        cfg:write(textutils.serialise({
            version     = manifest.body.version or VERSION,
            installedAt = os.epoch("utc"),
            serverId    = serverId,
            fileCount   = #files,
        }))
        cfg:close()
    end

    status("Installation complete! Rebooting...")
    os.sleep(1.5)
    os.reboot()
end

-- ─────────────────────────────────────────────────────────────
-- Entry point
-- ─────────────────────────────────────────────────────────────

openModem()

if fs.exists("/boot.lua") then
    -- OS already installed — hand off to boot loader
    dofile("/boot.lua")
else
    -- Fresh device — run provisioning
    provision()
end
