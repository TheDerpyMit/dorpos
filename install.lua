--[[
    DorpOS :: install.lua
    ─────────────────────
    Unified installer for both Phones and Servers.
    Downloads directly from your GitHub repository: TheDerpyMit/dorpos
]]

local REPO_OWNER = "TheDerpyMit"
local REPO_NAME  = "dorpos"
local BRANCH     = "main"

local function cls()
    term.clear()
    term.setCursorPos(1, 1)
end

local function downloadFile(url, path)
    -- We pass a User-Agent to avoid getting blocked by GitHub
    local resp = http.get(url, { ["User-Agent"] = "ComputerCraft" })
    if not resp then return false end
    local content = resp.readAll()
    resp.close()

    local dir = fs.getDir(path)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

cls()
print("========================================")
print("          DorpOS Installer              ")
print("========================================")
print()
print("Where are you installing DorpOS?")
print(" 1) Phone (Ender/Pocket Computer)")
print(" 2) Server (CC Computer with wireless modem)")
print()

local choice = nil
while true do
    write("Select (1-2): ")
    local input = read()
    if input == "1" or input == "2" then
        choice = tonumber(input)
        break
    end
    print("Invalid choice.")
end

if choice == 1 then
    -- Phone installation
    cls()
    print("Installing DorpOS Phone Bootstrap...")
    local url  = "https://raw.githubusercontent.com/" .. REPO_OWNER .. "/" .. REPO_NAME .. "/" .. BRANCH .. "/DorpOS/phone/startup.lua?t=" .. os.epoch("utc")
    local path = "/startup.lua"
    
    print("Downloading: " .. path)
    if downloadFile(url, path) then
        print("\nSuccess! Phone Bootstrap installed.")
        print("Rebooting in 3 seconds to provision...")
        os.sleep(3)
        -- Delete installer so it doesn't clutter the drive
        if shell.getRunningProgram() ~= "startup" then
            fs.delete(shell.getRunningProgram())
        end
        os.reboot()
    else
        print("\n[Error] Download failed! Ensure HTTP is enabled in config.")
    end

elseif choice == 2 then
    -- Server installation
    cls()
    print("Fetching server repository tree from GitHub...")
    local apiURL = "https://api.github.com/repos/" .. REPO_OWNER .. "/" .. REPO_NAME .. "/git/trees/" .. BRANCH .. "?recursive=1&t=" .. os.epoch("utc")
    
    local resp = http.get(apiURL, { ["User-Agent"] = "ComputerCraft-Installer" })
    if not resp then
        print("\n[Error] Could not contact GitHub API.")
        print("Ensure HTTP is enabled in your ComputerCraft config.")
        return
    end
    
    local jsonStr = resp.readAll()
    resp.close()
    
    local ok, data = pcall(textutils.unserialiseJSON or json.decode, jsonStr)
    if not ok or not data or not data.tree then
        print("\n[Error] Failed to parse repository metadata.")
        return
    end

    print("Downloading server repository files...")
    
    local successCount = 0
    local failCount    = 0

    for _, entry in ipairs(data.tree) do
        -- Only download files (type = "blob") located inside the DorpOS folder
        if entry.type == "blob" and entry.path:sub(1, 7) == "DorpOS/" then
            -- Strip the "DorpOS/" prefix to install directly to root directories
            local targetPath = "/" .. entry.path:sub(8)
            local downloadURL = "https://raw.githubusercontent.com/" .. REPO_OWNER .. "/" .. REPO_NAME .. "/" .. BRANCH .. "/" .. entry.path .. "?t=" .. os.epoch("utc")
            
            print("Downloading: " .. targetPath)
            if downloadFile(downloadURL, targetPath) then
                successCount = successCount + 1
            else
                print("[Failed] " .. targetPath)
                failCount = failCount + 1
            end
        end
    end

    print("\nDownload complete!")
    print(string.format("Success: %d files, Failed: %d files", successCount, failCount))

    if failCount == 0 then
        -- Run the server setup wizard immediately
        print("Launching Setup Wizard...")
        os.sleep(1.5)
        -- Clean up this installer
        fs.delete(shell.getRunningProgram())
        shell.run("/servers/setup.lua")
    else
        print("Please check your internet connection and try again.")
    end
end
