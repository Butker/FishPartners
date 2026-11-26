-- Fish & Partners: mini session window ("HUD")
-- A small, movable window with the essentials of the Intraday P&L page, so you can
-- keep an eye on the session while you play. Opens when a session starts.

local _, ns = ...
local UI, C = ns.UI, ns.C
local H = {}
ns.HUD = H

local W, HGT = 250, 186
local LINES = 4
local LINE_H = 13
local MIN_SCALE, MAX_SCALE = 0.6, 2.5
local f

local function sess() return ns.cdb and ns.cdb.session end

local function SavePos()
    local p, _, rp, x, y = f:GetPoint()
    ns.db.hud = { p = p, rp = rp, x = x, y = y }
end

-- Pin the window by its top-left corner (in screen space) so scaling grows it down/right
local function anchorTopLeft(screenLeft, screenTop)
    local eff = f:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", screenLeft / eff, screenTop / eff)
end

local function smallButton(parent, text, w, style)
    local b = UI.Button(parent, text, w, 18, style)
    b.label:SetFont(UI.FONT, 10, "")
    return b
end

local function build()
    f = CreateFrame("Frame", "FishPartnersHUD", UIParent)
    f:SetSize(W, HGT)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePos() end)
    local pos = ns.db.hud
    if pos and pos.p then f:SetPoint(pos.p, UIParent, pos.rp, pos.x, pos.y) else f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120) end
    UI.Fill(f, C.bg, 0.9)
    UI.Border(f, C.orange)

    -- header
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1); head:SetHeight(18)
    UI.Fill(head, { 0, 0, 0 }, 1)
    local title = UI.Text(head, 10, C.orange, "LEFT", UI.FONT, "")
    title:SetPoint("LEFT", 6, 0); title:SetText("F&P · INTRADAY P&L")
    f.dot = head:CreateTexture(nil, "OVERLAY")
    f.dot:SetSize(6, 6)
    f.state = UI.Text(head, 9, C.green, "RIGHT", UI.FONT, "")
    local close = smallButton(head, "x", 16, "default")
    close:SetHeight(14)
    close:SetPoint("RIGHT", -2, 0)
    close.tip = "Hide the mini window (the session keeps running).\nBring it back with /fpwm hud."
    close:SetScript("OnClick", function() H:Hide(true) end)
    f.state:SetPoint("RIGHT", close, "LEFT", -6, 0)
    f.dot:SetPoint("RIGHT", f.state, "LEFT", -4, 0)

    -- clock + gold/hour
    f.clock = UI.Text(f, 22, C.amber, "LEFT", UI.FONT, "")
    f.clock:SetPoint("TOPLEFT", 8, -24)
    local cl = UI.Text(f, 8, C.grey); cl:SetPoint("TOPLEFT", f.clock, "BOTTOMLEFT", 0, 0); cl:SetText("MARKET OPEN FOR")
    f.gph = UI.Text(f, 16, C.green, "RIGHT", UI.FONT, "")
    f.gph:SetPoint("TOPRIGHT", -8, -26)
    local gl = UI.Text(f, 8, C.grey, "RIGHT"); gl:SetPoint("TOPRIGHT", f.gph, "BOTTOMRIGHT", 0, -2); gl:SetText("GOLD / HOUR")

    -- P&L row
    local sep1 = UI.HLine(f, C.dim); sep1:SetPoint("TOPLEFT", 8, -62); sep1:SetPoint("TOPRIGHT", -8, -62)
    f.total = UI.Text(f, 14, C.white, "LEFT", UI.FONT, "")
    f.total:SetPoint("TOPLEFT", 8, -67)
    f.split = UI.Text(f, 9, C.grey, "RIGHT")
    f.split:SetPoint("TOPRIGHT", -8, -70)

    -- latest loot
    local sep2 = UI.HLine(f, C.dim); sep2:SetPoint("TOPLEFT", 8, -88); sep2:SetPoint("TOPRIGHT", -8, -88)
    local ll = UI.Text(f, 8, C.orange); ll:SetPoint("TOPLEFT", 8, -92); ll:SetText("LATEST FILLS")
    f.fillsLabel = ll
    f.lines = {}
    for i = 1, LINES do
        local y = -104 - (i - 1) * LINE_H
        local name = UI.Text(f, 10, C.white, "LEFT")
        name:SetPoint("TOPLEFT", 8, y); name:SetWidth(170)
        local val = UI.Text(f, 10, C.white, "RIGHT")
        val:SetPoint("TOPRIGHT", -8, y); val:SetWidth(64)
        f.lines[i] = { name = name, val = val }
    end

    -- buttons
    f.pause = smallButton(f, "PAUSE", 76, "default")
    f.pause:SetPoint("BOTTOMLEFT", 8, 7)
    f.pause:SetScript("OnClick", function() ns.Session:ToggleStartPause(); H:Refresh() end)
    f.open = smallButton(f, "TERMINAL", 76, "default")
    f.open:SetPoint("LEFT", f.pause, "RIGHT", 4, 0)
    f.open.tip = "Open the full Intraday P&L page"
    f.open:SetScript("OnClick", function() ns:ShowPage("pnl") end)
    f.stop = smallButton(f, "BOOK", 74, "primary")
    f.stop:SetPoint("LEFT", f.open, "RIGHT", 4, 0)
    f.stop.tip = "Stop the session and book it to your archive"
    f.stop:SetScript("OnClick", function() ns.Session:Stop() end)

    -- scale grip (bottom-right): drag to zoom the whole window, text included
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(f:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:RegisterForClicks("RightButtonUp")
    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local eff = f:GetEffectiveScale()
        local left, top = f:GetLeft() * eff, f:GetTop() * eff
        local startX, startY = GetCursorPosition()
        local startW, startH = W * eff, HGT * eff        -- current on-screen size in pixels
        local parentEff = f:GetEffectiveScale() / f:GetScale()
        self.sizing = true
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            -- keep aspect ratio: follow whichever direction you dragged further
            local fx = (startW + (x - startX)) / startW
            local fy = (startH + (startY - y)) / startH
            local factor = (math.abs(fx - 1) >= math.abs(fy - 1)) and fx or fy
            local newScale = (startW * factor) / (W * parentEff)
            newScale = math.max(MIN_SCALE, math.min(MAX_SCALE, newScale))
            f:SetScale(newScale)
            anchorTopLeft(left, top)
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        if not self.sizing then return end
        self.sizing = false
        self:SetScript("OnUpdate", nil)
        ns.S.hudScale = math.floor(f:GetScale() * 100 + 0.5) / 100
        SavePos()
    end)
    grip:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            local eff = f:GetEffectiveScale()
            local left, top = f:GetLeft() * eff, f:GetTop() * eff
            f:SetScale(1)
            ns.S.hudScale = 1
            anchorTopLeft(left, top)
            SavePos()
        end
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Drag to scale\nRight-click: reset to 100%", 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.grip = grip

    f:SetScale(ns.S.hudScale or 1)
    f:Hide()
