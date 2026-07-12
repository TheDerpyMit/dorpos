--[[
    DorpOS :: phone/system/theme/themes/amoled.lua
    AMOLED (true black) theme — pure black backgrounds to simulate
    AMOLED screens; high-contrast accent colours.
]]
return {
    name        = "AMOLED",
    id          = "amoled",

    bg          = colors.black,
    bgCard      = colors.black,
    bgInput     = colors.black,
    bgStatus    = colors.black,
    bgDock      = colors.black,
    bgOverlay   = colors.black,

    text        = colors.white,
    textMuted   = colors.lightGray,
    textOnAccent= colors.black,

    accent      = colors.yellow,
    accentDark  = colors.orange,

    success     = colors.lime,
    warning     = colors.yellow,
    danger      = colors.red,
    info        = colors.cyan,

    border      = colors.gray,

    statusBarText   = colors.white,
    statusBarBg     = colors.black,
    dockBg          = colors.black,
    dockText        = colors.white,
    iconBg          = colors.black,
    iconText        = colors.yellow,
    notifBg         = colors.black,
    notifText       = colors.white,
    keyboardBg      = colors.black,
    keyboardKey     = colors.gray,
    keyboardText    = colors.white,
    keyboardSpecial = colors.yellow,
}
