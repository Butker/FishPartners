-- Fish & Partners: Opening Bell
-- When you enter a dungeon or raid, the desk asks whether to open a trading session
-- (none running) or book the current one and open a fresh one for this venture.

local _, ns = ...
local UI, C = ns.UI, ns.C
local B = {}
ns.Bell = B

local dlg
local REENTRY_GRACE = 15 * 60 -- re-entering the same instance within 15 min (corpse run, port out) doesn't ask again

local function sess() return ns.cdb and ns.cdb.session end

local function build()
    dlg = CreateFrame("Frame", "FishPartnersBell", UIParent)
    dlg:SetSize(380, 168)
    dlg:SetPoint("TOP", 0, -150)
    dlg:SetFrameStrata("DIALOG")
    dlg:SetToplevel(true)
    dlg:EnableMouse(true)
    dlg:SetMovable(true)
    dlg:RegisterForDrag("LeftButton")
    dlg:SetScript("OnDragStart", dlg.StartMoving)
    dlg:SetScript("OnDragStop", dlg.StopMovingOrSizing)
    UI.Fill(dlg, C.bg, 0.97)
    UI.Border(dlg, C.orange)
    tinsert(UISpecialFrames, "FishPartnersBell")

    local head = UI.Panel(dlg, C.orange, false)
    head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1); head:SetHeight(20)
    dlg.kicker = UI.Text(head, 10, { 0, 0, 0 }, "LEFT", UI.FONT, "")
    dlg.kicker:SetPoint("LEFT", 8, 0)
    local brand = UI.Text(head, 9, { 0, 0, 0 }, "RIGHT"); brand:SetPoint("RIGHT", -8, 0)
    brand:SetText("FISH & PARTNERS · TRADING DESK")

    local accent = dlg:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 1, -21); accent:SetPoint("BOTTOMLEFT", 1, 1); accent:SetWidth(3)
    dlg.accent = accent

    dlg.title = UI.Text(dlg, 16, C.white, "LEFT", UI.FONT_HEAD, "")
    dlg.title:SetPoint("TOPLEFT", 14, -30); dlg.title:SetWidth(352)
    dlg.body = UI.Text(dlg, 11, C.grey, "LEFT")
    dlg.body:SetPoint("TOPLEFT", 14, -54); dlg.body:SetWidth(352)
    dlg.body:SetWordWrap(true)
    dlg.body:SetJustifyV("TOP")
    dlg.stats = UI.Text(dlg, 11, C.amber, "LEFT", UI.FONT, "")
    dlg.stats:SetPoint("TOPLEFT", 14, -100); dlg.stats:SetWidth(352)

    dlg.b1 = UI.Button(dlg, "", 128, 24, "go")
    dlg.b2 = UI.Button(dlg, "", 110, 24, "default")
    dlg.b3 = UI.Button(dlg, "", 104, 24, "default")
    dlg.b1:SetPoint("BOTTOMRIGHT", -10, 10)
    dlg.b2:SetPoint("RIGHT", dlg.b1, "LEFT", -6, 0)
    dlg.b3:SetPoint("RIGHT", dlg.b2, "LEFT", -6, 0)
    dlg:Hide()
end

local function setButton(b, text, style, tip, fn)
    if not text then b:Hide() return end
    b:SetText(text); b:SetStyle(style); b.tip = tip
    b:SetScript("OnClick", function() dlg:Hide(); if fn then fn() end end)
    b:Show()
end

function B:Ask(zone)
    if not dlg then build() end
    local st = ns.Session:Stats()
    zone = zone or "this instance"

    if not st.active then
        dlg.kicker:SetText("OPENING BELL")
        dlg.accent:SetColorTexture(C.green[1], C.green[2], C.green[3], 1)
        dlg.title:SetText("New market: " .. zone)
        dlg.body:SetText("Our analysts see opportunity in " .. zone .. ". Shall we open a trading session and start booking every coin and drop?")
        dlg.stats:SetText(ns.Color("dim", "No open positions. You are currently flat."))
        setButton(dlg.b1, "OPEN SESSION", "go", "Start a new session now", function() ns.Session:Start() end)
        setButton(dlg.b2, "STAY FLAT", "default", "Don't track this run")
        setButton(dlg.b3, nil)
    else
        dlg.kicker:SetText("PORTFOLIO REBALANCE")
        dlg.accent:SetColorTexture(C.orange[1], C.orange[2], C.orange[3], 1)
        dlg.title:SetText("New venture: " .. zone)
        dlg.body:SetText("You already have a session " .. (st.paused and "on the books (trading halted)" or "open") ..
            ". Close the books on it and open a fresh session for " .. zone .. "?")
        dlg.stats:SetText(format("%s on the clock   ·   P&L %s   ·   %s/h", ns.Duration(st.elapsed or 0), ns.PnL(st.total or 0),
            st.gph and ns.MoneyShort(st.gph) or "--"))
        setButton(dlg.b1, "BOOK & OPEN NEW", "go", "Book the current session to your archive and start a new one",
            function() ns.Session:Stop(); ns.Session:Start() end)
        if st.paused then
            setButton(dlg.b2, "RESUME CURRENT", "default", "Keep the current session and resume trading",
                function() ns.Session:TogglePause() end)
            setButton(dlg.b3, "HOLD", "default", "Do nothing")
        else
            setButton(dlg.b2, "HOLD POSITION", "default", "Keep the current session running")
            setButton(dlg.b3, nil)
        end
    end
    dlg:Show()
    if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960) end
end

---------------------------------------------------------------------------
-- Detection
---------------------------------------------------------------------------
local wasInside = false
local resetSince = false

local function instanceInfo()
    local inside, kind = IsInInstance()
    if not inside or (kind ~= "party" and kind ~= "raid") then return nil end
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    return instanceID or name, name
end

local function check(isLogin, isReload)
    if not ns.db then return end
    local id, name = instanceInfo()
    if not id then wasInside = false return end
    if wasInside then return end -- moving around inside the same instance
    wasInside = true
    if isReload or not ns.S.instanceBell then return end

    local last = ns.cdb.lastInstance
    local now = time()
    local sameRun = last and last.id == id and (now - (last.t or 0)) < REENTRY_GRACE and not resetSince
    ns.cdb.lastInstance = { id = id, t = now }
    resetSince = false
    if sameRun then return end
    -- don't nag on the login screen hand-off; give the world a moment to load
    C_Timer.After(isLogin and 4 or 1.5, function()
        if instanceInfo() then B:Ask(name or GetZoneText()) end
    end)
end

ns:On("PLAYER_ENTERING_WORLD", function(isLogin, isReload) check(isLogin, isReload) end)
ns:On("ZONE_CHANGED_NEW_AREA", function() check(false, false) end)

-- An instance reset means the next entry is a new run, even within the grace window
local resetPat
ns:On("CHAT_MSG_SYSTEM", function(msg)
    if type(msg) ~= "string" then return end
    if not resetPat then
        local fmt = _G.INSTANCE_RESET_SUCCESS or "%s has been reset."
        resetPat = "^" .. fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", ".+") .. "$"
    end
    if msg:match(resetPat) then resetSince = true end
end)

-- keep the grace timer fresh while you're inside (so a corpse run after a long pull still counts as the same run)
ns:OnInit(function()
    C_Timer.NewTicker(60, function()
        if wasInside and ns.cdb.lastInstance then ns.cdb.lastInstance.t = time() end
    end)
end)
