-- Fish & Partners: terminal widget kit (no templates, texture-only so it works on any client)

local _, ns = ...
local UI = {}
ns.UI = UI
local C = ns.C

UI.FONT      = "Fonts\\ARIALN.TTF"
UI.FONT_HEAD = "Fonts\\FRIZQT__.TTF"

function UI.Fill(frame, color, alpha, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    return t
end

function UI.Border(frame, color, alpha)
    color = color or C.line
    local function edge()
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(color[1], color[2], color[3], alpha or 1)
        return t
    end
    local top, bot, left, right = edge(), edge(), edge(), edge()
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
    bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(1)
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(1)
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
    frame.borders = { top, bot, left, right }
end

function UI.SetBorderColor(frame, color)
    if not frame.borders then return end
    for _, t in ipairs(frame.borders) do t:SetColorTexture(color[1], color[2], color[3], 1) end
end

function UI.Panel(parent, color, withBorder)
    local f = CreateFrame("Frame", nil, parent)
    f.bg = UI.Fill(f, color or C.panel, 1)
    if withBorder ~= false then UI.Border(f) end
    return f
end

function UI.Text(parent, size, color, justify, font, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(font or UI.FONT, size or 12, flags or "")
    color = color or C.white
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

function UI.HLine(parent, color)
    local t = parent:CreateTexture(nil, "ARTWORK")
    color = color or C.line
    t:SetColorTexture(color[1], color[2], color[3], 1)
    t:SetHeight(1)
    return t
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local STYLES = {
    primary = { bg = C.orange, hover = C.amber, text = { 0, 0, 0 } },
    default = { bg = C.panel2, hover = { 0.16, 0.16, 0.2 }, text = C.amber },
    danger  = { bg = { 0.35, 0.06, 0.06 }, hover = { 0.55, 0.1, 0.1 }, text = C.white },
    go      = { bg = { 0.05, 0.32, 0.22 }, hover = { 0.08, 0.45, 0.3 }, text = C.green },
}

function UI.Button(parent, text, w, h, style)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 100, h or 22)
    b.bg = UI.Fill(b, C.panel2, 1, "BACKGROUND")
    UI.Border(b, C.line)
    local fs = UI.Text(b, 11, C.amber, "CENTER", UI.FONT, "")
    fs:SetPoint("CENTER", 0, 0)
    b:SetFontString(fs)
    b.label = fs
    function b:SetStyle(s)
        self.style = STYLES[s] or STYLES.default
        local st = self.style
        self.bg:SetColorTexture(st.bg[1], st.bg[2], st.bg[3], 1)
        self.label:SetTextColor(st.text[1], st.text[2], st.text[3])
    end
    b:SetScript("OnEnter", function(self)
        local st = self.style
        self.bg:SetColorTexture(st.hover[1], st.hover[2], st.hover[3], 1)
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        local st = self.style
        self.bg:SetColorTexture(st.bg[1], st.bg[2], st.bg[3], 1)
        GameTooltip:Hide()
    end)
    b:SetStyle(style or "default")
    b:SetText(text or "")
    return b
end

-- Segmented selector: options = { {value, label}, ... }
function UI.Segment(parent, options, onSelect, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f.buttons = {}
    local x = 0
    for i, opt in ipairs(options) do
        local b = UI.Button(f, opt[2], w or 52, h or 18, "default")
        b.label:SetFont(UI.FONT, 10, "")
        b:SetPoint("LEFT", f, "LEFT", x, 0)
        x = x + (w or 52) - 1
        b.value = opt[1]
        b:SetScript("OnClick", function() f:Select(opt[1]); onSelect(opt[1]) end)
        f.buttons[i] = b
    end
    f:SetSize(x + 1, h or 18)
    function f:Select(v)
        self.value = v
        for _, b in ipairs(self.buttons) do b:SetStyle(b.value == v and "primary" or "default") end
    end
    return f
end

---------------------------------------------------------------------------
-- KPI tile
---------------------------------------------------------------------------
function UI.KPI(parent, label, w, h, bigSize)
    local f = UI.Panel(parent, C.panel)
    f:SetSize(w, h)
    local accent = f:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(C.orange[1], C.orange[2], C.orange[3], 1)
    accent:SetPoint("TOPLEFT", 1, -1); accent:SetPoint("BOTTOMLEFT", 1, 1); accent:SetWidth(2)
    f.accent = accent
    f.label = UI.Text(f, 9, C.grey)
    f.label:SetPoint("TOPLEFT", 9, -6)
    f.label:SetText(label:upper())
    f.value = UI.Text(f, bigSize or 17, C.white, "LEFT", UI.FONT, "")
    f.value:SetPoint("TOPLEFT", 9, -19)
    f.value:SetPoint("RIGHT", -6, 0)
    f.sub = UI.Text(f, 9, C.grey)
    f.sub:SetPoint("BOTTOMLEFT", 9, 6)
    f.sub:SetPoint("RIGHT", -6, 0)
    return f
end

---------------------------------------------------------------------------
-- Section header ("> HOLDINGS ---------------")
---------------------------------------------------------------------------
function UI.Section(parent, title, right)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(16)
    local t = UI.Text(f, 10, C.orange, "LEFT", UI.FONT, "")
    t:SetPoint("LEFT", 0, 0)
    t:SetText(title:upper())
    local l = UI.HLine(f, C.dim)
    l:SetPoint("LEFT", t, "RIGHT", 6, 0)
    l:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.title = t
    if right then
        local r = UI.Text(f, 9, C.grey, "RIGHT")
        r:SetPoint("RIGHT", 0, 0)
        l:SetPoint("RIGHT", r, "LEFT", -6, 0)
        f.right = r
    end
    return f
end

---------------------------------------------------------------------------
-- Scrolling data table
-- cols = { {title=, width=, justify=}, ... }
-- data rows = { cells = {...strings}, link = itemLink?, tooltip = fn(tt)?, onClick = fn(button)? }
---------------------------------------------------------------------------
function UI.Table(parent, cols, width, height, rowH)
    rowH = rowH or 16
    local f = UI.Panel(parent, C.panel)
    f:SetSize(width, height)
    local headerH = 18
    local numRows = math.floor((height - headerH - 2) / rowH)
    f.offset, f.data, f.rows = 0, {}, {}

    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1); head:SetHeight(headerH)
    UI.Fill(head, C.panel2, 1)
    local hl = UI.HLine(head, C.orange); hl:SetPoint("BOTTOMLEFT"); hl:SetPoint("BOTTOMRIGHT")

    local function layoutCells(row, isHeader)
        local x = 6
        row.cells = {}
        for i, col in ipairs(cols) do
            local fs = UI.Text(row, isHeader and 9 or 11, isHeader and C.orange or C.white, col.justify or "LEFT")
            fs:SetPoint("LEFT", row, "LEFT", x, 0)
            fs:SetWidth(col.width - 6)
            row.cells[i] = fs
            x = x + col.width
        end
    end
    layoutCells(head, true)
    for i, col in ipairs(cols) do head.cells[i]:SetText(col.title:upper()) end

    for r = 1, numRows do
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(rowH)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -(headerH + 1 + (r - 1) * rowH))
        row:SetPoint("RIGHT", f, "RIGHT", -6, 0)
        row.stripe = UI.Fill(row, C.white, (r % 2 == 0) and 0.025 or 0, "BACKGROUND")
        row.stripeA = (r % 2 == 0) and 0.025 or 0
        row.hl = UI.Fill(row, C.orange, 0, "ARTWORK")
        layoutCells(row, false)
        row:RegisterForClicks("AnyUp")
        row:SetScript("OnEnter", function(self)
            self.hl:SetColorTexture(C.orange[1], C.orange[2], C.orange[3], 0.12)
            local d = self.item
            if not d then return end
            if d.tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                d.tooltip(GameTooltip)
                GameTooltip:Show()
            elseif d.link and d.link:find("|H") then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, d.link)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self.hl:SetColorTexture(C.orange[1], C.orange[2], C.orange[3], 0)
            GameTooltip:Hide()
        end)
        row:SetScript("OnClick", function(self, button)
            if self.item and self.item.onClick then self.item.onClick(button) end
            if self.item and self.item.link and IsModifiedClick and IsModifiedClick("CHATLINK") then
                ChatEdit_InsertLink(self.item.link)
            end
        end)
        f.rows[r] = row
    end

    local track = f:CreateTexture(nil, "ARTWORK")
    track:SetColorTexture(1, 1, 1, 0.04)
    track:SetPoint("TOPRIGHT", -2, -(headerH + 2)); track:SetPoint("BOTTOMRIGHT", -2, 2); track:SetWidth(3)
    local thumb = f:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(C.orange[1], C.orange[2], C.orange[3], 0.7)
    thumb:SetWidth(3)
    f.track, f.thumb = track, thumb

    f.empty = UI.Text(f, 11, C.dim, "CENTER")
    f.empty:SetPoint("CENTER", 0, -8)

    function f:Render()
        local total = #self.data
        local maxOff = math.max(0, total - numRows)
        if self.offset > maxOff then self.offset = maxOff end
        for r = 1, numRows do
            local row, d = self.rows[r], self.data[r + self.offset]
            row.item = d
            if d and d.selected then
                row.stripe:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], 0.22)
            elseif d and d.header then
                row.stripe:SetColorTexture(C.orange[1], C.orange[2], C.orange[3], 0.10)
            else
                row.stripe:SetColorTexture(C.white[1], C.white[2], C.white[3], row.stripeA)
            end
            if d then
                for i = 1, #cols do row.cells[i]:SetText(d.cells[i] or "") end
                row:Show()
            else
                row:Hide()
            end
        end
        if total > numRows then
            local trackH = height - headerH - 4
            local th = math.max(12, trackH * numRows / total)
            thumb:SetHeight(th)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", -2, -(headerH + 2) - (trackH - th) * (self.offset / maxOff))
            thumb:Show(); track:Show()
        else
            thumb:Hide(); track:Hide()
        end
        self.empty:SetShown(total == 0)
    end
    function f:SetData(data, keepOffset)
        self.data = data or {}
        if not keepOffset then self.offset = 0 end
        self:Render()
    end
    function f:SetEmptyText(t) self.empty:SetText(t) end

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        self.offset = math.max(0, self.offset - delta * (IsShiftKeyDown() and numRows or 3))
        self:Render()
    end)
    return f
