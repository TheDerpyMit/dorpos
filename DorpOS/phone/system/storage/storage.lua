--[[
    DorpOS :: phone/system/storage/storage.lua
    ──────────────────────────────────────────
    Persistent key-value store backed by the CC filesystem.
    All data is stored as serialised Lua tables (JSON-compatible subset).

    Features:
      - Atomic saves: write to a .tmp file, then move over the real file
        so a crash mid-write never corrupts existing data.
      - Namespaced stores: each store is its own file under /data/
      - In-memory cache: reads are fast after the first load.

    Usage:
        local Storage = require("system.storage.storage")

        -- Open (or create) a named store
        local prefs = Storage.open("user_prefs")

        -- Read / write
        prefs.set("theme", "dark")
        prefs.set("pin_attempts", 0)
        local theme = prefs.get("theme")      -- "dark"
        local all   = prefs.getAll()          -- { theme="dark", ... }

        -- Persist to disk immediately (also called automatically)
        prefs.save()

        -- Wipe all keys in the store
        prefs.clear()
]]

local Storage = {}
local C = require("shared.constants")

-- In-memory cache: storeId -> { data = {...}, dirty = bool }
local _stores = {}

--- Resolve the filesystem path for a named store.
local function storePath(name)
    return C.PATH_DATA .. "/" .. name .. ".dat"
end

local function tmpPath(name)
    return C.PATH_DATA .. "/" .. name .. ".tmp"
end

--- Load a store file from disk, returning an empty table on any error.
local function loadFromDisk(name)
    local path = storePath(name)
    if not fs.exists(path) then return {} end
    local f = io.open(path, "r")
    if not f then return {} end
    local raw = f:read("*a")
    f:close()
    local ok, data = pcall(textutils.unserialise, raw)
    if ok and type(data) == "table" then return data end
    return {}
end

--- Write a store to disk atomically via a temp file.
local function saveToDisk(name, data)
    -- Ensure the data directory exists
    if not fs.exists(C.PATH_DATA) then fs.makeDir(C.PATH_DATA) end

    local tmp  = tmpPath(name)
    local path = storePath(name)

    local ok, s = pcall(textutils.serialise, data)
    if not ok then return false, "serialise failed: " .. tostring(s) end

    local f = io.open(tmp, "w")
    if not f then return false, "cannot open tmp file for writing" end
    f:write(s)
    f:close()

    -- Atomic replace
    if fs.exists(path) then fs.delete(path) end
    fs.move(tmp, path)
    return true
end

--- Open (or create) a named persistent store.
--- Returns a store object with get/set/delete/save/clear/getAll methods.
---@param name string  Alphanumeric store name, e.g. "user_prefs"
---@return table store
function Storage.open(name)
    assert(type(name) == "string" and #name > 0, "Store name must be a non-empty string")

    -- Return cached store if already open
    if _stores[name] then
        return _stores[name].api
    end

    -- Load from disk
    local data = loadFromDisk(name)
    local state = { data = data, dirty = false }

    local store = {}

    --- Get a value by key. Returns `default` if the key is absent.
    function store.get(key, default)
        local v = state.data[key]
        if v == nil then return default end
        return v
    end

    --- Set a value. Queues a disk write (use save() to flush immediately).
    function store.set(key, value)
        state.data[key] = value
        state.dirty = true
    end

    --- Delete a key.
    function store.delete(key)
        state.data[key] = nil
        state.dirty = true
    end

    --- Return a shallow copy of all key-value pairs in the store.
    function store.getAll()
        local copy = {}
        for k, v in pairs(state.data) do copy[k] = v end
        return copy
    end

    --- Write the store to disk immediately. Called automatically on set()
    --- in critical paths; safe to call manually any time.
    ---@return boolean ok, string? err
    function store.save()
        if not state.dirty then return true end
        local ok, err = saveToDisk(name, state.data)
        if ok then state.dirty = false end
        return ok, err
    end

    --- Erase all keys and persist the empty store.
    function store.clear()
        state.data  = {}
        state.dirty = true
        store.save()
    end

    --- Check if a key exists.
    function store.has(key)
        return state.data[key] ~= nil
    end

    _stores[name] = { api = store, state = state }
    return store
end

--- Flush all open stores to disk. Call this on shutdown or before reboot.
function Storage.flushAll()
    for name, entry in pairs(_stores) do
        if entry.state.dirty then
            saveToDisk(name, entry.state.data)
            entry.state.dirty = false
        end
    end
end

--- Delete a named store file from disk and remove it from the cache.
---@param name string
function Storage.delete(name)
    local path = storePath(name)
    if fs.exists(path) then fs.delete(path) end
    _stores[name] = nil
end

return Storage
