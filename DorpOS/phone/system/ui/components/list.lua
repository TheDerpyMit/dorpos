--[[  DorpOS :: system/ui/components/list.lua
    Scrollable item list.

    Props:
        x, y        number
        width       number
        height      number
        items       table    Array of strings or { label, sublabel, icon, id }
        selected    number?  1-based selected index
        scroll      number?  1-based first visible index (managed by caller)
        onSelect    function Called with (index, item) on click
        showIndex   boolean? Show item numbers (default false)
        itemHeight  number?  Rows per item (default 1)
        bg          number?  List background
        selBg       number?  Selected item background
        selFg       number?  Selected item text
]]
local M = {}
local Theme = require("system.theme.theme")
local utils = require("system.utils.utils")

function M.draw(props)
    local t   = Theme.get()
    local x   = props.x      or 1
    local y   = props.y      or 1
    local w   = props.width  or 26
    local h   = props.height or 10
    local ih  = props.itemHeight or 1
    local items   = props.items   or {}
    local scroll  = props.scroll  or 1
    local selIdx  = props.selected

    local bg    = props.bg    or t.bg
    local selBg = props.selBg or t.accent
    local selFg = props.selFg or t.textOnAccent

    -- Hit areas returned for click handling
    local hits = {}

    local row = y
    for i = scroll, #items do
        if row + ih - 1 > y + h - 1 then break end

        local item = items[i]
        local label, sublabel, icon
        if type(item) == "string" then
            label = item
        else
            label    = item.label    or tostring(i)
            sublabel = item.sublabel
            icon     = item.icon
        end

        local isSel = (i == selIdx)
        local ibg   = isSel and selBg or bg
        local ifg   = isSel and selFg or t.text

        -- Fill row background
        term.setBackgroundColor(ibg)
        term.setTextColor(ifg)
        for dr = 0, ih - 1 do
            term.setCursorPos(x, row + dr)
            term.write(string.rep(" ", w))
        end

        -- Icon
        local textX = x + 1
        if icon then
            term.setCursorPos(x + 1, row)
            term.write(icon .. " ")
            textX = x + 3
        end

        -- Label
        local prefix = props.showIndex and (i .. ". ") or ""
        local avail  = w - (textX - x) - 1
        term.setCursorPos(textX, row)
        term.write(utils.truncate(prefix .. label, avail))

        -- Sublabel (row below, muted)
        if sublabel and ih >= 2 then
            term.setCursorPos(textX, row + 1)
            term.setTextColor(isSel and selFg or t.textMuted)
            term.write(utils.truncate(sublabel, avail))
        end

        -- Bottom divider
        if not isSel then
            term.setCursorPos(x, row + ih - 1)
            term.setBackgroundColor(ibg)
            term.setTextColor(t.border)
        end

        -- Store hit area
        local ri = i
        table.insert(hits, {
            y1 = row, y2 = row + ih - 1,
            hit = function(mx, my)
                return mx >= x and mx < x + w and my >= row and my <= row + ih - 1
            end,
            activate = function()
                if props.onSelect then props.onSelect(ri, items[ri]) end
            end,
        })

        row = row + ih
    end

    -- Scroll indicator
    if #items > math.floor(h / ih) then
        local totalRows = #items * ih
        local visRatio  = h / totalRows
        local barH      = math.max(1, math.floor(h * visRatio))
        local barY      = y + math.floor((scroll - 1) / #items * h)
        term.setBackgroundColor(t.border)
        for r = barY, math.min(y + h - 1, barY + barH - 1) do
            term.setCursorPos(x + w - 1, r)
            term.write(" ")
        end
    end

    return hits
end

return M
