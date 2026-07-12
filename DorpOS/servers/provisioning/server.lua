--[[
    DorpOS :: servers/provisioning/server.lua
    ─────────────────────────────────────────
    Provisioning Server — acts as the "factory installer".

    Responsibilities:
      - Listen for new devices broadcasting /provision/hello
      - Send the OS file manifest (list of paths + hashes)
      - Serve individual file contents on request
      - Register newly installed device IDs

    Setup:
      1. Copy the entire DorpOS/phone/ directory to this server's filesystem
         (or configure FILE_ROOT to point to wherever the files live)
      2. Run this script on a ComputerCraft computer with a modem
      3. The server will call rednet.host(C.HOST_PROVISIONING, C.PROTOCOL_NAME)

    The manifest is built from the actual files in FILE_ROOT on first
    request and cached. Re-generate by deleting /data/manifest.dat.
]]

package.path = "/?.lua;/?/init.lua;" .. package.path

local C     = require("shared.constants")
local proto = require("shared.protocol")
local sha   = require("system.crypto.sha256")

-- Root directory containing the phone OS files to serve
local FILE_ROOT = "/phone_files"

-- ─────────────────────────────────────────────────────────────
-- Manifest builder
-- ─────────────────────────────────────────────────────────────

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function hashFile(path)
    local content = readFile(path)
    if not content then return nil end
    return sha.hash(content)
end

local function scanDir(root, prefix, out)
    out = out or {}
    prefix = prefix or ""
    local ok, list = pcall(fs.list, root)
    if not ok then return out end
    for _, name in ipairs(list) do
        local full    = fs.combine(root, name)
        local relPath = prefix == "" and name or (prefix .. "/" .. name)
        if fs.isDir(full) then
            scanDir(full, relPath, out)
        else
            local h = hashFile(full)
            if h then
                table.insert(out, { path = "/" .. relPath, hash = h, size = fs.getSize(full) })
            end
        end
    end
    return out
end

local _manifest = nil

local function getManifest()
    if _manifest then return _manifest end
    print("[prov] Building manifest from " .. FILE_ROOT)
    local files = scanDir(FILE_ROOT)
    _manifest = {
        version = C.OS_VERSION,
        files   = files,
    }
    print("[prov] Manifest built: " .. #files .. " files")
    return _manifest
end

-- ─────────────────────────────────────────────────────────────
-- Device registry
-- ─────────────────────────────────────────────────────────────

local function loadDevices()
    if not fs.exists("/data/devices.dat") then return {} end
    local f = io.open("/data/devices.dat", "r")
    if not f then return {} end
    local raw = f:read("*a")
    f:close()
    local ok, t = pcall(textutils.unserialise, raw)
    return (ok and type(t) == "table") and t or {}
end

local function saveDevices(devices)
    if not fs.exists("/data") then fs.makeDir("/data") end
    local f = io.open("/data/devices.dat", "w")
    if f then f:write(textutils.serialise(devices)); f:close() end
end

local devices = loadDevices()

-- ─────────────────────────────────────────────────────────────
-- Server start
-- ─────────────────────────────────────────────────────────────

proto.init()
proto.host(C.HOST_PROVISIONING)
print("[prov] Provisioning Server started")
print("[prov] Computer ID: " .. os.getComputerID())
print("[prov] Serving files from: " .. FILE_ROOT)

while true do
    local clientId, req = proto.receive()
    if not clientId then goto continue end

    local ep = req.endpoint

    -- ── /provision/hello — new device discovery ──────────────
    if ep == "/provision/hello" then
        local deviceId = req.body and req.body.deviceId
        print("[prov] New device: " .. tostring(deviceId))

        local manifest = getManifest()
        proto.respond(clientId, req, {
            version  = manifest.version,
            files    = manifest.files,
            serverId = os.getComputerID(),
        })

        -- Register device
        if deviceId then
            devices[tostring(deviceId)] = {
                deviceId    = deviceId,
                firstSeen   = os.epoch("utc"),
                version     = "0.0.0",
                status      = "provisioning",
            }
            saveDevices(devices)
        end

    -- ── /provision/file — file download ──────────────────────
    elseif ep == "/provision/file" then
        local reqPath = req.body and req.body.path
        if not reqPath then
            proto.respondBadRequest(clientId, req, "missing path")
            goto continue
        end

        -- Map client path to local file root
        local localPath = FILE_ROOT .. reqPath
        local content   = readFile(localPath)
        if not content then
            proto.respondError(clientId, req, 404, "File not found: " .. reqPath)
            goto continue
        end

        proto.respond(clientId, req, {
            path    = reqPath,
            content = content,
            hash    = sha.hash(content),
        })

    -- ── /provision/complete — device confirms install ─────────
    elseif ep == "/provision/complete" then
        local deviceId = req.body and req.body.deviceId
        if deviceId and devices[tostring(deviceId)] then
            devices[tostring(deviceId)].status  = "installed"
            devices[tostring(deviceId)].version = req.body.version or C.OS_VERSION
            devices[tostring(deviceId)].installedAt = os.epoch("utc")
            saveDevices(devices)
        end
        proto.respond(clientId, req, { ok = true })
        print("[prov] Device installed: " .. tostring(deviceId))

    -- ── /provision/devices — admin list ──────────────────────
    elseif ep == "/provision/devices" then
        local list = {}
        for _, d in pairs(devices) do table.insert(list, d) end
        proto.respond(clientId, req, { devices = list, count = #list })

    else
        proto.respondError(clientId, req, 404, "Unknown endpoint")
    end

    ::continue::
end
