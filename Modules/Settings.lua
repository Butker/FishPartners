-- Fish & Partners: Risk & Compliance (settings)

local _, ns = ...
local UI, C = ns.UI, ns.C

local function pct(v) return v .. "%" end
local function changedValuation() ns:Fire("VALUATION_CHANGED") end

local function build(p)
    local W = ns.PAGE_W
    local colW = (W - 24) / 2

    -- LEFT: valuation policy
    local l = CreateFrame("Frame", nil, p)
    l:SetPoint("TOPLEFT", 0, 0); l:SetSize(colW, ns.PAGE_H)
    local s1 = UI.Section(l, "Valuation policy"); s1:SetPoint("TOPLEFT", 0, 0); s1:SetWidth(colW)

    local y = -26
    local function add(ctrl, h)
        ctrl:SetPoint("TOPLEFT", 0, y)
        ctrl:SetWidth(colW)
        y = y - (h or 26)
        return ctrl
    end

    p.controls = {}
    local S = function() return ns.S end
    p.controls[#p.controls + 1] = add(UI.Stepper(l, "Gear (weapons/armor): AH must beat vendor by",
        function() return S().gearMargin end, function(v) S().gearMargin = v; changedValuation() end, 0, 500, 1, pct, colW))
    p.controls[#p.controls + 1] = add(UI.Stepper(l, "Mats & everything else: AH must beat vendor by",
        function() return S().otherMargin end, function(v) S().otherMargin = v; changedValuation() end, 0, 500, 1, pct, colW))
    p.controls[#p.controls + 1] = add(UI.Toggle(l, "Deduct the AH cut from AH prices (net proceeds)",
        function() return S().deductAHCut end, function(v) S().deductAHCut = v; changedValuation() end, colW))
    p.controls[#p.controls + 1] = add(UI.Stepper(l, "Mark AH prices as stale after (days)",
        function() return S().priceStaleDays or 7 end, function(v) S().priceStaleDays = v; changedValuation() end, 1, 60, 1, nil, colW), 24)
    p.controls[#p.controls + 1] = add(UI.Stepper(l, "AH cut",
        function() return S().ahCut end, function(v) S().ahCut = v; changedValuation() end, 0, 30, 1, pct, colW), 34)

    local explain = UI.Text(l, 10, C.grey, "LEFT")
    explain:SetWordWrap(true)
    explain:SetPoint("TOPLEFT", 0, y)
    explain:SetWidth(colW)
    explain:SetText(
        "How an item is priced:\n" ..
        "  1. Soulbound / BoP / quest items  →  vendor price.\n" ..
        "  2. Otherwise read the last Auctionator scan.\n" ..
        "  3. Use the AH price only if it beats vendor by the premium above\n" ..
        "      (gear defaults to 10%, everything else 5%). Else vendor.\n\n" ..
        "Shift-click + / - to step by 5. Changes re-mark open positions instantly.")
    y = y - 100

    local feed = UI.Text(l, 11, C.white, "LEFT")
    feed:SetPoint("TOPLEFT", 0, y)
    p.feed = feed
    y = y - 24


    -- RIGHT: desk settings
    local r = CreateFrame("Frame", nil, p)
    r:SetPoint("TOPLEFT", colW + 24, 0); r:SetSize(colW, ns.PAGE_H)
    local s2 = UI.Section(r, "Desk settings"); s2:SetPoint("TOPLEFT", 0, 0); s2:SetWidth(colW)
    y = -26
    local function addR(ctrl, h)
        ctrl:SetPoint("TOPLEFT", 0, y)
        ctrl:SetWidth(colW)
        y = y - (h or 24)
        return ctrl
    end
    p.controls[#p.controls + 1] = addR(UI.Toggle(r, "Count quest gold in Intraday P&L (on by default)",
        function() return S().sessionQuest end, function(v) S().sessionQuest = v; ns:Fire("SESSION_UPDATE") end, colW))
    p.controls[#p.controls + 1] = addR(UI.Toggle(r, "Include inventory (bags + bank) in AUM",
        function() return S().aumItems end, function(v) S().aumItems = v; ns.Wealth:Snapshot() end, colW))
    p.controls[#p.controls + 1] = addR(UI.Toggle(r, "Show minimap button",
        function() return not S().minimapHide end, function(v) S().minimapHide = not v; ns:UpdateMinimap() end, colW))
    p.controls[#p.controls + 1] = addR(UI.Stepper(r, "Terminal scale",
        function() return math.floor((S().scale or 1) * 100 + 0.5) end,
        function(v) S().scale = v / 100; ns:ApplyScale() end, 60, 160, 5, pct, colW))
    p.controls[#p.controls + 1] = addR(UI.Stepper(r, "Ticker tape speed",
        function() return S().tickerSpeed end, function(v) S().tickerSpeed = v end, 0, 150, 5, nil, colW))
    p.controls[#p.controls + 1] = addR(UI.Stepper(r, "Ledger retention (entries)",
        function() return S().ledgerMax end, function(v) S().ledgerMax = v end, 500, 50000, 500, ns.Commas, colW), 26)
    p.controls[#p.controls + 1] = addR(UI.Toggle(r, "Profit line in chat when an AH sale is collected",
        function() return S().saleChat end, function(v) S().saleChat = v end, colW), 22)
    p.controls[#p.controls + 1] = addR(UI.Toggle(r, "Morning report on first login of the day",
        function() return S().dailyReport end, function(v) S().dailyReport = v end, colW), 22)
    p.controls[#p.controls + 1] = addR(UI.Toggle(r, "Mini session window when a session starts",
        function() return S().hudAuto end, function(v) S().hudAuto = v end, colW), 24)
    p.controls[#p.controls + 1] = addR(UI.Toggle(r, "Pause the session while you're AFK",
        function() return S().afkPause ~= false end, function(v) S().afkPause = v end, colW), 24)
    p.controls[#p.controls + 1] = addR(UI.Toggle(r, "Group loot rules with other Fish & Partners users",
        function() return S().groupRules ~= false end, function(v) S().groupRules = v end, colW), 24)
    p.controls[#p.controls + 1] = addR(UI.Toggle(r, "Opening bell when entering a dungeon or raid",
        function() return S().instanceBell end, function(v) S().instanceBell = v end, colW), 24)
    p.controls[#p.controls + 1] = addR(UI.Stepper(r, "Mini window scale",
        function() return math.floor((S().hudScale or 1) * 100 + 0.5) end,
        function(v) S().hudScale = v / 100; if ns.HUD then ns.HUD:ApplyScale() end end, 60, 200, 5, pct, colW), 32)

    local s3 = UI.Section(r, "Danger zone"); s3:SetPoint("TOPLEFT", 0, y); s3:SetWidth(colW)
    y = y - 26
    local function danger(label, msg, fn, x)
        local b = UI.Button(r, label, (colW - 8) / 2, 22, "danger")
        b:SetPoint("TOPLEFT", x, y)
        b:SetScript("OnClick", function() UI.Confirm(msg, function() fn(); ns.Print("Done. Compliance has been notified.") end) end)
        return b
    end
    danger("SHRED LEDGER", "Delete ALL general ledger entries (every character)?", function()
        wipe(ns.db.ledger); ns:RefreshPage("gl")
    end, 0)
    danger("WIPE AUM HISTORY", "Delete the daily AUM history chart data?", function()
        wipe(ns.db.history); ns.Wealth:Snapshot()
    end, (colW + 8) / 2)
    y = y - 28
    danger("CLEAR BOOKED SESSIONS", "Delete this character's booked session archive?", function()
        wipe(ns.cdb.archive); ns:RefreshPage("pnl")
    end, 0)
    danger("FORGET OTHER ACCOUNTS", "Remove every other character from AUM tracking?", function()
        local mine = ns.CharKey()
        for k in pairs(ns.db.chars) do if k ~= mine then ns.db.chars[k] = nil end end
        ns.Wealth:Snapshot()
    end, (colW + 8) / 2)
    y = y - 30

    local disclaimer = UI.Text(r, 9, C.dim, "LEFT")
    disclaimer:SetWordWrap(true)
    disclaimer:SetPoint("TOPLEFT", 0, y); disclaimer:SetWidth(colW)
    disclaimer:SetText("Fish & Partners Wealth Management is not a registered investment adviser. " ..
        "Past loot is not indicative of future loot. Murloc-denominated assets may go down as well as up. " ..
        "Goblin AH cut subject to change without notice.")
end

local function refresh(p)
    for _, c in ipairs(p.controls) do if c.Refresh then c:Refresh() end end
    if ns.HasAuctionator() then
        p.feed:SetText("Price feed:  " .. ns.Color("green", "AUCTIONATOR CONNECTED") ..
            ns.Color("grey", "  ·  run a full scan at the AH for fresh marks"))
    else
        p.feed:SetText("Price feed:  " .. ns.Color("red", "AUCTIONATOR NOT FOUND") ..
            ns.Color("grey", "  ·  vendor prices only"))
    end
end

ns:RegisterPage({ id = "cmpl", order = 7, code = "CMPL", title = "Compliance", build = build, refresh = refresh })
