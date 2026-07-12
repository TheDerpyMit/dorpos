--[[
    DorpOS :: phone/system/services/notification_manager.lua
    ──────────────────────────────────────────────────────────
    Notification subsystem.

    Provides:
        - Local notification queue (in-memory + persisted to cache)
        - Unread count
        - Priority levels
        - Toast display via animation engine
        - Do Not Disturb mode

    Usage:
        local notif = require("system.services.notification_manager")

        notif.push({
            title   = "Messages",
            body    = "Alice: hey!",
            app     = C.APP_MESSAGES,
            type    = "info",   -- "info"|"success"|"warning"|"error"
            priority = 1,       -- 0=silent, 1=normal, 2=priority
        })

        local count = notif.unreadCount()
        local all   = notif.getAll()
        notif.markRead(id)
        notif.clear()
]]

local notif = {}

local C       = require("shared.constants")
local Storage = require("system.storage.storage")
local log     = require("system.utils.logger")

-- ─────────────────────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────────────────────

local _notifications = {}   -- in-memory list
local _dnd           = false
local _idCounter     = 0

local store = Storage.open("notifications")

-- Load persisted notifications on startup
local function loadCache()
    local cached = store.get("list", {})
    if type(cached) == "table" then
        _notifications = cached
        -- Find max id
        for _, n in ipairs(_notifications) do
            if n.id and n.id > _idCounter then _idCounter = n.id end
        end
    end
end

local function saveCache()
    -- Keep only last 50 notifications
    local trimmed = {}
    local start = math.max(1, #_notifications - 49)
    for i = start, #_notifications do
        table.insert(trimmed, _notifications[i])
    end
    _notifications = trimmed
    store.set("list", _notifications)
    store.set("unread", notif.unreadCount())
    store.save()
end

loadCache()

-- ─────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────

--- Push a new notification.
---@param n table  { title, body, app, type, priority }
---@return number id  The assigned notification ID
function notif.push(n)
    _idCounter = _idCounter + 1
    local entry = {
        id        = _idCounter,
        title     = n.title    or "Notification",
        body      = n.body     or "",
        app       = n.app      or "",
        type      = n.type     or "info",
        priority  = n.priority or 1,
        read      = false,
        timestamp = os.epoch("utc"),
    }
    table.insert(_notifications, entry)
    saveCache()
    log.info("notif", "Pushed notification", { id = entry.id, title = entry.title })

    -- Queue a screen event so the kernel can show a banner
    if not _dnd or entry.priority >= 2 then
        os.queueEvent("dorpos_notification", entry)
    end

    return entry.id
end

--- Return all notifications (newest first).
---@return table
function notif.getAll()
    local copy = {}
    for i = #_notifications, 1, -1 do
        table.insert(copy, _notifications[i])
    end
    return copy
end

--- Return count of unread notifications.
---@return number
function notif.unreadCount()
    local count = 0
    for _, n in ipairs(_notifications) do
        if not n.read then count = count + 1 end
    end
    return count
end

--- Mark a notification as read by its ID.
---@param id number
function notif.markRead(id)
    for _, n in ipairs(_notifications) do
        if n.id == id then
            n.read = true
            saveCache()
            return
        end
    end
end

--- Mark all notifications as read.
function notif.markAllRead()
    for _, n in ipairs(_notifications) do n.read = true end
    saveCache()
end

--- Remove all notifications.
function notif.clear()
    _notifications = {}
    saveCache()
end

--- Enable or disable Do Not Disturb.
---@param enabled boolean
function notif.setDND(enabled)
    _dnd = enabled
    store.set("dnd", enabled)
    store.save()
    log.info("notif", "DND " .. (enabled and "on" or "off"))
end

--- Return whether DND is enabled.
---@return boolean
function notif.isDND()
    return _dnd
end

return notif
