--[[
    DorpOS :: shared/api.lua
    ────────────────────────
    Convenience re-export of shared libraries for modules that want a
    single require instead of loading constants and protocol separately.

    Usage:
        local API = require("shared.api")
        API.proto.init()
        local ok, resp = API.proto.request(API.C.HOST_ACCOUNTS, "/login", body)
]]

local api = {}

api.C     = require("shared.constants")
api.proto = require("shared.protocol")

--- Shorthand: initialise the network layer.
function api.init()
    api.proto.init()
end

return api
