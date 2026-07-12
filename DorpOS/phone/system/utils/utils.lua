--[[
    DorpOS :: phone/system/utils/utils.lua
    ──────────────────────────────────────
    General-purpose utility functions used across the entire codebase.
    No dependencies on other DorpOS modules (safe to require anywhere).
]]

local utils = {}

-- ─────────────────────────────────────────────────────────────
-- String helpers
-- ─────────────────────────────────────────────────────────────

--- Trim leading and trailing whitespace.
---@param s string
---@return string
function utils.trim(s)
    return s:match("^%s*(.-)%s*$")
end

--- Split a string by a separator pattern.
---@param s   string
---@param sep string  Lua pattern (default "%s+")
---@return table
function utils.split(s, sep)
    sep = sep or "%s+"
    local parts = {}
    local pattern = "([^" .. sep .. "]+)"
    for part in s:gmatch(pattern) do
        table.insert(parts, part)
    end
    return parts
end

--- Wrap text to fit within a given column width, returning a table of lines.
---@param text  string
---@param width number
---@return table lines
function utils.wrap(text, width)
    local lines  = {}
    local line   = ""
    for word in text:gmatch("%S+") do
        if #line + #word + 1 > width then
            if #line > 0 then table.insert(lines, line) end
            line = word
        else
            line = line == "" and word or (line .. " " .. word)
        end
    end
    if #line > 0 then table.insert(lines, line) end
    return lines
end

--- Truncate a string to max length, appending "…" if cut.
---@param s      string
---@param maxLen number
---@return string
function utils.truncate(s, maxLen)
    if #s <= maxLen then return s end
    return s:sub(1, maxLen - 1) .. "\x85"  -- \x85 = ellipsis in CC font
end

--- Pad a string to exactly `width` characters (left-align, space-fill).
---@param s     string
---@param width number
---@return string
function utils.padRight(s, width)
    s = tostring(s)
    if #s >= width then return s:sub(1, width) end
    return s .. string.rep(" ", width - #s)
end

--- Pad a string to exactly `width` characters (right-align, space-fill).
---@param s     string
---@param width number
---@return string
function utils.padLeft(s, width)
    s = tostring(s)
    if #s >= width then return s:sub(1, width) end
    return string.rep(" ", width - #s) .. s
end

--- Centre a string within `width` characters.
---@param s     string
---@param width number
---@return string
function utils.centre(s, width)
    s = tostring(s)
    if #s >= width then return s:sub(1, width) end
    local pad   = width - #s
    local left  = math.floor(pad / 2)
    local right = pad - left
    return string.rep(" ", left) .. s .. string.rep(" ", right)
end

--- Check if a string starts with a given prefix.
function utils.startsWith(s, prefix)
    return s:sub(1, #prefix) == prefix
end

--- Check if a string ends with a given suffix.
function utils.endsWith(s, suffix)
    return suffix == "" or s:sub(-#suffix) == suffix
end

-- ─────────────────────────────────────────────────────────────
-- Table helpers
-- ─────────────────────────────────────────────────────────────

--- Shallow copy of a table.
---@param t table
---@return table
function utils.shallowCopy(t)
    local copy = {}
    for k, v in pairs(t) do copy[k] = v end
    return copy
end

--- Deep copy of a table (handles nested tables; no cycles).
---@param t table
---@return table
function utils.deepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[utils.deepCopy(k)] = utils.deepCopy(v)
    end
    return setmetatable(copy, getmetatable(t))
end

--- Merge tables: values from `src` overwrite `dst` (shallow, in-place).
---@param dst table
---@param src table
---@return table dst
function utils.merge(dst, src)
    for k, v in pairs(src) do dst[k] = v end
    return dst
end

--- Check if a value exists in an array-style table.
---@param t   table
---@param val any
---@return boolean
function utils.contains(t, val)
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

--- Filter an array using a predicate function.
---@param t   table
---@param fn  function  predicate(value) -> boolean
---@return table
function utils.filter(t, fn)
    local out = {}
    for _, v in ipairs(t) do
        if fn(v) then table.insert(out, v) end
    end
    return out
end

--- Map an array through a transform function.
---@param t  table
---@param fn function  transform(value) -> any
---@return table
function utils.map(t, fn)
    local out = {}
    for i, v in ipairs(t) do out[i] = fn(v) end
    return out
end

--- Find the first element satisfying a predicate.
---@param t  table
---@param fn function
---@return any|nil
function utils.find(t, fn)
    for _, v in ipairs(t) do
        if fn(v) then return v end
    end
    return nil
end

-- ─────────────────────────────────────────────────────────────
-- Math helpers
-- ─────────────────────────────────────────────────────────────

--- Clamp a value between min and max.
function utils.clamp(v, mn, mx)
    return math.max(mn, math.min(mx, v))
end

--- Linear interpolation between a and b by factor t in [0,1].
function utils.lerp(a, b, t)
    return a + (b - a) * t
end

--- Round a number to the nearest integer.
function utils.round(v)
    return math.floor(v + 0.5)
end

-- ─────────────────────────────────────────────────────────────
-- Time helpers
-- ─────────────────────────────────────────────────────────────

--- Format epoch ms as "HH:MM" (Minecraft in-game time is not real time;
--- os.epoch("utc") gives real UTC ms on CC:T servers).
---@param epochMs number  UTC epoch in milliseconds
---@return string "HH:MM"
function utils.formatTime(epochMs)
    local secs  = math.floor(epochMs / 1000)
    local h     = math.floor(secs / 3600) % 24
    local m     = math.floor(secs / 60) % 60
    return string.format("%02d:%02d", h, m)
end

--- Format epoch ms as "DD/MM/YYYY".
function utils.formatDate(epochMs)
    -- CC:T doesn't have os.date, so we compute manually
    local secs  = math.floor(epochMs / 1000)
    local days  = math.floor(secs / 86400)
    -- Days since 1970-01-01
    local y, m, d = 1970, 1, 1
    local daysInMonth = {31,28,31,30,31,30,31,31,30,31,30,31}
    while true do
        local diy = (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) and 366 or 365
        if days < diy then break end
        days = days - diy
        y = y + 1
    end
    local leap = (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0))
    if leap then daysInMonth[2] = 29 end
    while true do
        local dim = daysInMonth[m]
        if days < dim then break end
        days = days - dim
        m = m + 1
    end
    d = days + 1
    return string.format("%02d/%02d/%04d", d, m, y)
end

--- Return current UTC time string "HH:MM".
function utils.now()
    return utils.formatTime(os.epoch("utc"))
end

--- Return current date string "DD/MM/YYYY".
function utils.today()
    return utils.formatDate(os.epoch("utc"))
end

-- ─────────────────────────────────────────────────────────────
-- Serialisation helpers
-- ─────────────────────────────────────────────────────────────

--- Safely serialise a value to a string. Returns nil on failure.
---@param v any
---@return string|nil
function utils.serialise(v)
    local ok, s = pcall(textutils.serialise, v)
    return ok and s or nil
end

--- Safely unserialise a string. Returns nil on failure.
---@param s string
---@return any|nil
function utils.unserialise(s)
    local ok, v = pcall(textutils.unserialise, s)
    return ok and v or nil
end

return utils
