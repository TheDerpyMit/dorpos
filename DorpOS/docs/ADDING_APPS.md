# Adding a New App to DorpOS

## 1. Create the app file

Create `/phone/apps/<yourapp>/init.lua`:

```lua
--[[  DorpOS :: phone/apps/myapp/init.lua  ]]
local C     = require("shared.constants")
local ui    = require("system.ui.ui")
local Theme = require("system.theme.theme")
local utils = require("system.utils.utils")

local W, H = C.SCREEN_WIDTH, C.SCREEN_HEIGHT

local function draw()
    local t = Theme.get()
    ui.clear()

    -- Header bar (standard pattern)
    term.setCursorPos(1, 1)
    term.setBackgroundColor(t.accent)
    term.setTextColor(t.textOnAccent)
    term.write(utils.padRight(" My App", W))

    -- Your content here
    ui.write(2, 5, "Hello from My App!", t.text, t.bg)

    -- Back button (standard pattern)
    ui.button({ x = 1, y = H, width = 6, label = "Back", style = "ghost" })
end

draw()

-- Event loop
while true do
    local ev = { os.pullEvent() }
    if ev[1] == "mouse_click" then
        local mx, my = ev[3], ev[4]
        if my == H and mx <= 6 then return end  -- exit app
        -- Handle other clicks...
    end
end
```

## 2. Register the app

In `phone/system/services/app_manager.lua`, add to `BUILTIN_APPS`:

```lua
{ id = "com.dorpos.myapp", name = "My App", icon = "?", path = "/apps/myapp/init.lua", builtin = true },
```

Or for a **third-party app** installed at runtime:

```lua
local appMgr = require("system.services.app_manager")
appMgr.register({
    id      = "com.yourname.myapp",
    name    = "My App",
    icon    = "?",
    path    = "/apps/myapp/init.lua",
    builtin = false,
})
```

## 3. Add a constant (optional)

In `shared/constants.lua`:

```lua
Constants.APP_MYAPP = "com.dorpos.myapp"
```

## 4. Standard patterns to follow

### Header bar
```lua
term.setCursorPos(1, 1)
term.setBackgroundColor(t.accent)
term.setTextColor(t.textOnAccent)
term.write(utils.padRight(" App Name", W))
```

### Back button
```lua
ui.button({ x = 1, y = H, width = 6, label = "Back", style = "ghost" })
-- In event loop:
if my == H and mx <= 6 then return end
```

### Using storage
```lua
local Storage = require("system.storage.storage")
local store   = Storage.open("myapp_data")
store.set("key", value)
store.save()
local val = store.get("key", defaultValue)
```

### Making network requests
```lua
local net = require("system.network.network")
local ok, resp = net.post(C.HOST_ACCOUNTS, "/some/endpoint", { payload = data })
if ok then
    -- resp.body contains the response
end
```

### Using on-screen keyboard
```lua
local kbComp = require("system.ui.components.keyboard")
local kbHits = kbComp.draw({
    y       = H - 6,
    shifted = shifted,
    onChar  = function(c) myValue = myValue .. c end,
    onBack  = function() if #myValue > 0 then myValue = myValue:sub(1,-2) end end,
    onEnter = function() -- submit end,
    onShift = function() shifted = not shifted end,
    onClose = function() -- dismiss keyboard end,
})

-- In mouse_click handler:
kbComp.handleClick(kbHits, mx, my)
```

## 5. Launching another app

From within an app, launch another using the kernel event:

```lua
os.queueEvent("dorpos_launch_app", C.APP_MESSAGES, { optional = "args" })
```

The app will open after your current app returns control to the kernel.

## 6. Pushing a notification

```lua
local notif = require("system.services.notification_manager")
notif.push({
    title    = "My App",
    body     = "Something happened!",
    type     = "info",    -- "info"|"success"|"warning"|"error"
    priority = 1,         -- 0=silent, 1=normal, 2=urgent (ignores DND)
})
```
