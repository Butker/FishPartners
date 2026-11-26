-- Fish & Partners: main terminal window

local _, ns = ...
local UI, C = ns.UI, ns.C

local W, H = 880, 580
ns.PAGE_W, ns.PAGE_H = W - 20, H - 112

local pages, pageOrder = {}, {}
local tickers = {}
local main

function ns:RegisterPage(def)
    pages[def.id] = def
    table.insert(pageOrder, def)
    table.sort(pageOrder, function(a, b) return a.order < b.order end)
end

function ns:AddTicker(fn) table.insert(tickers, fn) end

local SLOGANS = {
    "FISH & PARTNERS: YOUR GOLD, OUR HOOKS",
    "PAST LOOT IS NOT INDICATIVE OF FUTURE LOOT",
    "DIVERSIFY: ALSO KILL THE OTHER BOARS",
    "MURLOC FUTURES OPEN MIXED IN WESTFALL",
    "ANALYSTS UPGRADE LINEN CLOTH TO 'HOLD'",
    "GOBLIN CARTEL ANNOUNCES 5% AH CUT, AGAIN",
    "STRANGLETHORN PAGE SUPPLY SHOCK CONTINUES",
    "COPPER ORE RALLIES ON MINER SHORTAGE",
}

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function SavePos()
    local p, _, rp, x, y = main:GetPoint()
    ns.db.frame = { p = p, rp = rp, x = x, y = y }
end

