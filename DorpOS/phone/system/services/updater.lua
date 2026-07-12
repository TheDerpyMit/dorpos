--[[
    DorpOS :: phone/system/services/updater.lua
    ────────────────────────────────────────────
    Over-the-air update service.

    Runs as a background check called by the kernel.
    Only downloads files that have changed (delta update via hash comparison).

    Flow:
        1. Request manifest from Update Server
        2. Compare each file's hash to local /data/config/install.json
        3. Download only changed files
        4. Verify each downloaded file (SHA-256)
        5. Replace files atomically
        6. Update install.json
        7. Queue a "dorpos_update_ready" event for the kernel to notify user
]]

local updater = {}

local C       = require("shared.constants")
local net     = require("system.network.network")
local sha     = require("system.crypto.sha256")
local Storage = require("system.storage.storage")
local log     = require("system.utils.logger")

-- ─────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────

local function fileHash(path)
    if not fs.exists(path) then return nil end
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return sha.hash(content)
end

local function loadInstallConfig()
    if not fs.exists(C.FILE_INSTALL_CONFIG) then return {} end
    local f = io.open(C.FILE_INSTALL_CONFIG, "r")
    if not f then return {} end
    local raw = f:read("*a")
    f:close()
    local ok, cfg = pcall(textutils.unserialise, raw)
    return (ok and type(cfg) == "table") and cfg or {}
end

local function saveInstallConfig(cfg)
    local f = io.open(C.FILE_INSTALL_CONFIG, "w")
    if f then
        f:write(textutils.serialise(cfg))
        f:close()
    end
end

-- ─────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────

--- Check for updates. Returns { hasUpdate, count, version } or nil on error.
---@return table|nil result
function updater.check()
    log.info("updater", "Checking for updates")

    local ok, resp = net.post(C.HOST_UPDATES, "/updates/manifest", {
        currentVersion = C.OS_VERSION,
        deviceId       = os.getComputerID(),
    })

    if not ok then
        log.warn("updater", "Update check failed", { msg = resp.message })
        return nil
    end

    local manifest = resp.body
    if not manifest.files then return nil end

    -- Compare each file
    local toUpdate = {}
    for _, entry in ipairs(manifest.files) do
        local localHash = fileHash(entry.path)
        if localHash ~= entry.hash then
            table.insert(toUpdate, entry)
        end
    end

    return {
        hasUpdate   = #toUpdate > 0,
        count       = #toUpdate,
        version     = manifest.version,
        toUpdate    = toUpdate,
        serverId    = resp.body.serverId,
    }
end

--- Download and apply all pending updates. Returns true on success.
---@param result table  From updater.check()
---@return boolean ok, string? err
function updater.apply(result)
    if not result or not result.hasUpdate then return true end

    log.info("updater", "Applying " .. result.count .. " file updates")

    for i, entry in ipairs(result.toUpdate) do
        log.info("updater", string.format("Downloading [%d/%d] %s", i, result.count, entry.path))

        local ok, resp = net.post(C.HOST_UPDATES, "/updates/file", {
            path = entry.path,
            hash = entry.hash,
        })

        if not ok or not resp.body.content then
            log.error("updater", "Failed to download", { path = entry.path })
            return false, "Failed to download: " .. entry.path
        end

        local content = resp.body.content

        -- Verify hash
        local gotHash = sha.hash(content)
        if not sha.equal(gotHash, entry.hash) then
            log.error("updater", "Hash mismatch", { path = entry.path })
            return false, "Hash mismatch: " .. entry.path
        end

        -- Write atomically
        local tmpPath = entry.path .. ".tmp"
        local f = io.open(tmpPath, "w")
        if not f then
            return false, "Cannot write: " .. tmpPath
        end
        f:write(content)
        f:close()

        if fs.exists(entry.path) then fs.delete(entry.path) end
        fs.move(tmpPath, entry.path)

        log.info("updater", "Updated: " .. entry.path)
    end

    -- Update install config
    local cfg = loadInstallConfig()
    cfg.version     = result.version
    cfg.lastUpdated = os.epoch("utc")
    saveInstallConfig(cfg)

    log.info("updater", "Update complete", { version = result.version })
    os.queueEvent("dorpos_update_ready", result.version)
    return true
end

--- Full check-and-apply cycle. Returns true if updates were applied.
---@return boolean
function updater.run()
    local result = updater.check()
    if result and result.hasUpdate then
        local ok, err = updater.apply(result)
        if not ok then
            log.error("updater", "Update failed", { err = err })
            return false
        end
        return true
    end
    return false
end

return updater