end

function H:Refresh()
    if not f or not f:IsShown() then return end
    local st = ns.Session:Stats()
    local s = sess()

    if not st.active then
        f.state:SetText("CLOSED"); f.state:SetTextColor(C.grey[1], C.grey[2], C.grey[3])
        f.dot:SetColorTexture(C.grey[1], C.grey[2], C.grey[3], 1)
        f.clock:SetText(ns.Color("dim", "00:00:00"))
        f.pause:SetText("START"); f.pause:SetStyle("go")
        f.stop:SetAlpha(0.4); f.stop:SetEnabled(false)
    elseif st.paused then
        f.state:SetText("HALTED"); f.state:SetTextColor(C.amber[1], C.amber[2], C.amber[3])
        f.dot:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], 1)
        f.clock:SetText(ns.Duration(st.elapsed))
        f.pause:SetText("RESUME"); f.pause:SetStyle("go")
        f.stop:SetAlpha(1); f.stop:SetEnabled(true)
    else
        f.state:SetText("OPEN"); f.state:SetTextColor(C.green[1], C.green[2], C.green[3])
        f.dot:SetColorTexture(C.green[1], C.green[2], C.green[3], 1)
        f.clock:SetText(ns.Duration(st.elapsed))
        f.pause:SetText("PAUSE"); f.pause:SetStyle("default")
        f.stop:SetAlpha(1); f.stop:SetEnabled(true)
    end

    f.gph:SetText(st.gph and ns.MoneyShort(st.gph) or ns.Color("dim", "--"))
    f.total:SetText("P&L " .. ns.PnL(st.total or 0))
    f.split:SetText("coin " .. ns.MoneyShort(st.coin or 0) .. " · quest " .. ns.MoneyShort(st.quest or 0) .. " · items " .. ns.MoneyShort(st.items or 0))

    local tape = s and s.tape or {}
    for i = 1, LINES do
        local t, l = tape[i], f.lines[i]
        if t then
            local name
            if t.coin then name = ns.Color("amber", "Coin")
            elseif t.quest then name = ns.Color("cyan", "Quest gold")
            else name = (t.reward and ns.Color("cyan", "Reward ") or "") .. (t.link or "?") .. (t.qty and t.qty > 1 and ns.Color("grey", " x" .. t.qty) or "") end
            l.name:SetText(name)
            l.val:SetText(ns.PnL(t.v or 0))
        else
            l.name:SetText(i == 1 and ns.Color("dim", st.active and "Waiting for loot…" or "Press START to open the market") or "")
            l.val:SetText("")
        end
    end
end

function H:Show()
    if not f then build() end
    local s = sess()
    if s then s.hudClosed = nil end
    f:Show()
    self:Refresh()
end

function H:Hide(byUser)
    if f then f:Hide() end
    local s = sess()
    if byUser and s then s.hudClosed = true end
end

function H:Toggle()
    if f and f:IsShown() then self:Hide(true) else self:Show() end
end

function H:ApplyScale()
    if not f then return end
    local eff = f:GetEffectiveScale()
    local left, top = f:GetLeft(), f:GetTop()
    f:SetScale(ns.S.hudScale or 1)
    if left and top then anchorTopLeft(left * eff, top * eff); SavePos() end
end

-- Open automatically when a session starts (unless you closed it for this session)
local wasActive
ns:Listen("SESSION_UPDATE", function()
    local s = sess()
    local active = s and s.active or false
    if active and not wasActive and ns.S.hudAuto and not s.hudClosed then H:Show() end
    wasActive = active
    H:Refresh()
end)

ns:OnInit(function()
    local s = sess()
    wasActive = s and s.active or false
    if wasActive and ns.S.hudAuto and not s.hudClosed then
        C_Timer.After(1, function() H:Show() end)
    end
    C_Timer.NewTicker(1, function() H:Refresh() end)
end)
