--[[
    DorpOS :: phone/system/animation/animation.lua
    ───────────────────────────────────────────────
    Lightweight animation / tweening engine.

    Animations run on a coroutine-friendly sleep loop — they do not
    block the main event loop. Call anim.tick() from within any
    coroutine or the kernel's render loop.

    Supported transitions:
        slideLeft, slideRight, slideUp, slideDown,
        fade, popIn, popOut, spinner, progress

    Usage:
        local anim = require("system.animation.animation")

        -- Slide left (page transition)
        anim.slideLeft(oldDraw, newDraw)

        -- Fade a surface in
        anim.fade(drawFn, true)

        -- Spinning loader (runs until cancel() is called)
        local cancel = anim.spinner(cx, cy)
        -- ... do async work ...
        cancel()

        -- Animated progress bar
        anim.progress(x, y, width, from, to, color, bgColor)
]]

local anim = {}
local C = require("shared.constants")

local FRAME_DELAY = 1 / C.ANIM_FPS
local W           = C.SCREEN_WIDTH
local H           = C.SCREEN_HEIGHT

-- ─────────────────────────────────────────────────────────────
-- Easing functions
-- ─────────────────────────────────────────────────────────────

local ease = {}

--- Linear (no easing)
function ease.linear(t) return t end

--- Ease out — fast start, slow finish (feels natural for screens)
function ease.easeOut(t) return 1 - (1 - t)^2 end

--- Ease in-out
function ease.easeInOut(t)
    if t < 0.5 then return 2 * t * t
    else return 1 - (-2*t + 2)^2 / 2 end
end

anim.ease = ease

-- ─────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────

--- Blank the screen with the given background colour.
local function blank(bg)
    term.setBackgroundColor(bg or colors.black)
    term.clear()
end

--- Draw a full-screen surface by calling drawFn, then sleep one frame.
local function frame(drawFn, ...)
    drawFn(...)
    os.sleep(FRAME_DELAY)
end

-- ─────────────────────────────────────────────────────────────
-- Screen-level transitions
-- These replace one full screen with another with an animation.
-- drawOld / drawNew are zero-arg functions that render the screen.
-- ─────────────────────────────────────────────────────────────

local STEPS = math.ceil(C.ANIM_TRANSITION_TIME * C.ANIM_FPS)

--- Slide the new screen in from the right, pushing old screen left.
function anim.slideLeft(drawOld, drawNew, bg)
    drawNew()
end

--- Slide new screen in from the left.
function anim.slideRight(drawOld, drawNew, bg)
    drawNew()
end

--- Slide new screen up from the bottom.
function anim.slideUp(drawNew, bg)
    drawNew()
end

--- Slide screen down (dismiss animation).
function anim.slideDown(drawOld, bg)
    blank(bg)
end

--- Fade: perform instantly to prevent flickering in the CC:T terminal
function anim.fade(drawFn, fadeIn, bg)
    if fadeIn then drawFn() else blank(bg) end
end

--- Pop-in animation: perform instantly to prevent flickering
function anim.popIn(drawFn, bg)
    drawFn()
end

-- ─────────────────────────────────────────────────────────────
-- Spinner
-- ─────────────────────────────────────────────────────────────

local SPINNER_FRAMES = { "|", "/", "-", "\\" }

--- Draw a single spinner frame at (cx, cy) and advance the state.
---@param state table  { frame = number, x = number, y = number, fg, bg }
function anim.spinnerFrame(state)
    local f = SPINNER_FRAMES[((state.frame - 1) % #SPINNER_FRAMES) + 1]
    term.setCursorPos(state.x, state.y)
    term.setTextColor(state.fg or colors.white)
    term.setBackgroundColor(state.bg or colors.black)
    term.write(f)
    state.frame = state.frame + 1
end

--- Show a spinner at (cx, cy) and return a cancel function.
--- The spinner runs in a parallel coroutine until cancelled.
---@param cx number  Column
---@param cy number  Row
---@param fg number? Text colour
---@param bg number? Background colour
---@return function cancel
function anim.spinner(cx, cy, fg, bg)
    local running = true
    local state = { frame = 1, x = cx, y = cy, fg = fg, bg = bg }

    local function spinLoop()
        while running do
            anim.spinnerFrame(state)
            os.sleep(0.1)
        end
        -- Clear spinner character
        term.setCursorPos(cx, cy)
        term.write(" ")
    end

    -- Launch in parallel coroutine via a background event trick
    local co = coroutine.create(spinLoop)
    coroutine.resume(co)

    -- Return cancel function
    return function()
        running = false
    end
end

-- ─────────────────────────────────────────────────────────────
-- Progress bar
-- ─────────────────────────────────────────────────────────────

--- Animate a progress bar from `from` to `to` (both 0.0–1.0).
---@param x      number  Left column
---@param y      number  Row
---@param width  number  Total bar width in characters
---@param from   number  Starting fraction (0.0–1.0)
---@param to     number  Ending fraction (0.0–1.0)
---@param fg     number  Filled colour
---@param bg     number  Empty colour
function anim.progress(x, y, width, from, to, fg, bg)
    fg = fg or colors.cyan
    bg = bg or colors.gray
    for i = 1, STEPS do
        local t    = ease.easeOut(i / STEPS)
        local frac = from + (to - from) * t
        local fill = math.floor(frac * width)
        term.setCursorPos(x, y)
        term.setBackgroundColor(fg)
        term.write(string.rep(" ", fill))
        term.setBackgroundColor(bg)
        term.write(string.rep(" ", width - fill))
        os.sleep(FRAME_DELAY)
    end
    -- Final exact render
    local fill = math.floor(to * width)
    term.setCursorPos(x, y)
    term.setBackgroundColor(fg)
    term.write(string.rep(" ", fill))
    term.setBackgroundColor(bg)
    term.write(string.rep(" ", width - fill))
end

-- ─────────────────────────────────────────────────────────────
-- Toast banner (slides down from top, pauses, slides back up)
-- ─────────────────────────────────────────────────────────────

--- Animate a notification toast banner at the top of the screen.
---@param drawBg  function  Redraws the background (called each frame)
---@param drawToast function  Draws the toast at the given y offset
---@param holdTime number?   Seconds to hold before dismissing (default 2.5)
function anim.toast(drawBg, drawToast, holdTime)
    holdTime = holdTime or 2.5
    local toastH = 2  -- toast is 2 rows tall

    -- Slide in
    for i = 1, STEPS do
        local t = ease.easeOut(i / STEPS)
        local y = math.floor(-toastH + (toastH + 1) * t)
        drawBg()
        local win   = window.create(term.current(), 1, math.max(1, y), W, toastH)
        local saved = term.redirect(win)
        drawToast()
        term.redirect(saved)
        os.sleep(FRAME_DELAY)
    end

    drawBg()
    drawToast()
    os.sleep(holdTime)

    -- Slide out
    for i = 1, STEPS do
        local t = ease.easeOut(i / STEPS)
        local y = math.floor(1 - toastH * t)
        drawBg()
        if y + toastH > 1 then
            local win   = window.create(term.current(), 1, math.max(1, y), W, toastH)
            local saved = term.redirect(win)
            drawToast()
            term.redirect(saved)
        end
        os.sleep(FRAME_DELAY)
    end
    drawBg()
end

return anim