local function BuildTicker(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(18)
    UI.Fill(bar, { 0, 0, 0 }, 1)
    local tag = UI.Panel(bar, C.orange, false)
    tag:SetPoint("TOPLEFT"); tag:SetPoint("BOTTOMLEFT"); tag:SetWidth(54)
    local tt = UI.Text(tag, 10, { 0, 0, 0 }, "CENTER", UI.FONT, "")
    tt:SetPoint("CENTER"); tt:SetText("FPWM TICK")

    local clip = CreateFrame("Frame", nil, bar)
    clip:SetPoint("TOPLEFT", tag, "TOPRIGHT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT")
    clip:SetClipsChildren(true)
    local fs = UI.Text(clip, 11, C.amber, "LEFT")
    fs:SetPoint("LEFT", clip, "LEFT", 0, 0)
    local x, slogan = 0, 1

    local function rebuild()
        local parts = {}
        for _, fn in ipairs(tickers) do
            local ok, s = pcall(fn)
            if ok and s and s ~= "" then parts[#parts + 1] = s end
        end
        slogan = slogan % #SLOGANS + 1
        parts[#parts + 1] = ns.Color("cyan", SLOGANS[slogan])
        fs:SetText(table.concat(parts, ns.Color("dim", "     |     ")))
    end
    rebuild()
    x = clip:GetWidth() or 600
    bar:SetScript("OnUpdate", function(_, elapsed)
        x = x - elapsed * (ns.S.tickerSpeed or 45)
        local tw = fs:GetStringWidth() or 0
        if x < -tw then
            rebuild()
            x = clip:GetWidth()
        end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", clip, "LEFT", x, 0)
    end)
    return bar
end

local function BuildTabs(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(24)
    bar.tabs = {}
    local x = 0
    local tw = math.floor((W - 18 - (#pageOrder - 1) * 4) / #pageOrder)
    for i, def in ipairs(pageOrder) do
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(tw, 22)
        b:SetPoint("LEFT", bar, "LEFT", x, 0)
        x = x + tw + 4
        b.bg = UI.Fill(b, C.panel2, 1)
        UI.Border(b, C.line)
        local key = UI.Panel(b, C.amber, false)
        key:SetPoint("TOPLEFT", 2, -2); key:SetPoint("BOTTOMLEFT", 2, 2); key:SetWidth(18)
        local kt = UI.Text(key, 10, { 0, 0, 0 }, "CENTER", UI.FONT, ""); kt:SetPoint("CENTER"); kt:SetText(tostring(i))
        b.code = UI.Text(b, 11, C.amber, "LEFT", UI.FONT, "")
        b.code:SetPoint("LEFT", key, "RIGHT", 6, 0)
        b.code:SetText(def.code .. (tw >= 170 and " <GO>" or ""))
        b.title = UI.Text(b, tw >= 170 and 10 or 9, C.grey, "RIGHT")
        b.title:SetPoint("RIGHT", -6, 0)
        b.title:SetText(def.title)
        b:SetScript("OnClick", function() ns:ShowPage(def.id) end)
        b:SetScript("OnEnter", function(self) if ns.currentPage ~= def.id then self.bg:SetColorTexture(0.14, 0.14, 0.18, 1) end end)
        b:SetScript("OnLeave", function() ns:UpdateTabs() end)
        b.id = def.id
        bar.tabs[i] = b
    end
    return bar
end

function ns:UpdateTabs()
    if not main then return end
    for _, b in ipairs(main.tabs.tabs) do
        local on = b.id == ns.currentPage
        if on then
            b.bg:SetColorTexture(0.98, 0.545, 0.118, 0.18)
            UI.SetBorderColor(b, C.orange)
            b.title:SetTextColor(C.white[1], C.white[2], C.white[3])
        else
            b.bg:SetColorTexture(C.panel2[1], C.panel2[2], C.panel2[3], 1)
            UI.SetBorderColor(b, C.line)
            b.title:SetTextColor(C.grey[1], C.grey[2], C.grey[3])
        end
    end
end

local COMMANDS -- forward

local function BuildStatus(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(20)
    UI.Fill(bar, { 0, 0, 0 }, 1)
    local prompt = UI.Text(bar, 11, C.orange, "LEFT", UI.FONT, "")
    prompt:SetPoint("LEFT", 8, 0)
    prompt:SetText("FPWM>")
    local eb = CreateFrame("EditBox", nil, bar)
    eb:SetFont(UI.FONT, 11, "")
    eb:SetTextColor(C.amber[1], C.amber[2], C.amber[3])
    eb:SetPoint("LEFT", prompt, "RIGHT", 6, 0)
    eb:SetSize(220, 18)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(32)
    local hint = UI.Text(bar, 10, C.dim, "LEFT")
    hint:SetPoint("LEFT", eb, "LEFT", 0, 0)
    hint:SetText("PNL AUM PORT RPT GL CMPL · START STOP HUD CHECK · HELP  <GO>")
    eb:SetScript("OnEditFocusGained", function() hint:Hide() end)
    eb:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then hint:Show() end end)
    eb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self)
        local cmd = (self:GetText() or ""):upper():gsub("<GO>", ""):gsub("%s+", "")
        self:SetText("")
        self:ClearFocus()
        local fn = COMMANDS[cmd]
        if fn then fn() else ns.Print("Unknown function |cffffc238" .. cmd .. "|r. Try HELP <GO>.") end
    end)
    bar.status = UI.Text(bar, 10, C.grey, "RIGHT")
    bar.status:SetPoint("RIGHT", -8, 0)
    return bar
end

local function BuildMain()
    main = CreateFrame("Frame", "FishPartnersFrame", UIParent)
    main:SetSize(W, H)
    main:SetFrameStrata("HIGH")
    main:SetToplevel(true)
    main:SetClampedToScreen(true)
    main:SetMovable(true)
    main:EnableMouse(true)
    main:SetScale(ns.S.scale or 1)
    local pos = ns.db.frame
    if pos and pos.p then main:SetPoint(pos.p, UIParent, pos.rp, pos.x, pos.y) else main:SetPoint("CENTER") end
    UI.Fill(main, C.bg, 0.97)
    UI.Border(main, C.orange)
    tinsert(UISpecialFrames, "FishPartnersFrame")

    -- Header (drag handle)
    local head = CreateFrame("Frame", nil, main)
    head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1); head:SetHeight(36)
    UI.Fill(head, { 0, 0, 0 }, 1)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() main:StartMoving() end)
    head:SetScript("OnDragStop", function() main:StopMovingOrSizing(); SavePos() end)

    local icon = head:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24); icon:SetPoint("LEFT", 8, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Fish_02")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local logo = UI.Text(head, 16, C.orange, "LEFT", UI.FONT_HEAD, "")
    logo:SetPoint("LEFT", icon, "RIGHT", 8, 3)
    logo:SetText("FISH & PARTNERS")
    local sub = UI.Text(head, 9, C.grey, "LEFT")
    sub:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -1)
    sub:SetText("WEALTH MANAGEMENT  ·  EST. LVL 1  ·  NOT FDIC INSURED")

    local close = UI.Button(head, "X", 24, 20, "danger")
    close:SetPoint("RIGHT", -6, 0)
    close:SetScript("OnClick", function() main:Hide() end)

    local clock = UI.Text(head, 13, C.amber, "RIGHT", UI.FONT, "")
    clock:SetPoint("RIGHT", close, "LEFT", -12, 4)
    local who = UI.Text(head, 9, C.grey, "RIGHT")
    who:SetPoint("TOPRIGHT", clock, "BOTTOMRIGHT", 0, -1)
    local live = head:CreateTexture(nil, "OVERLAY")
    live:SetSize(7, 7)
    live:SetColorTexture(C.green[1], C.green[2], C.green[3], 1)
    live:SetPoint("RIGHT", clock, "LEFT", -40, 0)
    local liveTxt = UI.Text(head, 10, C.green, "LEFT", UI.FONT, "")
    liveTxt:SetPoint("LEFT", live, "RIGHT", 4, 0)
    liveTxt:SetText("LIVE")
    local acc = 0
    head:SetScript("OnUpdate", function(_, e)
        acc = acc + e
        live:SetAlpha(0.45 + 0.55 * math.abs(math.sin(GetTime() * 2.2)))
        if acc < 0.5 then return end
        acc = 0
        clock:SetText(date("%d %b %Y  %H:%M:%S"):upper())
        who:SetText((UnitName("player") or ""):upper() .. " @ " .. (GetRealmName() or ""):upper() .. "  ·  ACCT #" .. (UnitGUID("player") or "0000"):sub(-6))
    end)

    main.ticker = BuildTicker(main)
    main.ticker:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
    main.ticker:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, 0)
    local tl = UI.HLine(main, C.line); tl:SetPoint("TOPLEFT", main.ticker, "BOTTOMLEFT"); tl:SetPoint("TOPRIGHT", main.ticker, "BOTTOMRIGHT")

    main.tabs = BuildTabs(main)
    main.tabs:SetPoint("TOPLEFT", main.ticker, "BOTTOMLEFT", 9, -8)
    main.tabs:SetPoint("RIGHT", main, "RIGHT", -9, 0)

    main.status = BuildStatus(main)
    main.status:SetPoint("BOTTOMLEFT", 1, 1); main.status:SetPoint("BOTTOMRIGHT", -1, 1)
    local sl = UI.HLine(main, C.line); sl:SetPoint("BOTTOMLEFT", main.status, "TOPLEFT"); sl:SetPoint("BOTTOMRIGHT", main.status, "TOPRIGHT")

    main.content = CreateFrame("Frame", nil, main)
    main.content:SetPoint("TOPLEFT", main.tabs, "BOTTOMLEFT", 1, -8)
    main.content:SetSize(ns.PAGE_W, ns.PAGE_H)

    main:SetScript("OnShow", function()
        local cur = ns.currentPage and pages[ns.currentPage]
        if cur and cur.frame and not cur.buildFailed then safeRefresh(cur) end
    end)
    main:Hide()
end

ns.errors = {}
local function reportError(def, err)
    err = tostring(err)
    if not ns.errors[err] then
        ns.errors[err] = true
        table.insert(ns.errors, def.code .. ": " .. err)
        ns.Print(ns.Color("red", "The " .. def.code .. " page hit an error.") .. " Type " ..
            ns.Color("amber", "/fp diag") .. " and send me the output.")
    end
    if def.frame then
        if not def.frame.errText then
            def.frame.errText = UI.Text(def.frame, 10, C.red, "LEFT")
            def.frame.errText:SetPoint("BOTTOMLEFT", 0, 0)
            def.frame.errText:SetWidth(ns.PAGE_W)
            def.frame.errText:SetWordWrap(true)
        end
        def.frame.errText:SetText("ERROR: " .. err)
    end
end

local function safeRefresh(def)
    if not (def and def.frame and def.refresh) then return end
    local ok, err = pcall(def.refresh, def.frame)
    if not ok then reportError(def, err) end
end
ns.SafeRefresh = safeRefresh

function ns:SetStatus(text)
    if main then main.status.status:SetText(text or "") end
end

function ns:ShowPage(id)
    if not main then BuildMain() end
    local def = pages[id]
    if not def then return end
    if not main:IsShown() then ns.currentPage = id; main:Show() end
    for _, p in pairs(pages) do if p.frame then p.frame:Hide() end end
    if not def.frame then
        def.frame = CreateFrame("Frame", nil, main.content)
        def.frame:SetAllPoints(main.content)
        local ok, err = pcall(def.build, def.frame)
        if not ok then def.buildFailed = true; reportError(def, err) end
    end
    def.frame:Show()
    ns.currentPage = id
    ns:UpdateTabs()
    if not def.buildFailed then safeRefresh(def) end
    ns:SetStatus(def.code .. "  ·  " .. def.title:upper() .. "  ·  v" .. ns.VERSION
        .. (ns.HasAuctionator() and "  ·  " .. ns.Color("green", "AUCTIONATOR FEED OK") or "  ·  " .. ns.Color("red", "NO AUCTIONATOR FEED")))
end

function ns:RefreshPage(id)
    local def = pages[id]
    if main and main:IsShown() and ns.currentPage == id and def and def.frame and def.refresh and not def.buildFailed then
        safeRefresh(def)
    end
end

function ns:Toggle(id)
    if not main then BuildMain() end
    if main:IsShown() and (not id or id == ns.currentPage) then main:Hide() return end
    main:Show()
    ns:ShowPage(id or ns.currentPage or pageOrder[1].id)
end

function ns:ApplyScale()
    if main then main:SetScale(ns.S.scale or 1) end
end

---------------------------------------------------------------------------
-- Command line
---------------------------------------------------------------------------
COMMANDS = {
    PNL = function() ns:ShowPage("pnl") end,
    AUM = function() ns:ShowPage("aum") end,
    PORT = function() ns:ShowPage("port") end,
    RPT = function() ns:ShowPage("rpt") end,
    HUD = function() if ns.HUD then ns.HUD:Toggle() end end,
    RULES = function() if ns.Group then ns.Group:Print() end end,
    CHECK = function() if ns.Audit then ns.Audit:Print() end end,
    UPDATE = function()
        local U = ns.Update
        if U and U.newer then
            ns.Print("Newest version seen: " .. ns.Color("green", U.newer) .. " (you have " .. ns.VERSION .. ").")
        else
            ns.Print("You have " .. ns.VERSION .. ". No newer version seen from guild or group mates yet.")
        end
        ns.Print("Updater (download once, then double-click): " .. ns.Color("amber", U and U.UPDATER_URL or ""))
        ns.Print("Project page: " .. ns.Color("amber", U and U.REPO_URL or ""))
    end,
    PARTYDEBUG = function()
        if not ns.Party then return end
        ns.Party.debug = not ns.Party.debug
        ns.Print("Party loot debug " .. (ns.Party.debug and ns.Color("green", "ON") .. ": loot lines with items will be echoed with what the desk did." or ns.Color("grey", "OFF")))
    end,
    BELL = function() if ns.Bell then ns.Bell:Ask(GetZoneText and GetZoneText() or nil) end end,
    REPORT = function() if ns.Desk then ns.Desk:MorningReport(true) end end,
    GL = function() ns:ShowPage("gl") end,
    CMPL = function() ns:ShowPage("cmpl") end,
    START = function() if ns.Session then ns.Session:Start() end ns:ShowPage("pnl") end,
    PAUSE = function() if ns.Session then ns.Session:TogglePause() end end,
    STOP = function() if ns.Session then ns.Session:Stop() end end,
    MTM = function() if ns.Session then ns.Session:Remark() end end,
    DIAG = function()
        local P = ns.Print
        local v, build, _, iface = GetBuildInfo()
        P(ns.Color("orange", "DIAGNOSTICS") .. "  FPWM v" .. ns.VERSION .. "  ·  client " .. tostring(v) .. " (" .. tostring(iface) .. ")")
        local function yn(x) return x and ns.Color("green", "yes") or ns.Color("red", "no") end
        P("Modern AH API (C_AuctionHouse): " .. yn(C_AuctionHouse) .. "   Legacy AH API: " .. yn(GetNumAuctionItems)
            .. "   AuctionHouseFrame: " .. yn(AuctionHouseFrame) .. "   AuctionFrame: " .. yn(AuctionFrame))
        P("Auctionator API: " .. yn(ns.HasAuctionator()) .. "   Auctionator selling tab: " .. yn(_G.AuctionatorSellingFrame)
            .. "   Price history API: " .. yn(Auctionator and Auctionator.Database and Auctionator.Database.GetPriceHistory))
        if ns.Update then
            P("Update check: newest version seen " .. (ns.Update.newer and ns.Color("green", ns.Update.newer) or "none newer than yours"))
        end
        local st = ns.Session and ns.Session:Stats() or {}
        P("Session: " .. (st.active and ((st.paused and "paused" or "running") .. " · " .. ns.Duration(st.elapsed or 0)) or "none")
            .. " · ledger entries: " .. #ns.db.ledger)
        if ns.Audit then
            local r = ns.Audit:Run()
            local n = ns.Audit:Failures(r)
            P("Self-check: " .. (n == 0 and ns.Color("green", "all passed") or ns.Color("red", n .. " failed")) .. " (/fp check for details)")
        end
        if #ns.errors == 0 then P("Errors: none") else
            for i = math.max(1, #ns.errors - 2), #ns.errors do P(ns.Color("red", "Error: ") .. ns.errors[i]) end
        end
    end,
    HELP = function()
        ns.Print("Functions: |cffffc238PNL|r intraday P&L, |cffffc238AUM|r net worth, |cffffc238PORT|r portfolio, |cffffc238RPT|r report, |cffffc238GL|r ledger, |cffffc238CMPL|r settings,")
        ns.Print("|cffffc238START|r / |cffffc238PAUSE|r / |cffffc238STOP|r session, |cffffc238MTM|r mark holdings to market, |cffffc238HUD|r mini window, |cffffc238REPORT|r morning report.")
    end,
}
COMMANDS.SETTINGS, COMMANDS.CFG, COMMANDS.WEALTH, COMMANDS.LEDGER, COMMANDS.PORTFOLIO = COMMANDS.CMPL, COMMANDS.CMPL, COMMANDS.AUM, COMMANDS.GL, COMMANDS.PORT

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
local mmb
local function PlaceMinimap()
    local a = math.rad(ns.S.minimapAngle or 200)
    local r = (Minimap:GetWidth() / 2) + 6
    mmb:ClearAllPoints()
    mmb:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function ns:UpdateMinimap()
    if not mmb then return end
    mmb:SetShown(not ns.S.minimapHide)
end

local function BuildMinimap()
    mmb = CreateFrame("Button", "FishPartnersMinimapButton", Minimap)
    mmb:SetSize(31, 31)
    mmb:SetFrameStrata("MEDIUM")
    mmb:SetFrameLevel(8)
    mmb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mmb:RegisterForDrag("LeftButton")
    local icon = mmb:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Fish_02")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = mmb:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53); border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    mmb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    mmb:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if ns.Session then ns.Session:ToggleStartPause() end
        else
            ns:Toggle()
        end
    end)
    mmb:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            ns.S.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            PlaceMinimap()
        end)
    end)
    mmb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mmb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Fish & Partners", 0.98, 0.55, 0.12)
        GameTooltip:AddLine("Wealth Management", 0.6, 0.6, 0.65)
        if ns.Session then
            local s = ns.Session:Stats()
            if s.active then
                GameTooltip:AddDoubleLine("Session P&L", ns.MoneyShort(s.total), 1, 1, 1, 0.29, 0.96, 0.76)
                GameTooltip:AddDoubleLine("Gold / hour", s.gph and ns.MoneyShort(s.gph) or "--", 1, 1, 1, 1, 0.76, 0.22)
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffc238Left-click|r open terminal", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffc238Right-click|r start / pause session", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffc238Drag|r move", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    mmb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PlaceMinimap()
    ns:UpdateMinimap()
end

ns:OnInit(function()
    BuildMinimap()
    SLASH_FISHPARTNERS1 = "/fp"
    SlashCmdList.FISHPARTNERS = function(msg)
        msg = (msg or ""):upper():gsub("%s+", "")
        if msg == "" then ns:Toggle() return end
        local fn = COMMANDS[msg]
        if fn then
            fn()
        else
            COMMANDS.HELP()
        end
    end
end)