end

---------------------------------------------------------------------------
-- Bar chart (supports negatives). values = { {v=number, label=string}, ... }
---------------------------------------------------------------------------
function UI.BarChart(parent, width, height)
    local f = UI.Panel(parent, C.panel)
    f:SetSize(width, height)
    local padL, padR, padT, padB = 52, 8, 10, 16
    local plotW, plotH = width - padL - padR, height - padT - padB
    f.bars = {}

    -- grid lines
    for i = 0, 3 do
        local g = f:CreateTexture(nil, "BORDER")
        g:SetColorTexture(1, 1, 1, 0.04)
        g:SetHeight(1)
        g:SetPoint("TOPLEFT", padL, -padT - plotH * i / 3)
        g:SetPoint("RIGHT", -padR, 0)
    end
    f.zero = f:CreateTexture(nil, "ARTWORK")
    f.zero:SetColorTexture(C.grey[1], C.grey[2], C.grey[3], 0.6)
    f.zero:SetHeight(1)

    f.maxLabel = UI.Text(f, 9, C.grey, "RIGHT"); f.maxLabel:SetWidth(padL - 6)
    f.maxLabel:SetPoint("TOPRIGHT", f, "TOPLEFT", padL - 4, -padT + 5)
    f.minLabel = UI.Text(f, 9, C.grey, "RIGHT"); f.minLabel:SetWidth(padL - 6)
    f.minLabel:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", padL - 4, padB - 5)
    f.leftLabel = UI.Text(f, 9, C.dim, "LEFT"); f.leftLabel:SetPoint("BOTTOMLEFT", padL, 3)
    f.rightLabel = UI.Text(f, 9, C.dim, "RIGHT"); f.rightLabel:SetPoint("BOTTOMRIGHT", -padR, 3)
    f.title = UI.Text(f, 9, C.orange, "LEFT"); f.title:SetPoint("TOPLEFT", padL, -1)
    f.empty = UI.Text(f, 11, C.dim, "CENTER"); f.empty:SetPoint("CENTER")

    local function getBar(i)
        local b = f.bars[i]
        if b then return b end
        b = CreateFrame("Frame", nil, f)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
            self.tex:SetAlpha(1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.label or "", 1, 0.55, 0.12)
            GameTooltip:AddLine(ns.Money(self.v or 0), 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self) self.tex:SetAlpha(0.85); GameTooltip:Hide() end)
        f.bars[i] = b
        return b
    end

    function f:SetData(values, leftText, rightText, colorMode)
        for _, b in ipairs(self.bars) do b:Hide() end
        local n = #values
        self.empty:SetShown(n == 0)
        self.leftLabel:SetText(leftText or "")
        self.rightLabel:SetText(rightText or "")
        if n == 0 then self.maxLabel:SetText(""); self.minLabel:SetText(""); self.zero:Hide(); return end
        local maxV, minV = 0, 0
        for _, d in ipairs(values) do
            if d.v > maxV then maxV = d.v end
            if d.v < minV then minV = d.v end
        end
        if maxV == minV then maxV = minV + 1 end
        local range = maxV - minV
        local zeroY = plotH * (0 - minV) / range
        self.zero:ClearAllPoints()
        self.zero:SetPoint("BOTTOMLEFT", padL, padB + zeroY)
        self.zero:SetPoint("RIGHT", -padR, 0)
        self.zero:Show()
        self.maxLabel:SetText(ns.MoneyShort(maxV))
        self.minLabel:SetText(ns.MoneyShort(minV))
        local slot = plotW / n
        local bw = math.max(1, math.min(18, slot - 2))
        for i, d in ipairs(values) do
            local b = getBar(i)
            local h = math.max(1, plotH * math.abs(d.v) / range)
            b:ClearAllPoints()
            b:SetSize(bw, h)
            local x = padL + (i - 1) * slot + (slot - bw) / 2
            if d.v >= 0 then
                b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, padB + zeroY)
            else
                b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", x, padB + zeroY)
            end
            local col = d.v >= 0 and C.green or C.red
            if colorMode == "orange" then col = (i == n) and C.amber or C.orange end
            b.tex:SetColorTexture(col[1], col[2], col[3], 1)
            b.tex:SetAlpha(0.85)
            b.v, b.label = d.v, d.label
            b:Show()
        end
    end
    return f
