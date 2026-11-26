-- Fish & Partners: Assets Under Management (wealth across characters)
-- Cash per character + bags/bank marked to market with the same valuation policy.

local _, ns = ...
local UI, C = ns.UI, ns.C
local A = {}
ns.Wealth = A
local floor = math.floor

local function me()
    local key = ns.CharKey()
    local ch = ns.db.chars[key]
    if not ch then
        ch = {}
        ns.db.chars[key] = ch
    end
    return ch, key
end

local function scanBags(first, last, includeBank)
    local value, holdings, missing, counts = 0, {}, false, {}
    local function scan(bag)
        for slot = 1, ns.GetNumSlots(bag) do
            local link, count, isBound, itemID = ns.GetSlotInfo(bag, slot)
            if link then
                count = count or 1
                local id = itemID or tonumber(link:match("item:(%d+)"))
                if id then
                    local c = counts[id] or { q = 0, link = link }
                    c.q = c.q + count
                    if isBound then c.bound = true end
                    counts[id] = c
                end
                local unit = ns.Valuate(link, isBound)
                if id and ns.IsHiddenItem and ns.IsHiddenItem(id) then unit = 0 end
                if unit then
                    local v = unit * (count or 1)
                    value = value + v
                    local h = holdings[link]
                    if h then h.q, h.v = h.q + count, h.v + v else holdings[link] = { q = count, v = v } end
                else
                    missing = true
                end
            end
        end
    end
    if includeBank then scan(BANK_CONTAINER or -1) end
    for bag = first, last do scan(bag) end
    return value, holdings, missing, counts
end

