--[[
    DorpOS :: servers/all.lua
    ──────────────────────────
    Runs all 8 backend daemons concurrently on a single computer.
    Drives the monitor dashboard (auto-detected; works even if connected after boot).
]]

if package then
    package.path = "/?.lua;/?/init.lua;/shared/?.lua;/system/?.lua;/servers/?.lua;" .. (package.path or "")
else
    pcall(dofile, "/shared/shim.lua")
end

local C      = require("shared.constants")
local unpack = table.unpack or _G.unpack

-- ─────────────────────────────────────────────────────────────
-- Ensure secret exists
-- ─────────────────────────────────────────────────────────────

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
        f:write(s); f:close()
    end
end

if not fs.exists("/phone_files") then
    fs.makeDir("/phone_files")
    print("[All-in-One] Created /phone_files — copy phone OS files here.")
end

-- ─────────────────────────────────────────────────────────────
-- Initialise monitor dashboard
-- ─────────────────────────────────────────────────────────────

local dash = nil
local dashOk, dashResult = pcall(require, "servers.shared.monitor_dashboard")
if dashOk and type(dashResult) == "table" then
    dash = dashResult
    dash.init()
else
    print("[All-in-One] Dashboard load error: " .. tostring(dashResult))
end

-- ─────────────────────────────────────────────────────────────
-- Server daemons
-- ─────────────────────────────────────────────────────────────

local daemons = {
    { path = "/servers/provisioning/server.lua",  name = "Provisioning"  },
    { path = "/servers/activation/server.lua",    name = "Activation"    },
    { path = "/servers/accounts/server.lua",      name = "Accounts"      },
    { path = "/servers/messages/server.lua",      name = "Messages"      },
    { path = "/servers/notifications/server.lua", name = "Notifications" },
    { path = "/servers/marketplace/server.lua",   name = "Marketplace"   },
    { path = "/servers/updates/server.lua",       name = "Updates"       },
    { path = "/servers/cloud/server.lua",         name = "Cloud"         },
}

local fns = {}

-- ─────────────────────────────────────────────────────────────
-- Dashboard ticker — redraws every second, handles monitor events
-- ─────────────────────────────────────────────────────────────

if dash then
    table.insert(fns, function()
        while true do
            -- Sleep 1s but wake early on monitor_resize
            local timer = os.startTimer(1)
            while true do
                local ev = { os.pullEvent() }
                if ev[1] == "timer" and ev[2] == timer then break end
                if ev[1] == "monitor_resize" or ev[1] == "peripheral" then
                    -- Monitor connected/resized — redraw immediately
                    break
                end
            end
            dash.redraw()
        end
    end)
end

-- ─────────────────────────────────────────────────────────────
-- Launch each server daemon
-- ─────────────────────────────────────────────────────────────

for _, d in ipairs(daemons) do
    local dname = d.name
    local dpath = d.path
    table.insert(fns, function()
        local fn, err = loadfile(dpath)
        if not fn then
            local msg = "Failed to load " .. dname .. ": " .. tostring(err)
            print("[Error] " .. msg)
            if dash then dash.log(dname, "error", msg); dash.redraw() end
            return
        end
        local ok2, runErr = pcall(fn)
        if not ok2 then
            local msg = dname .. " crashed: " .. tostring(runErr)
            print("[Error] " .. msg)
            if dash then
                dash.setOffline(dname)
                dash.redraw()
            end
        end
    end)
end

print("[All-in-One] Starting all 8 servers...")
if dash then
    dash.log("System", "info", "All-in-One server starting 8 daemons...")
    dash.redraw()
end

parallel.waitForAll(unpack(fns))
