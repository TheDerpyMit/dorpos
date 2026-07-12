--[[
    DorpOS :: shared/constants.lua
    ─────────────────────────────
    Central constant registry for the entire DorpOS ecosystem.

    All hostnames, protocol versions, timing values, filesystem paths,
    and feature flags are defined here so that no magic numbers appear
    anywhere else in the codebase.

    Server discovery uses rednet.host() / rednet.lookup() — no fixed
    computer IDs are needed. Each server calls:
        rednet.host(C.HOST_PROVISIONING, C.PROTOCOL_NAME)
    and phones find it with:
        local id = rednet.lookup(C.PROTOCOL_NAME, C.HOST_PROVISIONING)

    Usage:
        local C = require("shared.constants")
        rednet.open(C.MODEM_SIDE)
]]

local Constants = {}

-- ─────────────────────────────────────────────────────────────
-- OS Identity
-- ─────────────────────────────────────────────────────────────

Constants.OS_NAME           = "DorpOS"
Constants.OS_VERSION        = "1.0.0"
Constants.PROTOCOL_NAME     = "dorpos"
Constants.PROTOCOL_VERSION  = 1

-- ─────────────────────────────────────────────────────────────
-- Hardware
-- ─────────────────────────────────────────────────────────────

--- Advanced Pocket Computers have a built-in ender modem on "back".
Constants.MODEM_SIDE        = "back"

-- ─────────────────────────────────────────────────────────────
-- Server Hostnames
-- Each backend server calls rednet.host(<hostname>, PROTOCOL_NAME).
-- Phones discover them via rednet.lookup(PROTOCOL_NAME, <hostname>).
-- This means no fixed computer IDs are required — servers can run
-- on any computer in the world as long as rednet can reach them.
-- ─────────────────────────────────────────────────────────────

Constants.HOST_PROVISIONING     = "dorpos.provisioning"
Constants.HOST_ACTIVATION       = "dorpos.activation"
Constants.HOST_ACCOUNTS         = "dorpos.accounts"
Constants.HOST_MESSAGES         = "dorpos.messages"
Constants.HOST_NOTIFICATIONS    = "dorpos.notifications"
Constants.HOST_MARKETPLACE      = "dorpos.marketplace"
Constants.HOST_UPDATES          = "dorpos.updates"
Constants.HOST_CLOUD            = "dorpos.cloud"

-- ─────────────────────────────────────────────────────────────
-- Networking Timings (seconds)
-- ─────────────────────────────────────────────────────────────

Constants.NET_TIMEOUT               = 10
Constants.NET_RETRY_DELAY           = 2
Constants.NET_MAX_RETRIES           = 3
Constants.NET_LOOKUP_TIMEOUT        = 5     -- rednet.lookup timeout

Constants.UPDATE_POLL_INTERVAL      = 300   -- 5 minutes
Constants.NOTIF_POLL_INTERVAL       = 30    -- 30 seconds

-- ─────────────────────────────────────────────────────────────
-- Filesystem Paths (relative to phone root)
-- ─────────────────────────────────────────────────────────────

Constants.PATH_ROOT             = "/"
Constants.PATH_SYSTEM           = "/system"
Constants.PATH_APPS             = "/apps"
Constants.PATH_DATA             = "/data"
Constants.PATH_CONFIG           = "/data/config"
Constants.PATH_CACHE            = "/data/cache"
Constants.PATH_USER             = "/data/user"
Constants.PATH_LOGS             = "/data/logs"
Constants.PATH_DOWNLOADS        = "/data/downloads"
Constants.PATH_ASSETS           = "/assets"

