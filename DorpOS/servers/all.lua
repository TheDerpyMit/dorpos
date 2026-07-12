--[[
    DorpOS :: servers/all.lua
    ──────────────────────────
    Runs all 8 backend daemons concurrently on a single computer.
    Ideal for local testing, development, and single-node servers.
]]

package.path = "/?.lua;/?/init.lua;/shared/?.lua;" .. package.path

local C = require("shared.constants")
local unpack = table.unpack or _G.unpack

-- Ensure secret exists
if not fs.exists("/data/secret.txt") then
    print("[All-in-One] Generating new HMAC secret key...")
    if not fs.exists("/data") then fs.makeDir("/data") end
    local f = io.open("/data/secret.txt", "w")
    if f then
        local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        local s = ""
        for _ = 1, 32 do
            local idx = math.random(1, #chars)
            s = s .. chars:sub(idx, idx)
        end
        f:write(s)
        f:close()
    end
end

-- Ensure phone files directory exists
if not fs.exists("/phone_files") then
    fs.makeDir("/phone_files")
    print("[All-in-One] Created empty /phone_files folder.")
    print("             Copy the '/phone' contents here for OTA/Installer to work.")
end

local daemons = {
    { path = "/servers/provisioning/server.lua", name = "Provisioning" },
    { path = "/servers/activation/server.lua",   name = "Activation" },
    { path = "/servers/accounts/server.lua",     name = "Accounts" },
    { path = "/servers/messages/server.lua",     name = "Messages" },
    { path = "/servers/notifications/server.lua", name = "Notifications" },
    { path = "/servers/marketplace/server.lua",   name = "Marketplace" },
    { path = "/servers/updates/server.lua",       name = "Updates" },
    { path = "/servers/cloud/server.lua",         name = "Cloud" },
}

local fns = {}
for _, d in ipairs(daemons) do
    table.insert(fns, function()
        local fn, err = loadfile(d.path)
        if not fn then
            print("[Error] Failed to load " .. d.name .. ": " .. tostring(err))
            return
        end
        local ok, runErr = pcall(fn)
        if not ok then
            print("[Error] " .. d.name .. " crashed: " .. tostring(runErr))
        end
    end)
end

print("[All-in-One] Starting all 8 servers...")
parallel.waitForAll(unpack(fns))
