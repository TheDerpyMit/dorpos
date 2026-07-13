--[[  DorpOS :: phone/system/animation/animation.lua
    Animation module — all transitions are instant (no-op).
    Animations removed per user request for maximum performance.
]]

local anim = {}
local C = require("shared.constants")

local W = C.SCREEN_WIDTH
local H = C.SCREEN_HEIGHT

-- Easing stubs (kept so require() callers don't crash)
local ease = {}
function ease.linear(t)    return t end
function ease.easeOut(t)   return t end
function ease.easeInOut(t) return t end
anim.ease = ease

-- ── Transitions — all instant, just draw the new screen ──────

function anim.slideLeft(drawOld, drawNew, bg)
    if drawNew then drawNew() end
end

function anim.slideRight(drawOld, drawNew, bg)
    if drawNew then drawNew() end
end

function anim.slideUp(drawNew, bg)
    if drawNew then drawNew() end
end

function anim.slideDown(drawOld, bg)
    -- nothing to draw
end

function anim.fade(drawFn, fadeIn, bg)
    if drawFn then drawFn() end
end

function anim.popIn(drawFn, bg)
    if drawFn then drawFn() end
end

-- ── Spinner — draw one static frame, return a no-op cancel ───

local SPINNER_FRAMES = { "|", "/", "-", "\\" }

function anim.spinnerFrame(state)
    local f = SPINNER_FRAMES[((state.frame - 1) % #SPINNER_FRAMES) + 1]
    term.setCursorPos(state.x, state.y)
    term.setTextColor(state.fg or colors.white)
    term.setBackgroundColor(state.bg or colors.black)
    term.write(f)
    state.frame = state.frame + 1
end

function anim.spinner(cx, cy, fg, bg)
    -- Draw a static indicator and return a no-op cancel
    term.setCursorPos(cx, cy)
    term.setTextColor(fg or colors.white)
    term.setBackgroundColor(bg or colors.black)
    term.write("/")
    return function()
        term.setCursorPos(cx, cy)
        term.write(" ")
    end
end

-- ── Progress bar — draw final state instantly ─────────────────

function anim.progress(x, y, width, from, to, fg, bg)
    fg = fg or colors.cyan
    bg = bg or colors.gray
    local fill = math.floor(to * width)
    term.setCursorPos(x, y)
    term.setBackgroundColor(fg)
    term.write(string.rep(" ", fill))
    term.setBackgroundColor(bg)
    term.write(string.rep(" ", width - fill))
end

-- ── Toast — show instantly, hold briefly, then clear ─────────
-- holdTime is ignored (was 2.5s before, now ~0)

function anim.toast(drawBg, drawToast, holdTime)
    if drawToast then drawToast() end
    os.sleep(1.5)   -- short pause so user can read it, then clear
    if drawBg then drawBg() end
end

return anim
