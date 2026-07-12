--[[
    DorpOS :: phone/system/theme/theme.lua
    ───────────────────────────────────────
    Theme engine. Maintains the active theme and provides token lookups.

    All UI code uses theme tokens, never raw colour constants, so that
    switching theme instantly affects the entire OS.

    Usage:
        local Theme = require("system.theme.theme")
        Theme.load("dark")   -- or "light" / "amoled"

        local t = Theme.get()
        term.setBackgroundColor(t.bg)
        term.setTextColor(t.text)

    Persisting the chosen theme:
        Theme.set("light")   -- sets + saves to config
]]

local Theme = {}

local Storage = require("system.storage.storage")
local C       = require("shared.constants")

-- Supported built-in themes (lazy-loaded)
local THEMES = {
    dark   = "system.theme.themes.dark",
    light  = "system.theme.themes.light",
    amoled = "system.theme.themes.amoled",
}

-- Loaded theme table cache
local _loaded = {}

-- Currently active theme table
local _current = nil
local _currentId = nil

-- ─────────────────────────────────────────────────────────────
-- Internals
-- ─────────────────────────────────────────────────────────────

local function loadTheme(id)
    if _loaded[id] then return _loaded[id] end
    local path = THEMES[id]
    if not path then return nil end
    local ok, t = pcall(require, path)
    if not ok or type(t) ~= "table" then return nil end
    _loaded[id] = t
    return t
end

-- ─────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────

--- Load a theme by ID without persisting it. Falls back to dark.
---@param id string  "dark" | "light" | "amoled"
function Theme.load(id)
    local t = loadTheme(id) or loadTheme("dark")
    _current   = t
    _currentId = t and t.id or "dark"
end

--- Switch to a theme and persist the choice to config storage.
---@param id string
function Theme.set(id)
    Theme.load(id)
    local store = Storage.open("theme")
    store.set("id", _currentId)
    store.save()
end

--- Return the currently active theme token table.
---@return table theme
function Theme.get()
    if not _current then
        -- Auto-load from saved config on first call
        local store = Storage.open("theme")
        local id    = store.get("id", "dark")
        Theme.load(id)
    end
    return _current
end

--- Return the ID of the currently active theme.
---@return string
function Theme.currentId()
    if not _currentId then Theme.get() end
    return _currentId
end

--- Return a list of available theme IDs and names.
---@return table list of { id, name }
function Theme.list()
    local out = {}
    for id, path in pairs(THEMES) do
        local t = loadTheme(id)
        table.insert(out, { id = id, name = t and t.name or id })
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

--- Apply the current theme to the given terminal object (or term if nil).
---@param target table?  Terminal object (default: term)
function Theme.apply(target)
    local t = Theme.get()
    local tgt = target or term
    tgt.setBackgroundColor(t.bg)
    tgt.setTextColor(t.text)
    tgt.clear()
end

return Theme
