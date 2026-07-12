--[[
    DorpOS :: phone/system/ui/ui.lua
    ────────────────────────────────
    UI framework core — the single entry point for all drawing.

    Apps NEVER call term.* directly. Instead they use:
        local ui = require("system.ui.ui")
        ui.clear()
        ui.button({ x=2, y=5, width=10, label="OK", onClick=fn })
        ui.label({ x=2, y=3, text="Hello" })

    The framework automatically uses the current theme for all colours.

    Components are lazy-loaded from system/ui/components/*.lua.
    Each component module exports a single draw(props) function.

    Coordinates are always (column, row), 1-indexed.
]]

local ui = {}

local Theme = require("system.theme.theme")
local C     = require("shared.constants")

-- ─────────────────────────────────────────────────────────────
-- Component registry (lazy-loaded)
-- ─────────────────────────────────────────────────────────────

local _components = {}
local COMP_PATH = "system.ui.components."

local function getComp(name)
    if not _components[name] then
        local ok, mod = pcall(require, COMP_PATH .. name)
        if not ok then error("UI component not found: " .. name .. "\n" .. mod) end
        _components[name] = mod
    end
    return _components[name]
end

-- ─────────────────────────────────────────────────────────────
-- Draw context helpers
-- ─────────────────────────────────────────────────────────────

--- Clear the screen with the theme background.
function ui.clear(target)
    local t = Theme.get()
    local tgt = target or term
    tgt.setBackgroundColor(t.bg)
    tgt.setTextColor(t.text)
    tgt.clear()
    tgt.setCursorPos(1, 1)
end

--- Set cursor position.
function ui.pos(x, y)
    term.setCursorPos(x, y)
end

--- Write text at (x, y) with optional fg/bg colours.
---@param x   number
---@param y   number
---@param txt string
---@param fg  number?  Defaults to theme.text
---@param bg  number?  Defaults to theme.bg
function ui.write(x, y, txt, fg, bg)
    local t = Theme.get()
    term.setCursorPos(x, y)
    term.setTextColor(fg or t.text)
    term.setBackgroundColor(bg or t.bg)
    term.write(tostring(txt))
end

--- Draw a filled rectangle.
---@param x      number
---@param y      number
---@param width  number
---@param height number
---@param color  number
function ui.rect(x, y, width, height, color)
    term.setBackgroundColor(color)
    for row = y, y + height - 1 do
        term.setCursorPos(x, row)
        term.write(string.rep(" ", width))
    end
end

--- Draw a horizontal divider line.
---@param y     number
---@param color number?  Defaults to theme.border
function ui.divider(y, color)
    local t = Theme.get()
    term.setCursorPos(1, y)
    term.setTextColor(color or t.border)
    term.setBackgroundColor(t.bg)
    term.write(string.rep("\140", C.SCREEN_WIDTH))  -- \140 = horizontal line char in CC font
end

-- ─────────────────────────────────────────────────────────────
-- Component dispatch
-- ─────────────────────────────────────────────────────────────

--- Render a button.
--- Props: { x, y, width, label, onClick, disabled, style }
function ui.button(props)    return getComp("button"  ).draw(props) end

--- Render a text label.
--- Props: { x, y, text, fg, bg, align, width }
function ui.label(props)     return getComp("label"   ).draw(props) end

--- Render a bordered window / panel.
--- Props: { x, y, width, height, title, bg }
function ui.window(props)    return getComp("window"  ).draw(props) end

--- Render a scrollable list.
--- Props: { x, y, width, height, items, selected, onSelect, scroll }
function ui.list(props)      return getComp("list"    ).draw(props) end

--- Render a modal dialog with title, message, and buttons.
--- Props: { title, message, buttons, onResult }
function ui.dialog(props)    return getComp("dialog"  ).draw(props) end

--- Render a popup overlay.
--- Props: { x, y, width, height, drawContent }
function ui.popup(props)     return getComp("popup"   ).draw(props) end

--- Render a single-line text input.
--- Props: { x, y, width, value, placeholder, onChange, password }
function ui.textbox(props)   return getComp("textbox" ).draw(props) end

--- Render a scroll container.
--- Props: { x, y, width, height, contentHeight, scrollY, drawContent }
function ui.scroll(props)    return getComp("scroll"  ).draw(props) end

--- Render a progress bar.
--- Props: { x, y, width, value, max, fg, bg, showText }
function ui.progress(props)  return getComp("progress").draw(props) end

--- Render a spinner (loading indicator) at a position.
--- Props: { x, y, fg, bg, frame }
function ui.spinner(props)   return getComp("spinner" ).draw(props) end

--- Render an on/off toggle switch.
--- Props: { x, y, value, onChange, label }
function ui.switch(props)    return getComp("switch"  ).draw(props) end

--- Render a checkbox.
--- Props: { x, y, value, onChange, label }
function ui.checkbox(props)  return getComp("checkbox").draw(props) end

--- Render a toast notification banner.
--- Props: { text, type, y }   type = "info"|"success"|"warning"|"error"
function ui.toast(props)     return getComp("toast"   ).draw(props) end

--- Render the on-screen keyboard.
--- Props: { y, onKey, onBackspace, onEnter, shifted, value }
function ui.keyboard(props)  return getComp("keyboard").draw(props) end

-- ─────────────────────────────────────────────────────────────
-- Event helpers
-- ─────────────────────────────────────────────────────────────

--- Check if a mouse click at (mx, my) is within a rectangle.
---@param mx number
---@param my number
---@param rx number  rect left
---@param ry number  rect top
---@param rw number  rect width
---@param rh number  rect height
---@return boolean
function ui.hitTest(mx, my, rx, ry, rw, rh)
    return mx >= rx and mx < rx + rw
       and my >= ry and my < ry + rh
end

--- Block until the next mouse_click event and return (button, x, y).
---@return number button, number x, number y
function ui.waitClick()
    local _, button, x, y = os.pullEvent("mouse_click")
    return button, x, y
end

--- Block until any of the listed events fires.
---@param events table  Array of event name strings
---@return string event, ...
function ui.waitEvent(events)
    while true do
        local ev = { os.pullEvent() }
        for _, name in ipairs(events) do
            if ev[1] == name then return table.unpack(ev) end
        end
    end
end

return ui
