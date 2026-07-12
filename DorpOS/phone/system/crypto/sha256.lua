--[[
    DorpOS :: phone/system/crypto/sha256.lua
    ─────────────────────────────────────────
    Pure-Lua implementation of SHA-256.
    Used for PIN hashing and manifest integrity verification.

    Original algorithm: FIPS PUB 180-4.
    This implementation is adapted for Lua 5.1 / LuaJIT with
    32-bit integer emulation via bit32 (included in CC:T).

    Usage:
        local sha = require("system.crypto.sha256")
        local hash = sha.hash("hello world")
        -- "b94d27b9934d3e08a52e52d7da7dabfac484efe04294e576b47c7862e9e083de"
        -- (standard SHA-256 hex output, 64 chars)

        -- Hash a table (serialises it first)
        local h2 = sha.hashTable({ key = "value" })
]]

local sha256 = {}

-- ─────────────────────────────────────────────────────────────
-- Constants: first 32 bits of fractional parts of cube roots
-- of first 64 primes.
-- ─────────────────────────────────────────────────────────────
local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

-- Initial hash values: first 32 bits of fractional parts of
-- square roots of first 8 primes.
local H0 = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
}

-- ─────────────────────────────────────────────────────────────
-- Bit helpers using bit32 (available in CC:T / Lua 5.1)
-- ─────────────────────────────────────────────────────────────
local b = bit32 or bit  -- CC:T provides bit32

local function band(a, b_)  return b.band(a, b_)   end
local function bxor(a, b_)  return b.bxor(a, b_)   end
local function bnot(a)      return b.bnot(a)         end
local function rshift(a,n)  return b.rshift(a, n)    end
local function lshift(a,n)  return b.lshift(a, n)    end
local function rrot(x, n)   return b.rrotate(x, n)   end

-- 32-bit add (wraps at 2^32)
local function add32(...)
    local s = 0
    for _, v in ipairs({...}) do
        s = band(s + v, 0xFFFFFFFF)
    end
    return s
end

-- ─────────────────────────────────────────────────────────────
-- Pre-processing: convert string to array of 32-bit big-endian words
-- ─────────────────────────────────────────────────────────────
local function preprocess(msg)
    local len = #msg
    local bitlen_hi = math.floor(len * 8 / 0x100000000) % 0x100000000
    local bitlen_lo = (len * 8) % 0x100000000

    -- Append bit "1" (0x80) then zeros, then 64-bit big-endian length
    msg = msg .. "\x80"
    while (#msg % 64) ~= 56 do
        msg = msg .. "\x00"
    end
    -- Append 64-bit length as big-endian
    for i = 3, 0, -1 do msg = msg .. string.char(rshift(bitlen_hi, i*8) % 256) end
    for i = 3, 0, -1 do msg = msg .. string.char(rshift(bitlen_lo, i*8) % 256) end

    -- Pack into 32-bit words (big-endian)
    local words = {}
    for i = 1, #msg, 4 do
        local a, b_, c, d_ = msg:byte(i, i+3)
        table.insert(words, lshift(a,24) + lshift(b_,16) + lshift(c,8) + d_)
    end
    return words
end

-- ─────────────────────────────────────────────────────────────
-- Core SHA-256 computation
-- ─────────────────────────────────────────────────────────────
local function compress(H, chunk)
    local W = {}
    for i = 1, 16 do W[i] = chunk[i] end
    for i = 17, 64 do
        local s0 = bxor(rrot(W[i-15],  7), bxor(rrot(W[i-15], 18), rshift(W[i-15],  3)))
        local s1 = bxor(rrot(W[i- 2], 17), bxor(rrot(W[i- 2], 19), rshift(W[i- 2], 10)))
        W[i] = add32(W[i-16], s0, W[i-7], s1)
    end

    local a, b_, c, d_, e, f, g, h =
        H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]

    for i = 1, 64 do
        local S1    = bxor(rrot(e, 6), bxor(rrot(e, 11), rrot(e, 25)))
        local ch    = bxor(band(e, f), band(bnot(e), g))
        local temp1 = add32(h, S1, ch, K[i], W[i])
        local S0    = bxor(rrot(a, 2), bxor(rrot(a, 13), rrot(a, 22)))
        local maj   = bxor(band(a, b_), bxor(band(a, c), band(b_, c)))
        local temp2 = add32(S0, maj)

        h = g; g = f; f = e
        e = add32(d_, temp1)
        d_ = c; c = b_; b_ = a
        a = add32(temp1, temp2)
    end

    H[1] = add32(H[1], a)
    H[2] = add32(H[2], b_)
    H[3] = add32(H[3], c)
    H[4] = add32(H[4], d_)
    H[5] = add32(H[5], e)
    H[6] = add32(H[6], f)
    H[7] = add32(H[7], g)
    H[8] = add32(H[8], h)
end

--- Compute the SHA-256 hash of a string.
---@param msg string
---@return string  64-character lowercase hex digest
function sha256.hash(msg)
    assert(type(msg) == "string", "sha256.hash expects a string")
    local words = preprocess(msg)
    local H = {}
    for i = 1, 8 do H[i] = H0[i] end

    local chunkCount = 0
    for i = 1, #words, 16 do
        local chunk = {}
        for j = 0, 15 do chunk[j+1] = words[i+j] end
        compress(H, chunk)
        chunkCount = chunkCount + 1
        if chunkCount % 4 == 0 then
            if _G.sleep then _G.sleep(0)
            elseif _G.os and _G.os.sleep then _G.os.sleep(0) end
        end
    end

    local digest = ""
    for _, v in ipairs(H) do
        digest = digest .. string.format("%08x", v)
    end
    return digest
end

--- Hash a Lua table by serialising it first. Useful for manifests.
---@param t table
---@return string hex digest
function sha256.hashTable(t)
    return sha256.hash(textutils.serialise(t))
end

--- Constant-time string comparison (prevent timing attacks on tokens).
---@param a string
---@param b string
---@return boolean
function sha256.equal(a, b)
    if #a ~= #b then return false end
    local diff = 0
    for i = 1, #a do
        diff = bit32.bor(diff, bit32.bxor(a:byte(i), b:byte(i)))
    end
    return diff == 0
end

return sha256