end

---------------------------------------------------------------------------
-- Settings controls
---------------------------------------------------------------------------
function UI.Toggle(parent, label, get, set, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 320, 20)
    local box = UI.Panel(b, C.panel2)
    box:SetSize(14, 14); box:SetPoint("LEFT", 0, 0)
    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 3, -3); fill:SetPoint("BOTTOMRIGHT", -3, 3)
    local txt = UI.Text(b, 11, C.white); txt:SetPoint("LEFT", box, "RIGHT", 8, 0); txt:SetText(label)
    local state = UI.Text(b, 10, C.grey, "RIGHT"); state:SetPoint("RIGHT", 0, 0)
    function b:Refresh()
        local on = get()
        if on then fill:SetColorTexture(C.green[1], C.green[2], C.green[3], 1) else fill:SetColorTexture(0, 0, 0, 0) end
        state:SetText(on and ns.Color("green", "ON") or ns.Color("dim", "OFF"))
    end
    b:SetScript("OnClick", function(self) set(not get()); self:Refresh() end)
    b:Refresh()
    return b
end

function UI.Stepper(parent, label, get, set, minV, maxV, step, fmt, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 320, 20)
    local txt = UI.Text(f, 11, C.white); txt:SetPoint("LEFT", 0, 0); txt:SetText(label)
    local plus = UI.Button(f, "+", 20, 18); plus:SetPoint("RIGHT", 0, 0)
    local val = UI.Text(f, 12, C.amber, "CENTER"); val:SetWidth(52); val:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    local minus = UI.Button(f, "-", 20, 18); minus:SetPoint("RIGHT", val, "LEFT", -2, 0)
    function f:Refresh() val:SetText(fmt and fmt(get()) or tostring(get())) end
    local function bump(d)
        local mult = IsShiftKeyDown() and 5 or 1
        local v = get() + d * step * mult
        v = math.max(minV, math.min(maxV, math.floor(v / step + 0.5) * step))
        set(v); f:Refresh()
    end
    plus:SetScript("OnClick", function() bump(1) end)
    minus:SetScript("OnClick", function() bump(-1) end)
    f:Refresh()
    return f
end

-- Confirm dialog helper
function UI.Confirm(text, onAccept)
    StaticPopupDialogs["FISHPARTNERS_CONFIRM"] = {
        text = text, button1 = YES or "Yes", button2 = NO or "No",
        OnAccept = onAccept, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("FISHPARTNERS_CONFIRM")
end
