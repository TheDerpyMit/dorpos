--[[
    DorpOS :: phone/system/crypto/token.lua
    ────────────────────────────────────────
    Session token utilities.

    Tokens are strings with the format:
        "<deviceId>.<userId>.<timestamp>.<hmac>"

    The HMAC is SHA-256(secret .. "|" .. deviceId .. "|" .. userId .. "|" .. timestamp).
    The server holds the secret. The phone stores the full token and
    sends it with every authenticated request. The server verifies the
    HMAC on receipt — no trust is placed in the client's claimed identity.

    Usage (server side):
        local token = require("system.crypto.token")
        local SECRET = "change-me-on-your-smp"  -- set in server config

        local tok = token.create(SECRET, "42", "alice", os.epoch("utc"))
        local ok, claims = token.verify(SECRET, tok)

    Usage (phone side):
        -- Just store and forward the token string received from the server.
        -- The phone never generates tokens itself.
]]

local token = {}
local sha = require("system.crypto.sha256")

local SEP = "."

--- Create a signed token string.
---@param secret    string  Server-side HMAC secret
---@param deviceId  string
---@param userId    string
---@param timestamp number  os.epoch("utc") at time of issue
---@return string tokenString
function token.create(secret, deviceId, userId, timestamp)
    local ts  = tostring(math.floor(timestamp))
    local msg = secret .. "|" .. deviceId .. "|" .. userId .. "|" .. ts
    local hmac = sha.hash(msg)
    return deviceId .. SEP .. userId .. SEP .. ts .. SEP .. hmac
end

--- Verify a token string.
---@param secret      string
---@param tokenString string
---@param maxAge      number?  Max age in seconds (default: no limit)
---@return boolean ok, table? claims  claims = { deviceId, userId, timestamp }
function token.verify(secret, tokenString, maxAge)
    if type(tokenString) ~= "string" then
        return false, nil
    end

    -- Split on SEP
    local parts = {}
    for part in tokenString:gmatch("[^" .. SEP .. "]+") do
        table.insert(parts, part)
    end
    if #parts ~= 4 then return false, nil end

    local deviceId = parts[1]
    local userId   = parts[2]
    local ts       = parts[3]
    local hmac     = parts[4]

    -- Reconstruct expected HMAC
    local msg      = secret .. "|" .. deviceId .. "|" .. userId .. "|" .. ts
    local expected = sha.hash(msg)

    -- Constant-time compare
    if not sha.equal(hmac, expected) then return false, nil end

    local timestamp = tonumber(ts)
    if not timestamp then return false, nil end

    -- Check age
    if maxAge then
        local now = math.floor(os.epoch("utc"))
        if now - timestamp > maxAge * 1000 then
            return false, nil  -- expired
        end
    end

    return true, {
        deviceId  = deviceId,
        userId    = userId,
        timestamp = timestamp,
    }
end

--- Extract the userId from a token without verifying it.
--- The server MUST always call verify() — this is only for display.
---@param tokenString string
---@return string|nil
function token.getUserId(tokenString)
    if type(tokenString) ~= "string" then return nil end
    local parts = {}
    for part in tokenString:gmatch("[^" .. SEP .. "]+") do
        table.insert(parts, part)
    end
    return parts[2]
end

return token
