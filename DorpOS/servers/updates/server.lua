--[[  DorpOS :: servers/updates/server.lua
    Update Server — serves file manifests and delta file downloads.
]]
if package then
    package.path = "/?.lua;/?/init.lua;/shared/?.lua;/system/?.lua;/servers/?.lua;" .. (package.path or "")
else
    pcall(dofile, "/shared/shim.lua")
end
local Base = require("servers.shared.server_base")
local C    = require("shared.constants")
local sha  = require("system.crypto.sha256")
local server = Base.new(C.HOST_UPDATES, "Updates")

-- Root where the canonical OS files are stored on this server
local FILE_ROOT = "/phone_files"

local function readFile(path)
    local f = io.open(path, "r"); if not f then return nil end
    local c = f:read("*a"); f:close(); return c
end

local _manifest = nil
local function getManifest()
    if _manifest then return _manifest end
    local files = {}
    local function scan(root, prefix)
        local ok, list = pcall(fs.list, root); if not ok then return end
        for _, name in ipairs(list) do
            local full = fs.combine(root, name)
            local rel  = prefix == "" and name or (prefix .. "/" .. name)
            if fs.isDir(full) then scan(full, rel)
            else
                local content = readFile(full)
                if content then
                    table.insert(files, { path = "/" .. rel, hash = sha.hash(content), size = fs.getSize(full) })
                end
                sleep(0) -- Yield to prevent "Too long without yielding" crash
            end
        end
    end
    scan(FILE_ROOT, "")
    _manifest = { version = C.OS_VERSION, files = files }
    print("[updates] Manifest built: " .. #files .. " files, version " .. C.OS_VERSION)
    return _manifest
end

-- Get manifest (for delta comparison)
server.route("/updates/manifest", function(clientId, req)
    server.ok(clientId, req, getManifest())
end)

-- Download a specific file
server.route("/updates/file", function(clientId, req)
    local path = req.body and req.body.path
    if not path then return server.badRequest(clientId, req, "missing path") end

    local localPath = FILE_ROOT .. path
    local content   = readFile(localPath)
    if not content then
        return server.fail(clientId, req, 404, "File not found: " .. path)
    end

    server.ok(clientId, req, {
        path    = path,
        content = content,
        hash    = sha.hash(content),
        version = C.OS_VERSION,
    })
end)

-- Force manifest rebuild (admin)
server.route("/updates/rebuild", function(clientId, req)
    _manifest = nil
    local m = getManifest()
    server.ok(clientId, req, { files = #m.files, version = m.version })
end)

-- Pre-warm manifest cache on startup
getManifest()

server.run()
