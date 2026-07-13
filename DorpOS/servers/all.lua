--[[
    DorpOS :: servers/all.lua
    ──────────────────────────
    Runs all 8 backend daemons concurrently on a single computer.
    Also drives the monitor dashboard if a monitor is attached.

    Dashboard: attach a 3x3 Advanced Monitor to the server computer.
    It will automatically show per-server panels with request counts,
    error counts, last endpoint handled, and a colour-coded activity log.
]]

if package then
    package.path = "/?.lua;/?/init.lua;/shared/?.lua;/system/?.lua;/servers/?.lua;/" .. (package.path or "")
else
    pcall(dofile, "/shared/shim.lua")
end

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

-- ─────────────────────────────────────────────────────────────
-- Initialise monitor dashboard (no-op if no monitor attached)
-- ─────────────────────────────────────────────────────────────

local dash = nil
local ok, d = pcall(require, "servers.shared.monitor_dashboard")
if ok then
    dash = d
    dash.init()
    print("[All-in-One] Monitor dashboard initialised.")
else
    print("[All-in-One] No monitor dashboard (no monitor attached?).")
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
-- Uptime ticker: redraws the dashboard once per second so the
-- uptime counter and any buffered log lines stay current.
-- ─────────────────────────────────────────────────────────────

if dash then
    table.insert(fns, function()
        while true do
            os.sleep(1)
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
                dash.log(dname, "error", msg)
                dash.redraw()
            end
        end
    end)
end

print("[All-in-One] Starting all 8 servers...")
if dash then
    dash.log("All-in-One", "info", "Starting all 8 servers via parallel.waitForAll...")
    dash.redraw()
end

parallel.waitForAll(unpack(fns))
