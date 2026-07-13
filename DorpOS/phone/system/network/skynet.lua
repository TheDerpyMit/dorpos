--[[  DorpOS :: phone/system/network/skynet.lua
    Gollark's Skynet Websocket client wrapper.
    Used for real-time messaging over the internet.
]]

local CBOR    = require("system.network.cbor")
local C       = require("shared.constants")

local skynet = {
    server = "wss://skynet.osmarks.net/connect/",
    socket = nil,
    open_channels = {},
}

function skynet.isConnected()
    return skynet.socket ~= nil
end

function skynet.connect(force)
    if not http.websocket then
        return false, "Websockets not supported by this ComputerCraft version"
    end
    if not skynet.socket or force then
        if skynet.socket then
            pcall(skynet.socket.close)
        end
        local sock, err = http.websocket(skynet.server)
        if not sock then
            return false, "Skynet server unavailable: " .. tostring(err)
        end
        skynet.socket = sock

        -- Re-open previously opened channels
        for _, c in ipairs(skynet.open_channels) do
            pcall(function()
                skynet.socket.send(CBOR.encode({ "open", c }), true)
            end)
        end
    end
    return true
end

function skynet.disconnect()
    if skynet.socket then
        pcall(skynet.socket.close)
        skynet.socket = nil
    end
end

local function send_raw(data)
    local ok = skynet.connect()
    if not ok then return false end
    local sendOk, err = pcall(skynet.socket.send, CBOR.encode(data), true)
    if not sendOk then
        -- Retry once on failure
        pcall(skynet.connect, true)
        sendOk = pcall(skynet.socket.send, CBOR.encode(data), true)
    end
    return sendOk
end

function skynet.open(channel)
    local found = false
    for _, c in ipairs(skynet.open_channels) do
        if c == channel then found = true; break end
    end
    if not found then
        table.insert(skynet.open_channels, channel)
    end
    send_raw({ "open", channel })
end

function skynet.send(channel, data, metadata)
    local obj = metadata or {}
    obj.message = data
    obj.channel = channel
    send_raw({ "message", obj })
end

local listener_running = false

-- Read one message from websocket and queue as skynet_message event
function skynet.listen()
    if not skynet.socket then
        local ok = skynet.connect()
        if not ok then
            os.sleep(5) -- throttle retries if server is down
            return
        end
    end

    local contents, err = skynet.socket.receive()
    if not contents then
        -- Connection closed or error
        skynet.socket = nil
        os.sleep(2)
        return
    end

    local ok, result = pcall(CBOR.decode, contents)
    if ok and type(result) == "table" then
        if result[1] == "message" and type(result[2]) == "table" then
            local payload = result[2]
            -- payload has: channel, message, sender (from Skynet server)
            os.queueEvent("skynet_message", payload.channel, payload.message, payload.sender)
        end
    end
end

return skynet
