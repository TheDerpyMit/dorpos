--[[
    DorpOS :: phone/system/theme/themes/dark.lua
    Dark theme — default DorpOS colour scheme.
    Uses CC:T colour constants (powers of 2, 0-32768).
]]
return {
    name        = "Dark",
    id          = "dark",

    -- Backgrounds
    bg          = colors.black,        -- main background
    bgCard      = colors.gray,         -- card / panel background
    bgInput     = colors.gray,         -- text input background
    bgStatus    = colors.black,        -- status bar background
    bgDock      = colors.black,        -- dock background
    bgOverlay   = colors.black,        -- overlay / modal backdrop

    -- Text
    text        = colors.white,        -- primary text
    textMuted   = colors.lightGray,    -- secondary / muted text
    textOnAccent= colors.white,        -- text on accent-coloured surfaces

    -- Accent (interactive elements)
    accent      = colors.cyan,         -- buttons, links, highlights
    accentDark  = colors.blue,         -- pressed / active state

    -- Semantic
    success     = colors.green,
    warning     = colors.yellow,
    danger      = colors.red,
    info        = colors.cyan,

    -- Dividers / borders
    border      = colors.lightGray,

    -- Specific UI elements
    statusBarText   = colors.white,
    statusBarBg     = colors.black,
    dockBg          = colors.gray,
    dockText        = colors.white,
    iconBg          = colors.gray,
    iconText        = colors.white,
    notifBg         = colors.gray,
    notifText       = colors.white,
    keyboardBg      = colors.gray,
    keyboardKey     = colors.lightGray,
    keyboardText    = colors.white,
    keyboardSpecial = colors.blue,
}
