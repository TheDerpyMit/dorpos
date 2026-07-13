--[[
    DorpOS :: phone/system/services/app_manager.lua
    ─────────────────────────────────────────────────
    Application lifecycle manager.

    Responsibilities:
        - Maintain a registry of installed apps (built-in + marketplace)
        - Launch apps in isolated environments with crash protection
        - Track the currently running app
        - Provide a clean API for the kernel to open/close apps

    App manifest format (returned by appManager.getInfo):
        {
            id      = "com.dorpos.calculator",
            name    = "Calculator",
            icon    = "#",         -- single char icon
            path    = "/apps/calculator/init.lua",
            builtin = true,
        }
]]

local appManager = {}

local C   = require("shared.constants")
local log = require("system.utils.logger")

-- ─────────────────────────────────────────────────────────────
-- Built-in app registry
-- ─────────────────────────────────────────────────────────────

local BUILTIN_APPS = {
    { id = C.APP_HOME,        name = "Home",        icon = "\143", path = "/apps/home/init.lua",        builtin = true },
    { id = C.APP_SETTINGS,    name = "Settings",    icon = "*",    path = "/apps/settings/init.lua",    builtin = true },
    { id = C.APP_CALCULATOR,  name = "Calc",        icon = "+",    path = "/apps/calculator/init.lua",  builtin = true },
    { id = C.APP_MESSAGES,    name = "Messages",    icon = "M",    path = "/apps/messages/init.lua",    builtin = true },
    { id = C.APP_NOTES,       name = "Notes",       icon = "=",    path = "/apps/notes/init.lua",       builtin = true },
    { id = C.APP_FILES,       name = "Files",       icon = "F",    path = "/apps/files/init.lua",       builtin = true },
    { id = C.APP_MARKETPLACE, name = "Market",      icon = "$",    path = "/apps/marketplace/init.lua", builtin = true },
    { id = C.APP_CLOCK,       name = "Clock",       icon = "o",    path = "/apps/clock/init.lua",       builtin = true },
    { id = C.APP_CALENDAR,    name = "Calendar",    icon = "C",    path = "/apps/calendar/init.lua",    builtin = true },
    { id = C.APP_ABOUT,       name = "About",       icon = "i",    path = "/apps/about/init.lua",       builtin = true },
    { id = C.APP_CLOUD,       name = "Cloud",       icon = "~",    path = "/apps/cloud/init.lua",       builtin = true },
}

-- Third-party apps installed via marketplace (loaded from storage)
local _thirdPartyApps = {}

-- Currently running app ID
local _currentAppId = nil

-- ─────────────────────────────────────────────────────────────
-- Registry
-- ─────────────────────────────────────────────────────────────

--- Return all installed apps (built-in + third-party).
---@return table list of app manifests
function appManager.getAll()
    local all = {}
    for _, app in ipairs(BUILTIN_APPS) do
        table.insert(all, app)
    end
    for _, app in ipairs(_thirdPartyApps) do
        table.insert(all, app)
    end
    return all
end

--- Return the manifest for a single app by ID. Returns nil if not found.
---@param id string
---@return table|nil
function appManager.getInfo(id)
    for _, app in ipairs(appManager.getAll()) do
        if app.id == id then return app end
    end
    return nil
end

--- Register a third-party app at runtime (installed from marketplace).
---@param manifest table
function appManager.register(manifest)
    -- Unregister old version if it exists
    for i, app in ipairs(_thirdPartyApps) do
        if app.id == manifest.id then
            table.remove(_thirdPartyApps, i)
            break
        end
    end
    table.insert(_thirdPartyApps, manifest)
    log.info("app_manager", "Registered app", { id = manifest.id })
end

--- Unregister a third-party app.
---@param id string
function appManager.unregister(id)
    for i, app in ipairs(_thirdPartyApps) do
        if app.id == id then
            table.remove(_thirdPartyApps, i)
            log.info("app_manager", "Unregistered app", { id = id })
            return true
        end
    end
    return false
end

-- ─────────────────────────────────────────────────────────────
-- Lifecycle
-- ─────────────────────────────────────────────────────────────

--- Launch an app by ID. Returns true on clean exit, false on crash.
--- The app runs synchronously in the current coroutine context
--- (the kernel handles the event loop; apps return when they close).
---@param id       string
---@param args     table?   Optional args passed to the app's init
---@param onClose  function? Called when the app exits (cleanly or not)
---@return boolean ok, string? errorMessage
function appManager.launch(id, args, onClose)
    local manifest = appManager.getInfo(id)
    if not manifest then
        log.error("app_manager", "Unknown app ID", { id = id })
        return false, "Unknown app: " .. id
    end

    if not fs.exists(manifest.path) then
        log.error("app_manager", "App file missing", { path = manifest.path })
        return false, "App not installed: " .. manifest.path
    end

    log.info("app_manager", "Launching", { id = id })
    local prevApp = _currentAppId
    _currentAppId = id

    -- Load and run in protected mode
    local fn, loadErr = loadfile(manifest.path)
    if not fn then
        _currentAppId = prevApp
        log.error("app_manager", "Load error", { id = id, err = loadErr })
        return false, "Load error: " .. tostring(loadErr)
    end

    -- Inject args into environment
    local env = setmetatable({ ARGS = args or {} }, { __index = _G })
    setfenv(fn, env)

    local ok, runErr = pcall(fn)
    _currentAppId = prevApp

    if not ok then
        log.error("app_manager", "Runtime crash", { id = id, err = tostring(runErr) })
        if onClose then onClose(false, runErr) end
        return false, tostring(runErr)
    end

    log.info("app_manager", "App closed cleanly", { id = id })
    if onClose then onClose(true) end
    return true
end

--- Return the ID of the currently running app (or nil).
---@return string|nil
function appManager.current()
    return _currentAppId
end

return appManager
