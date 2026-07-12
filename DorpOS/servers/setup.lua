--[[
    DorpOS :: servers/setup.lua
    ────────────────────────────
    Interactive server installer and setup script.
    Run this script on a computer to configure it as a DorpOS server.
]]

local function cls()
    term.clear()
    term.setCursorPos(1, 1)
end

cls()
print("========================================")
print("       DorpOS Server Setup Wizard       ")
print("========================================")
print()

local ROLES = {
    { name = "Provisioning Server",  path = "/servers/provisioning/server.lua" },
    { name = "Activation Server",    path = "/servers/activation/server.lua" },
    { name = "Accounts Server",      path = "/servers/accounts/server.lua" },
    { name = "Messages Server",      path = "/servers/messages/server.lua" },
    { name = "Notifications Server", path = "/servers/notifications/server.lua" },
    { name = "Marketplace Server",   path = "/servers/marketplace/server.lua" },
    { name = "Updates Server",       path = "/servers/updates/server.lua" },
    { name = "Cloud Server",         path = "/servers/cloud/server.lua" },
    { name = "All-in-One Server",     path = "/servers/all.lua" },
}

print("Please select the server role for this computer:")
for i, role in ipairs(ROLES) do
    print(string.format(" %d) %s", i, role.name))
end
print()

local choice = nil
while true do
    write("Select (1-" .. #ROLES .. "): ")
    local input = read()
    local num = tonumber(input)
    if num and num >= 1 and num <= #ROLES then
        choice = num
        break
    end
    print("Invalid choice.")
end

local selected = ROLES[choice]
print("\nSelected: " .. selected.name)

-- ─────────────────────────────────────────────────────────────
-- Shared Secret Setup
-- ─────────────────────────────────────────────────────────────
print("\n--- Security Configuration ---")
print("Every DorpOS server on your SMP must use the same HMAC secret key.")
write("Enter HMAC Secret (Press Enter to generate a secure random key): ")
local secret = read()

if secret == "" then
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    secret = ""
    for _ = 1, 32 do
        local idx = math.random(1, #chars)
        secret = secret .. chars:sub(idx, idx)
    end
    print("Generated random secret: " .. secret)
end

if not fs.exists("/data") then fs.makeDir("/data") end
local sf = io.open("/data/secret.txt", "w")
if sf then
    sf:write(secret)
    sf:close()
    print("Saved secret to /data/secret.txt")
else
    print("[Error] Failed to write secret key!")
end

-- ─────────────────────────────────────────────────────────────
-- Provisioning / Updates Phone Files Copy
-- ─────────────────────────────────────────────────────────────
if choice == 1 or choice == 7 or choice == 9 then
    print("\n--- Phone Files Configuration ---")
    print("This role requires phone installation/update files to serve.")
    if fs.exists("/phone") then
        write("Copy local '/phone' directory to '/phone_files'? (y/n): ")
        local ans = read():lower()
        if ans == "y" or ans == "yes" then
            if fs.exists("/phone_files") then
                fs.delete("/phone_files")
            end
            fs.copy("/phone", "/phone_files")
            print("Copied files to /phone_files")
        end
    else
        print("Note: Plase copy your phone OS source files to '/phone_files'")
        print("      on this computer so it can serve installation / updates.")
        if not fs.exists("/phone_files") then
            fs.makeDir("/phone_files")
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- Auto-Start Configuration (startup.lua)
-- ─────────────────────────────────────────────────────────────
print("\n--- Startup Configuration ---")
write("Would you like this server to start automatically on computer boot? (y/n): ")
local auto = read():lower()

if auto == "y" or auto == "yes" then
    local startupCode = [[
-- Auto-generated DorpOS Server Launcher
print("Starting DorpOS ]] .. selected.name .. [[...")
shell.run("]] .. selected.path .. [[")
]]
    local f = io.open("/startup.lua", "w")
    if f then
        f:write(startupCode)
        f:close()
        print("Auto-start launcher written to /startup.lua")
    else
        print("[Error] Failed to write to /startup.lua")
    end
end

print("\n=========================================")
print("  Setup Complete! Run 'startup' or reboot")
print("  to start your " .. selected.name .. ".")
print("=========================================")