local function topHoldings(map, n)
    local list = {}
    for link, h in pairs(map) do list[#list + 1] = { l = link, q = h.q, v = h.v } end
    table.sort(list, function(a, b) return a.v > b.v end)
    while #list > n do table.remove(list) end
    return list
end

function A:UpdateBasics()
    local ch = me()
    ch.name = UnitName("player")
    ch.realm = GetRealmName()
    ch.class = select(2, UnitClass("player"))
    ch.faction = UnitFactionGroup("player")
    ch.level = UnitLevel("player")
    ch.money = GetMoney()
    ch.t = time()
    self:Snapshot()
end

local retries = 0
function A:ScanBags()
    local ch = me()
    local nb = NUM_BAG_SLOTS or 4
    local v, map, missing, counts = scanBags(0, nb, false)
    ch.bags = v
    if ns.Portfolio then ns.Portfolio:SetLocation("b", counts) end
    ch.bagTop = topHoldings(map, 8)
    ch.t = time()
    if missing and retries < 5 then
        retries = retries + 1
        C_Timer.After(3, function() A:ScanBags() end)
    else
        retries = 0
    end
    self:Snapshot()
    ns:RefreshPage("aum")
end

function A:ScanBank()
    local ch = me()
    local nb = NUM_BAG_SLOTS or 4
    local v, map, _, counts = scanBags(nb + 1, nb + (NUM_BANKBAGSLOTS or 6), true)
    ch.bank = v
    if ns.Portfolio then ns.Portfolio:SetLocation("k", counts) end
    ch.bankTop = topHoldings(map, 8)
    ch.bankT = time()
    self:Snapshot()
    ns:RefreshPage("aum")
end

function A:Totals()
    local cash, items, n, richest, richV = 0, 0, 0, nil, -1
    for key, ch in pairs(ns.db.chars) do
        local inv = (ch.bags or 0) + (ch.bank or 0) + (ch.otherV or 0)
        cash = cash + (ch.money or 0)
        items = items + inv
        n = n + 1
        local t = (ch.money or 0) + (ns.S.aumItems and inv or 0)
        if t > richV then richest, richV = key, t end
    end
    local total = cash + (ns.S.aumItems and items or 0)
    return total, cash, items, n, richest
end

function A:Snapshot()
    local total, cash = self:Totals()
    local today = ns.Today()
    ns.db.history[today] = { total = total, cash = cash }
end

-- Previous close: most recent day before today
function A:PrevClose()
    local today, best = ns.Today(), nil
    for d in pairs(ns.db.history) do
        if d < today and (not best or d > best) then best = d end
    end
    return best and ns.db.history[best], best
end

local throttle
local function scheduleBagScan()
    if throttle then return end
    throttle = true
    C_Timer.After(2, function() throttle = nil; A:ScanBags() end)
end

ns:OnInit(function()
    A:UpdateBasics()
    C_Timer.After(5, function() A:ScanBags() end)
    -- prune history older than 400 days
    local cutoff = date("%Y-%m-%d", time() - 400 * 86400)
    for d in pairs(ns.db.history) do if d < cutoff then ns.db.history[d] = nil end end
end)
ns:On("PLAYER_MONEY", function() if ns.db then A:UpdateBasics(); ns:RefreshPage("aum") end end)
ns:On("PLAYER_LEVEL_UP", function() if ns.db then C_Timer.After(1, function() A:UpdateBasics() end) end end)
ns:On("BAG_UPDATE_DELAYED", function() if ns.db then scheduleBagScan() end end)
ns:On("BANKFRAME_OPENED", function() if ns.db then C_Timer.After(0.5, function() A:ScanBank() end) end end)
ns:On("PLAYERBANKSLOTS_CHANGED", function() if ns.db and BankFrame and BankFrame:IsShown() then A:ScanBank() end end)
ns:Listen("VALUATION_CHANGED", function() A:ScanBags() end)

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local chartDays = 30

local function build(p)
    local W = ns.PAGE_W
    local kw = (W - 4 * 6) / 5
    local labels = { "Total AUM", "Cash (liquid)", "Inventory · MTM", "Day change", "Book" }
    p.kpi = {}
    for i, l in ipairs(labels) do
        local k = UI.KPI(p, l, kw, 60, i == 1 and 20 or 17)
        k:SetPoint("TOPLEFT", (i - 1) * (kw + 6), 0)
        p.kpi[i] = k
    end

    local s1 = UI.Section(p, "AUM history · daily close")
    s1:SetPoint("TOPLEFT", 0, -68); s1:SetPoint("RIGHT", p, "RIGHT", -170, 0)
    local seg = UI.Segment(p, { { 30, "30D" }, { 90, "90D" }, { 365, "1Y" } },
        function(v) chartDays = v; ns:RefreshPage("aum") end, 48, 16)
    seg:SetPoint("TOPRIGHT", 0, -68)
    seg:Select(chartDays)
    p.chart = UI.BarChart(p, W, 150)
    p.chart:SetPoint("TOPLEFT", 0, -88)
    p.chart.empty:SetText("History builds up one bar per day you log in.")

    local s2 = UI.Section(p, "Holdings by account", true)
    s2:SetPoint("TOPLEFT", 0, -246); s2:SetWidth(W)
    p.secChars = s2
    p.list = UI.Table(p, {
        { title = "Account", width = 140 },
        { title = "Realm", width = 112 },
        { title = "Lvl", width = 34, justify = "RIGHT" },
        { title = "Cash", width = 104, justify = "RIGHT" },
        { title = "Bags", width = 94, justify = "RIGHT" },
        { title = "Bank", width = 94, justify = "RIGHT" },
        { title = "Total", width = 110, justify = "RIGHT" },
        { title = "Alloc", width = 58, justify = "RIGHT" },
        { title = "Updated", width = 90, justify = "RIGHT" },
    }, W, ns.PAGE_H - 266, 17)
    p.list:SetPoint("TOPLEFT", 0, -266)
end

local function ago(t)
    if not t then return ns.Color("dim", "never") end
    local d = time() - t
    if d < 120 then return ns.Color("green", "live") end
    if d < 3600 then return floor(d / 60) .. "m ago" end
    if d < 86400 then return floor(d / 3600) .. "h ago" end
    return floor(d / 86400) .. "d ago"
end

local function refresh(p)
    local total, cash, items, n, richest = A:Totals()
    local prev, prevDay = A:PrevClose()

    p.kpi[1].value:SetText(ns.Color("amber", ns.MoneyShort(total)))
    p.kpi[1].sub:SetText(n .. " accounts" .. (ns.S.aumItems and " · cash + inventory" or " · cash only"))
    p.kpi[2].value:SetText(ns.MoneyShort(cash))
    p.kpi[2].sub:SetText(total > 0 and format("%.0f%% of AUM", 100 * cash / total) or "")
    p.kpi[3].value:SetText(ns.MoneyShort(items))
    p.kpi[3].sub:SetText(ns.HasAuctionator() and "bags, bank, mail, AH listings" or "vendor prices only")
    if prev and prev.total then
        local d = total - prev.total
        local pct = prev.total > 0 and (100 * d / prev.total) or nil
        p.kpi[4].value:SetText(ns.PnL(d))
        p.kpi[4].sub:SetText((pct and ns.Pct(pct, true) or "--") .. " vs " .. prevDay)
    else
        p.kpi[4].value:SetText(ns.Color("dim", "--"))
        p.kpi[4].sub:SetText("no prior close yet")
    end
    p.kpi[5].value:SetText(richest and ns.CharLabel(richest) or "--")
    p.kpi[5].sub:SetText("top allocation")

    -- chart
    local pts = {}
    for i = chartDays - 1, 0, -1 do
        local d = date("%Y-%m-%d", time() - i * 86400)
        local h = ns.db.history[d]
        if h then pts[#pts + 1] = { v = (ns.S.aumItems and h.total or h.cash) or 0, label = d } end
    end
    p.chart:SetData(pts, pts[1] and pts[1].label or "", pts[#pts] and pts[#pts].label or "", "orange")

    -- accounts
    local rows = {}
    local myKey = ns.CharKey()
    for key, ch in pairs(ns.db.chars) do
        local inv = (ch.bags or 0) + (ch.bank or 0) + (ch.otherV or 0)
        local t = (ch.money or 0) + (ns.S.aumItems and inv or 0)
        rows[#rows + 1] = {
            t = t,
            cells = {
                (key == myKey and ns.Color("orange", "» ") or "") .. ns.CharLabel(key),
                ns.Color("grey", ch.realm or ""),
                tostring(ch.level or ""),
                ns.MoneyShort(ch.money or 0),
                ns.Color("grey", ns.MoneyShort(ch.bags or 0)),
                ch.bankT and ns.Color("grey", ns.MoneyShort(ch.bank or 0)) or ns.Color("dim", "visit bank"),
                ns.Color("white", ns.MoneyShort(t)),
                total > 0 and ns.Color("amber", format("%.1f%%", 100 * t / total)) or "",
                ago(ch.t),
            },
            tooltip = function(tt)
                tt:AddLine(ns.CharLabel(key) .. ns.Color("grey", " - " .. (ch.realm or "")))
                tt:AddDoubleLine("Cash", ns.Money(ch.money or 0), 0.8, 0.8, 0.8, 1, 1, 1)
                tt:AddDoubleLine("Bags (MTM)", ns.Money(ch.bags or 0), 0.8, 0.8, 0.8, 1, 1, 1)
                tt:AddDoubleLine("Bank (MTM)", ch.bankT and ns.Money(ch.bank or 0) or "not scanned", 0.8, 0.8, 0.8, 1, 1, 1)
                tt:AddDoubleLine("Mail + AH listings", ns.Money(ch.otherV or 0), 0.8, 0.8, 0.8, 1, 1, 1)
                local top = {}
                for _, h in ipairs(ch.bagTop or {}) do top[#top + 1] = h end
                for _, h in ipairs(ch.bankTop or {}) do top[#top + 1] = h end
                table.sort(top, function(a, b) return a.v > b.v end)
                if #top > 0 then
                    tt:AddLine(" ")
                    tt:AddLine("Top positions", 0.98, 0.55, 0.12)
                    for i = 1, math.min(8, #top) do
                        tt:AddDoubleLine(top[i].l .. " x" .. top[i].q, ns.MoneyShort(top[i].v), 1, 1, 1, 1, 1, 1)
                    end
                end
                if key ~= myKey then
                    tt:AddLine(" ")
                    tt:AddLine("Right-click to close this account", 0.5, 0.5, 0.55)
                end
            end,
            onClick = function(button)
                if button == "RightButton" and key ~= myKey then
                    UI.Confirm("Close account " .. key .. "?\n(Removes it from AUM tracking.)", function()
                        ns.db.chars[key] = nil
                        A:Snapshot()
                        ns:RefreshPage("aum")
                    end)
                end
            end,
        }
    end
    table.sort(rows, function(a, b) return a.t > b.t end)
    p.list:SetData(rows, true)
    p.secChars.right:SetText(n .. " ACCOUNTS")
end

ns:RegisterPage({ id = "aum", order = 2, code = "AUM", title = "Net Worth", build = build, refresh = refresh })

ns:AddTicker(function()
    if not ns.db then return end
    local total, cash = A:Totals()
    local prev = A:PrevClose()
    local chg = ""
    if prev and prev.total and prev.total > 0 then
        local pct = 100 * (total - prev.total) / prev.total
        chg = " " .. (pct >= 0 and ns.Color("green", ns.Pct(pct, true)) or ns.Color("red", ns.Pct(pct)))
    end
    return "AUM " .. ns.Color("amber", ns.MoneyShort(total)) .. chg .. "   CASH " .. ns.MoneyShort(cash)
end)