Constants.FILE_INSTALL_CONFIG   = "/data/config/install.json"
Constants.FILE_USER_CONFIG      = "/data/config/user.json"
Constants.FILE_THEME_CONFIG     = "/data/config/theme.json"
Constants.FILE_SESSION          = "/data/config/session.json"
Constants.FILE_PIN              = "/data/config/pin.json"
Constants.FILE_NOTIF_CACHE      = "/data/cache/notifications.json"
Constants.FILE_MSG_CACHE        = "/data/cache/messages.json"
Constants.FILE_MARKET_CACHE     = "/data/cache/marketplace.json"
Constants.FILE_CONTACTS_CACHE   = "/data/cache/contacts.json"

-- ─────────────────────────────────────────────────────────────
-- UI / Display
-- ─────────────────────────────────────────────────────────────

--- Advanced Pocket Computer terminal size (characters).
Constants.SCREEN_WIDTH          = 26
Constants.SCREEN_HEIGHT         = 20

Constants.STATUS_BAR_HEIGHT     = 1
Constants.DOCK_HEIGHT           = 1
Constants.CONTENT_HEIGHT        = Constants.SCREEN_HEIGHT
                                  - Constants.STATUS_BAR_HEIGHT
                                  - Constants.DOCK_HEIGHT

Constants.ANIM_FPS              = 20
Constants.ANIM_TRANSITION_TIME  = 0.15
Constants.TOAST_DURATION        = 3

-- ─────────────────────────────────────────────────────────────
-- Security
-- ─────────────────────────────────────────────────────────────

Constants.PIN_MAX_ATTEMPTS      = 5
Constants.PIN_LOCKOUT_DURATION  = 30   -- seconds
Constants.SESSION_TTL           = 86400  -- 24 hours in seconds

-- ─────────────────────────────────────────────────────────────
-- Marketplace
-- People post listings with what they're selling and what they
-- want in return (text description, like Facebook Marketplace).
-- The server stores and validates all transaction state.
-- ─────────────────────────────────────────────────────────────

Constants.MARKET_TITLE_MAX_LEN  = 48
Constants.MARKET_DESC_MAX_LEN   = 256
Constants.MARKET_PRICE_MAX_LEN  = 64   -- "2 diamonds and a stack of wood"
Constants.MARKET_ITEMS_PER_PAGE = 8

--- Listing status values stored server-side.
Constants.MARKET_STATUS_ACTIVE      = "active"
Constants.MARKET_STATUS_SOLD        = "sold"
Constants.MARKET_STATUS_REMOVED     = "removed"

-- ─────────────────────────────────────────────────────────────
-- Logging
-- ─────────────────────────────────────────────────────────────

Constants.LOG_DEBUG     = 1
Constants.LOG_INFO      = 2
Constants.LOG_WARN      = 3
Constants.LOG_ERROR     = 4
Constants.LOG_FATAL     = 5
Constants.LOG_MIN_LEVEL = Constants.LOG_DEBUG
Constants.LOG_MAX_SIZE  = 50000  -- ~50 KB before rotation

-- ─────────────────────────────────────────────────────────────
-- App Registry
-- ─────────────────────────────────────────────────────────────

Constants.APP_HOME          = "com.dorpos.home"
Constants.APP_LOCKSCREEN    = "com.dorpos.lockscreen"
Constants.APP_SETTINGS      = "com.dorpos.settings"
Constants.APP_CALCULATOR    = "com.dorpos.calculator"
Constants.APP_MESSAGES      = "com.dorpos.messages"
Constants.APP_CONTACTS      = "com.dorpos.contacts"
Constants.APP_NOTES         = "com.dorpos.notes"
Constants.APP_FILES         = "com.dorpos.files"
Constants.APP_MARKETPLACE   = "com.dorpos.marketplace"
Constants.APP_STORE         = "com.dorpos.store"
Constants.APP_CLOCK         = "com.dorpos.clock"
Constants.APP_CALENDAR      = "com.dorpos.calendar"
Constants.APP_ABOUT         = "com.dorpos.about"
Constants.APP_CLOUD         = "com.dorpos.cloud"
Constants.APP_SETUP         = "com.dorpos.setup"

return Constants
