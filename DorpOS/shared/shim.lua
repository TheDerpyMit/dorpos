--[[
    DorpOS :: shared/shim.lua
    ──────────────────────────
    Polyfill shim for older ComputerCraft / CraftOS versions that lack
    the standard Lua 'package' and 'require' module loader APIs.
]]

if not package then
    package = {
        path = "/?.lua;/?/init.lua;/shared/?.lua;/system/?.lua;/servers/?.lua;",
        loaded = {}
    }
    
    function _G.require(modname)
        if package.loaded[modname] then
            return package.loaded[modname]
        end
        
        -- Try matching paths based on package.path config
        local pathName = modname:gsub("%.", "/")
        local searchPaths = {
            pathName,
            "shared/" .. pathName,
            "system/" .. pathName,
            "servers/" .. pathName,
            "phone/" .. pathName
        }

        for _, p in ipairs(searchPaths) do
            local filePaths = {
                "/" .. p .. ".lua",
                "/" .. p .. "/init.lua"
            }
            for _, fp in ipairs(filePaths) do
                if fs.exists(fp) then
                    local fn, err = loadfile(fp)
                    if not fn then
                        error("Failed to load module '" .. modname .. "': " .. tostring(err), 2)
                    end
                    -- Run in a safe environment inheriting globals
                    local env = setmetatable({}, { __index = _G })
                    setfenv(fn, env)
                    local result = fn()
                    package.loaded[modname] = result or env
                    return package.loaded[modname]
                end
            end
        end
        
        error("Module '" .. modname .. "' not found.", 2)
    end
else
    -- If package exists, check if it's already modified to avoid infinite prepends
    if not package.path or not package.path:find("/shared/?.lua", 1, true) then
        -- If package.path is nil, we must explicitly include the default ROM search paths
        local defaultPaths = "?.lua;?/init.lua;/rom/modules/main/?.lua;/rom/modules/main/?/init.lua"
        local existing = package.path or defaultPaths
        package.path = "/?.lua;/?/init.lua;/shared/?.lua;/system/?.lua;/servers/?.lua;" .. existing
    end
end
