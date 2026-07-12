# DorpOS Theme System

## Overview

Every UI element reads colours from the active theme via `Theme.get()`.
No hardcoded colours appear in app or component code.

## Built-in Themes

| ID | Name | Description |
|----|------|-------------|
| `dark` | Dark | Default — dark grey backgrounds, cyan accent |
| `light` | Light | White backgrounds, blue accent |
| `amoled` | AMOLED | True black, yellow accent |

## Colour Tokens

Every theme table has these keys:

| Token | Purpose |
|-------|---------|
| `bg` | Main screen background |
| `bgCard` | Card / panel background |
| `bgInput` | Text input background |
| `bgStatus` | Status bar background |
| `bgDock` | Dock background |
| `text` | Primary text |
| `textMuted` | Secondary / muted text |
| `textOnAccent` | Text on accent-coloured surfaces |
| `accent` | Buttons, highlights, active states |
| `accentDark` | Pressed / hover accent |
| `success` | Success messages |
| `warning` | Warning messages |
| `danger` | Error / destructive actions |
| `info` | Information |
| `border` | Dividers |
| `iconBg` / `iconText` | App icon colours |
| `dockBg` / `dockText` | Dock bar colours |
| `keyboardBg` / `keyboardKey` / `keyboardText` / `keyboardSpecial` | On-screen keyboard |
| `notifBg` / `notifText` | Notification banner |

## Creating a Custom Theme

1. Create `/phone/system/theme/themes/mytheme.lua`:

```lua
return {
    name        = "My Theme",
    id          = "mytheme",

    bg          = colors.purple,
    bgCard      = colors.magenta,
    bgInput     = colors.magenta,
    bgStatus    = colors.purple,
    bgDock      = colors.purple,
    bgOverlay   = colors.purple,

    text        = colors.white,
    textMuted   = colors.lightGray,
    textOnAccent= colors.white,

    accent      = colors.pink,
    accentDark  = colors.red,

    success     = colors.lime,
    warning     = colors.yellow,
    danger      = colors.red,
    info        = colors.cyan,

    border      = colors.magenta,

    statusBarText   = colors.white,
    statusBarBg     = colors.purple,
    dockBg          = colors.purple,
    dockText        = colors.white,
    iconBg          = colors.magenta,
    iconText        = colors.white,
    notifBg         = colors.magenta,
    notifText       = colors.white,
    keyboardBg      = colors.purple,
    keyboardKey     = colors.magenta,
    keyboardText    = colors.white,
    keyboardSpecial = colors.pink,
}
```

2. Register it in `phone/system/theme/theme.lua`:

```lua
local THEMES = {
    dark    = "system.theme.themes.dark",
    light   = "system.theme.themes.light",
    amoled  = "system.theme.themes.amoled",
    mytheme = "system.theme.themes.mytheme",   -- add this line
}
```

3. It will now appear in Settings → Appearance.

## Switching Theme at Runtime

```lua
local Theme = require("system.theme.theme")
Theme.set("amoled")   -- switches and persists
```

## Reading Theme in Code

```lua
local Theme = require("system.theme.theme")
local t     = Theme.get()

term.setBackgroundColor(t.bg)
term.setTextColor(t.accent)
```
