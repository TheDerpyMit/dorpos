--[[
    DorpOS :: phone/system/utils/logger.lua
    ───────────────────────────────────────
    Structured logger. Writes to /data/logs/dorpos.log with automatic
    rotation when the file exceeds C.LOG_MAX_SIZE bytes.

    Usage:
        local log = require("system.utils.logger")
        log.info("kernel", "Boot started")
        log.error("network", "Timeout after 10s", { host = "dorpos.messages" })
]]

local logger = {}
local C = require("shared.constants")

local LOG_FILE   = C.PATH_LOGS .. "/dorpos.log"
local LOG_OLD    = C.PATH_LOGS .. "/dorpos.old.log"

local LEVEL_NAMES = { "DEBUG", "INFO ", "WARN ", "ERROR", "FATAL" }

-- Ensure log directory exists
local function ensureDir()
    if not fs.exists(C.PATH_LOGS) then
        fs.makeDir(C.PATH_LOGS)
    end
end

-- Rotate log file if it's too big
local function maybeRotate()
    if fs.exists(LOG_FILE) then
        local size = fs.getSize(LOG_FILE)
        if size and size >= C.LOG_MAX_SIZE then
            if fs.exists(LOG_OLD) then fs.delete(LOG_OLD) end
            fs.move(LOG_FILE, LOG_OLD)
        end
    end
end

--- Write a log entry at the given level.
---@param level  number  C.LOG_DEBUG .. C.LOG_FATAL
---@param tag    string  Module/component name, e.g. "kernel"
---@param msg    string  Human-readable message
---@param data   table?  Optional extra context (serialised inline)
function logger.write(level, tag, msg, data)
    if level < C.LOG_MIN_LEVEL then return end
    ensureDir()
    maybeRotate()

    local levelStr = LEVEL_NAMES[level] or "?????"
    local timestamp = os.epoch("utc")
    local extra = ""
    if data and type(data) == "table" then
        local ok, s = pcall(textutils.serialise, data)
        if ok then extra = " | " .. s:gsub("%s+", " ") end
    end

    local line = string.format("[%d] [%s] [%s] %s%s\n",
        timestamp, levelStr, tag, msg, extra)

    local f = io.open(LOG_FILE, "a")
    if f then
        f:write(line)
        f:close()
    end
end

function logger.debug(tag, msg, data) logger.write(C.LOG_DEBUG, tag, msg, data) end
function logger.info (tag, msg, data) logger.write(C.LOG_INFO,  tag, msg, data) end
function logger.warn (tag, msg, data) logger.write(C.LOG_WARN,  tag, msg, data) end
function logger.error(tag, msg, data) logger.write(C.LOG_ERROR, tag, msg, data) end
function logger.fatal(tag, msg, data) logger.write(C.LOG_FATAL, tag, msg, data) end

--- Read the last N lines from the log file. Useful for the About app.
---@param n number
---@return table lines
function logger.tail(n)
    local lines = {}
    if not fs.exists(LOG_FILE) then return lines end
    local f = io.open(LOG_FILE, "r")
    if not f then return lines end
    for line in f:lines() do
        table.insert(lines, line)
        if #lines > n * 2 then
            table.remove(lines, 1)
        end
    end
    f:close()
    local result = {}
    local start = math.max(1, #lines - n + 1)
    for i = start, #lines do
        table.insert(result, lines[i])
    end
    return result
end

return logger
