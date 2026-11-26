-- Fish & Partners: Auction desk (ledger-driven, no AH window overlays)
--   * Below-cost warning in chat when you post
--   * Profit line in chat when an AH sale is collected
--   * Auction log (posted / sold / expired) -> sell-through, "doesn't sell" signals
--   * Morning report on your first login of the day
--   * Report tab (RPT)

local _, ns = ...
local UI, C = ns.UI, ns.C
local D = {}
ns.Desk = D
local floor, min, max, abs = math.floor, math.min, math.max, math.abs

ns:OnInit(function()
    ns.db.aucLog = ns.db.aucLog or {}
    ns.db.seenMail = ns.db.seenMail or {}
    local now = time()
    for k, exp in pairs(ns.db.seenMail) do if exp < now then ns.db.seenMail[k] = nil end end
end)

local function ID(x) return ns.Portfolio and ns.Portfolio.ID(x) end
local function Link(id) return ns.Portfolio and ns.Portfolio.Link(id) end
local function cut() return (ns.S.ahCut or 5) / 100 end

function D.Log(kind, id, q, v, r)
    if not id or not q or q <= 0 then return end
    local log = ns.db.aucLog
    log[#log + 1] = { t = time(), k = kind, id = id, q = q, v = v, r = r, c = ns.CharKey() }
    while #log > 3000 do table.remove(log, 1) end
end

---------------------------------------------------------------------------
-- Sell slot snapshot
---------------------------------------------------------------------------
local sell -- { id, link, count, name }
local function readSellSlot()
    if not GetAuctionSellItemInfo then sell = nil return end
    local name, _, count, _, _, _, _, _, _, itemID = GetAuctionSellItemInfo()
    if not name then sell = nil return end
    local id = itemID or ID(name)
    sell = { id = id, name = name, count = count or 1, link = id and Link(id) or name }
end

ns:On("NEW_AUCTION_UPDATE", function() if ns.db then readSellSlot() end end)
ns:On("AUCTION_HOUSE_CLOSED", function() sell = nil end)

---------------------------------------------------------------------------
-- Post hooks: log + below-cost warning
---------------------------------------------------------------------------
local function warnIfBelowCost(id, perUnit, qty, link)
    if not id or not perUnit then return end
    local b = ns.Portfolio:Basis(id)
    if not b or b.qty <= 0 then return end
    local net = perUnit * (1 - cut())
    if net < b.avg then
        ns.Print(ns.Color("red", "BELOW COST") .. "  " .. (link or "") .. " posted at " .. ns.MoneyShort(perUnit) ..
            " vs your cost " .. ns.MoneyShort(b.avg) .. ". Loss if it sells: " .. ns.Color("red", ns.MoneyShort((b.avg - net) * qty)))
    end
end

local function hook(tbl, name, fn)
    if type(tbl) == "table" and type(tbl[name]) == "function" then
        hooksecurefunc(tbl, name, function(...)
            local ok, err = pcall(fn, ...)
            if not ok then geterrorhandler()(err) end
        end)
    end
end

ns:OnInit(function()
    local function legacy(minBid, buyout, _, stackSize, numStacks)
        if not sell then readSellSlot() end
        if not sell then return end
        stackSize = stackSize or sell.count or 1
        local qty = stackSize * (numStacks or 1)
        D.Log("post", sell.id, qty)
        if buyout and buyout > 0 then warnIfBelowCost(sell.id, buyout / stackSize, qty, sell.link) end
    end
    hook(_G, "PostAuction", legacy)
    hook(_G, "StartAuction", legacy)
    if C_AuctionHouse then
        local function linkOf(loc) return C_Item and C_Item.GetItemLink and loc and C_Item.GetItemLink(loc) end
        hook(C_AuctionHouse, "PostItem", function(loc, _, qty, _, buyout)
            local link = linkOf(loc); local id = ID(link); qty = qty or 1
            D.Log("post", id, qty)
            -- modern AH: buyout is the price per unit; qty is how many at that price
            if buyout and buyout > 0 then warnIfBelowCost(id, buyout, qty, link) end
        end)
        hook(C_AuctionHouse, "PostCommodity", function(loc, _, qty, unitPrice)
            local link = linkOf(loc); local id = ID(link)
            D.Log("post", id, qty)
            warnIfBelowCost(id, unitPrice, qty or 1, link)
        end)
    end
end)

---------------------------------------------------------------------------
-- Sales: chat line + log
---------------------------------------------------------------------------
ns:Listen("LEDGER_ENTRY", function(e)
    if e.k ~= "AH_SALE" or e.c ~= ns.CharKey() then return end
    local id = ID(e.i)
    D.Log("sold", id, e.q or 0, e.a, e.r)
    if not ns.S.saleChat then return end
    local link = id and Link(id) or e.i or "?"
    local msg = ns.Color("green", "SOLD") .. "  " .. (e.q and (e.q .. "x ") or "") .. link .. " for " .. ns.MoneyShort(e.a)
    local b = id and ns.Portfolio:Basis(id)
    if e.r and b and e.q then
        local cost = e.q * b.avg
        msg = msg .. "  ·  " .. ns.PnL(e.r) .. " realized" .. (cost > 0 and ns.Color("grey", " (" .. ns.Pct(100 * e.r / cost, true) .. ")") or "")
    else
        msg = msg .. ns.Color("dim", "  ·  uncosted")
    end
    ns.Print(msg)
end)

---------------------------------------------------------------------------
-- Expired auctions (from the mailbox)
---------------------------------------------------------------------------
local function countArg(modernN, ...)
    if select("#", ...) >= modernN then return (select(4, ...)) end
    return (select(3, ...))
end
local expiredCap

ns:On("MAIL_INBOX_UPDATE", function()
    if not ns.db or not GetInboxNumItems then return end
    expiredCap = expiredCap or (ns.Ledger.SubjectCapture(_G.AUCTION_EXPIRED_MAIL_SUBJECT, "^Auction expired: (.+)$"))
    for i = 1, (GetInboxNumItems() or 0) do
        local _, _, sender, subject, _, _, daysLeft = GetInboxHeaderInfo(i)
        if subject and subject:match(expiredCap) then
            local expiry = time() + floor((daysLeft or 0) * 86400)
            local key = subject .. "|" .. floor(expiry / 3600)
            if not ns.db.seenMail[key] then
                ns.db.seenMail[key] = expiry + 3600
                local link = GetInboxItemLink and GetInboxItemLink(i, 1)
                local id = ID(link) or ID(subject:match(expiredCap))
                local q = link and tonumber(countArg(6, GetInboxItem(i, 1))) or 1
                D.Log("exp", id, q)
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Aggregations
---------------------------------------------------------------------------
function D:Aggregate(seconds)
    local since = seconds and (time() - seconds) or 0
    local per = {}
    local sold, expired = 0, 0
    for i = #ns.db.aucLog, 1, -1 do
        local l = ns.db.aucLog[i]
        if l.t < since then break end
        local a = per[l.id] or { posted = 0, sold = 0, exp = 0, value = 0, realized = 0 }
        per[l.id] = a
        if l.k == "post" then a.posted = a.posted + l.q
        elseif l.k == "sold" then a.sold = a.sold + l.q; a.value = a.value + (l.v or 0); a.realized = a.realized + (l.r or 0); sold = sold + l.q
        elseif l.k == "exp" then a.exp = a.exp + l.q; expired = expired + l.q end
    end
    return per, sold, expired
end

function D:Signal(a)
    local total = a.sold + a.exp
    if total == 0 then return ns.Color("dim", "NEW"), nil end
    local st = a.sold / total
    if a.sold == 0 and a.exp >= 2 then return ns.Color("red", "NO BID"), "Nothing sold, several expiries: list lower or vendor it." end
    if st < 0.4 then return ns.Color("amber", "CUT PRICE"), "Under 40% sell-through: undercut more aggressively." end
    if st >= 0.8 and a.sold >= 5 then return ns.Color("green", "HOT"), "Sells reliably: you may be able to price higher." end
    return ns.Color("grey", "OK"), nil
end

---------------------------------------------------------------------------
-- Morning report
---------------------------------------------------------------------------
function D:MorningReport(force)
    local today = ns.Today()
    if not force and (not ns.S.dailyReport or ns.db.lastReport == today) then return end
    ns.db.lastReport = today
    local P = ns.Print
    P(ns.Color("orange", "MORNING REPORT") .. ns.Color("grey", "  ·  " .. date("%A %d %B"):upper()))

    local total = ns.Wealth:Totals()
    local prev, prevDay = ns.Wealth:PrevClose()
    if prev and prev.total and prev.total > 0 then
        P(format("AUM %s  %s vs %s", ns.Color("amber", ns.MoneyShort(total)), ns.PnL(total - prev.total) ..
            ns.Color("grey", " (" .. ns.Pct(100 * (total - prev.total) / prev.total, true) .. ")"), prevDay))
    else
        P("AUM " .. ns.Color("amber", ns.MoneyShort(total)))
    end

    -- movers among your holdings: latest daily low vs the one before
    local best, worst
    local seen = {}
    for _, ch in pairs(ns.db.chars) do
        for id in pairs(ch.inv or {}) do
            if not seen[id] and not ns.Portfolio:IsHidden(id) then
                seen[id] = true
                local h = ns.Market and ns.Market.History(id, 14) or {}
                if #h >= 2 then
                    local a, b = h[#h - 1].v, h[#h].v
                    if a > 0 then
                        local pct = 100 * (b / a - 1)
                        if not best or pct > best.p then best = { id = id, p = pct } end
                        if not worst or pct < worst.p then worst = { id = id, p = pct } end
                    end
                end
            end
        end
    end
    if best and best.p > 0 then P("Top gainer  " .. (Link(best.id) or best.id) .. "  " .. ns.Color("green", ns.Pct(best.p, true))) end
    if worst and worst.p < 0 then P("Top loser   " .. (Link(worst.id) or worst.id) .. "  " .. ns.Color("red", ns.Pct(worst.p))) end

    local _, sold, expired = D:Aggregate(86400)
    local net, n = 0, 0
    for i = #ns.db.ledger, 1, -1 do
        local e = ns.db.ledger[i]
        if e.t < time() - 86400 then break end
        if e.k == "AH_SALE" then n = n + 1 end
        local cat = ns.Ledger.CATS[e.k]
        if cat and cat[2] == "AH" then net = net + e.a end
    end
    P(format("AH 24h: %d sales (%d units)  ·  %d expired  ·  net ", n, sold, expired) .. ns.PnL(net))
    local w = 0
    for _ in pairs(ns.db.watch or {}) do w = w + 1 end
    if w > 0 then P(w .. " items on your watchlist. Have a profitable session.") end
end
ns:OnInit(function() C_Timer.After(15, function() D:MorningReport() end) end)

---------------------------------------------------------------------------
-- Report page
---------------------------------------------------------------------------
local RANGES = { ["7D"] = 7 * 86400, ["30D"] = 30 * 86400, ALL = nil }
local view = { range = "30D" }

local function build(p)
    local W, H = ns.PAGE_W, ns.PAGE_H
    local seg = UI.Segment(p, { { "7D", "7D" }, { "30D", "30D" }, { "ALL", "ALL" } },
        function(v) view.range = v; ns:RefreshPage("rpt") end, 44, 20)
    seg:SetPoint("TOPLEFT", 0, 0); seg:Select(view.range)
    local mr = UI.Button(p, "MORNING REPORT", 120, 20, "default")
    mr:SetPoint("TOPRIGHT", 0, 0)
    mr:SetScript("OnClick", function() D:MorningReport(true) end)

    local kw = (W - 4 * 6) / 5
    local labels = { "AH proceeds", "Avg profit / sale", "Sell-through", "AH costs", "Realized P&L · lifetime" }
    p.kpi = {}
    for i, l in ipairs(labels) do
        local k = UI.KPI(p, l, kw, 56)
        k:SetPoint("TOPLEFT", (i - 1) * (kw + 6), -28)
        p.kpi[i] = k
    end

    local leftW = 318
    local rightW = W - leftW - 10
    local s1 = UI.Section(p, "Top earners · lifetime"); s1:SetPoint("TOPLEFT", 0, -92); s1:SetWidth(leftW)
    p.top = UI.Table(p, {
        { title = "Instrument", width = 190 },
        { title = "Realized", width = 120, justify = "RIGHT" },
    }, leftW, H - 112, 16)
    p.top:SetPoint("TOPLEFT", 0, -112)
    p.top:SetEmptyText("Sell something with a cost basis.")

    local s2 = UI.Section(p, "Auction performance", true); s2:SetPoint("TOPLEFT", leftW + 10, -92); s2:SetWidth(rightW)
    p.secPerf = s2
    p.perf = UI.Table(p, {
        { title = "Instrument", width = 168 },
        { title = "Posted", width = 50, justify = "RIGHT" },
        { title = "Sold", width = 46, justify = "RIGHT" },
        { title = "Expired", width = 54, justify = "RIGHT" },
        { title = "ST%", width = 46, justify = "RIGHT" },
        { title = "Avg/unit", width = 66, justify = "RIGHT" },
        { title = "Signal", width = 76, justify = "RIGHT" },
    }, rightW, H - 112, 16)
    p.perf:SetPoint("TOPLEFT", leftW + 10, -112)
    p.perf:SetEmptyText("Post some auctions. Expiries are read from your mailbox.")
end

local function refresh(p)
    local secs = RANGES[view.range]
    local since = secs and (time() - secs) or 0
    local proceeds, nSales, rSum, rN, fees, deposits = 0, 0, 0, 0, 0, 0
    for i = #ns.db.ledger, 1, -1 do
        local e = ns.db.ledger[i]
        if e.t < since then break end
        if e.k == "AH_SALE" then
            proceeds, nSales = proceeds + e.a, nSales + 1
            if e.r then rSum, rN = rSum + e.r, rN + 1 end
            fees = fees + (e.f or 0)
        elseif e.k == "AH_DEPOSIT" then
            deposits = deposits - e.a
        end
    end
    local per, sold, expired = D:Aggregate(secs)

    p.kpi[1].value:SetText(ns.Color("green", ns.MoneyShort(proceeds)))
    p.kpi[1].sub:SetText(nSales .. " sales collected · " .. view.range)
    p.kpi[2].value:SetText(rN > 0 and ns.PnL(rSum / rN) or ns.Color("dim", "--"))
    p.kpi[2].sub:SetText(rN > 0 and (rN .. " costed sales") or "needs cost basis")
    local st = (sold + expired) > 0 and (100 * sold / (sold + expired)) or nil
    p.kpi[3].value:SetText(st and ns.Color(st >= 60 and "green" or st >= 40 and "amber" or "red", ns.Pct(st)) or ns.Color("dim", "--"))
    p.kpi[3].sub:SetText(sold .. " sold · " .. expired .. " expired (units)")
    p.kpi[4].value:SetText(ns.Color("red", ns.MoneyShort(fees + deposits)))
    p.kpi[4].sub:SetText("cut " .. ns.MoneyShort(fees) .. " · deposits " .. ns.MoneyShort(deposits))
    p.kpi[5].value:SetText(ns.PnL(ns.db.realized or 0))
    p.kpi[5].sub:SetText("vs your avg cost")

    -- top earners (lifetime realized per item)
    local top = {}
    for id, b in pairs(ns.db.basis or {}) do
        if b.realized and abs(b.realized) >= 1 then
            local link = Link(id)
            top[#top + 1] = { v = b.realized, link = link, cells = { link or ("item " .. id), ns.PnL(b.realized) } }
        end
    end
    table.sort(top, function(a, b) return a.v > b.v end)
    p.top:SetData(top, true)

    -- performance
    local rows = {}
    for id, a in pairs(per) do
        local link = Link(id)
        local sig, advice = D:Signal(a)
        local total = a.sold + a.exp
        rows[#rows + 1] = {
            n = a.posted + a.sold + a.exp, link = link,
            cells = {
                link or ("item " .. tostring(id)),
                tostring(a.posted), tostring(a.sold), tostring(a.exp),
                total > 0 and ns.Pct(100 * a.sold / total) or "--",
                a.sold > 0 and ns.MoneyShort(a.value / a.sold) or ns.Color("dim", "--"),
                sig,
            },
            tooltip = function(tt)
                if link then pcall(tt.SetHyperlink, tt, link) end
                tt:AddLine(" ")
                tt:AddLine("Auction performance · " .. view.range, 0.98, 0.55, 0.12)
                tt:AddDoubleLine("Posted / sold / expired", a.posted .. " / " .. a.sold .. " / " .. a.exp, 0.8, 0.8, 0.8, 1, 1, 1)
                if a.sold > 0 then tt:AddDoubleLine("Proceeds", ns.Money(a.value), 0.8, 0.8, 0.8, 1, 1, 1) end
                if a.realized ~= 0 then tt:AddDoubleLine("Realized", ns.Money(a.realized, true), 0.8, 0.8, 0.8, 1, 1, 1) end
                local med = ns.Market and ns.Market.MarketMedian(id)
                local mkt = ns.GetAHPrice(link, id)
                if advice then
                    tt:AddLine(" ")
                    tt:AddLine(advice, 1, 0.76, 0.22, true)
                    local ref = med and mkt and min(med, mkt) or med or mkt
                    if ref then tt:AddDoubleLine("Suggested list price", ns.Money(floor(ref * 0.97)), 0.8, 0.8, 0.8, 0.29, 0.96, 0.76) end
                end
            end,
        }
    end
    table.sort(rows, function(a, b) return a.n > b.n end)
    p.perf:SetData(rows, true)
    p.secPerf.right:SetText(#rows .. " INSTRUMENTS · " .. view.range)
end

ns:RegisterPage({ id = "rpt", order = 5, code = "RPT", title = "Report", build = build, refresh = refresh })
ns:Listen("LEDGER_ENTRY", function() ns:RefreshPage("rpt") end)
