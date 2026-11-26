-- Fish & Partners: General Ledger
-- Every change to your money (PLAYER_MONEY delta) is booked as one ledger entry.
-- Context (open AH / merchant / mail / loot window...) and hooks on the actions
-- you take (buyouts, postings, vendor sales, mail collection) tell us WHAT it was.

local _, ns = ...
local UI, C = ns.UI, ns.C
local L = {}
ns.Ledger = L

L.CATS = {
    LOOT        = { "Loot (coin)",      "LOOT" },
    QUEST       = { "Quest reward",     "OTHER" },
    AH_BUY      = { "AH purchase",      "AH" },
    AH_BID      = { "AH bid placed",    "AH" },
    AH_SALE     = { "AH sale",          "AH" },
    AH_DEPOSIT  = { "AH deposit",       "AH" },
    AH_REFUND   = { "AH outbid refund", "AH" },
    VENDOR_SALE = { "Vendor sale",      "VENDOR" },
    VENDOR_BUY  = { "Vendor purchase",  "VENDOR" },
    REPAIR      = { "Repairs",          "VENDOR" },
    MAIL_IN     = { "Mail received",    "OTHER" },
    MAIL_OUT    = { "Mail sent/postage","OTHER" },
    TRADE_IN    = { "Trade in",         "OTHER" },
    TRADE_OUT   = { "Trade out",        "OTHER" },
    TRAVEL      = { "Flight path",      "OTHER" },
    TRAINING    = { "Class training",   "OTHER" },
    BANK        = { "Bank slot",        "OTHER" },
    OTHER_IN    = { "Other income",     "OTHER" },
    OTHER_OUT   = { "Other expense",    "OTHER" },
}

---------------------------------------------------------------------------
-- Context + tags
---------------------------------------------------------------------------
local ctx = {}       -- name -> { open = bool, closed = GetTime() }
local tags = {}      -- pending action hints
local pending = {}   -- money deltas awaiting classification
local lastMoney

local function setCtx(name, open)
    ctx[name] = ctx[name] or {}
    ctx[name].open = open
    if not open then ctx[name].closed = GetTime() end
end
local function inCtx(name, grace)
    local c = ctx[name]
    if not c then return false end
    return c.open or (c.closed and GetTime() - c.closed < (grace or 2))
end
L.InCtx = inCtx
local floor = math.floor

-- info.expect = exact copper we expect (mail money); such tags only ever match that amount
-- info.key    = identity, so the same mail is never tagged twice
function L.Tag(cat, sign, info)
    info = info or {}
    if info.key then
        for _, t in ipairs(tags) do if t.key == info.key then return end end
    end
    info.cat, info.sign, info.t = cat, sign, GetTime()
    info.ttl = info.expect and 20 or 6
    tags[#tags + 1] = info
end

-- Returns a list of tags explaining this delta (several when the server merged
-- multiple mail collections into one money update), or nil.
local function takeTags(delta, now)
    for i = #tags, 1, -1 do
        if now - tags[i].t > tags[i].ttl then table.remove(tags, i) end
    end
    -- 1) exact amount match
    for i, tg in ipairs(tags) do
        if tg.expect and tg.expect == delta then
            table.remove(tags, i)
            return { tg }
        end
    end
    -- 2) coalesced: consecutive expected amounts that add up to this delta
    local sum, idx = 0, {}
    for i, tg in ipairs(tags) do
        if tg.expect and (tg.expect > 0) == (delta > 0) then
            sum = sum + tg.expect
            idx[#idx + 1] = i
            if sum == delta then
                local out = {}
                for j = #idx, 1, -1 do table.insert(out, 1, table.remove(tags, idx[j])) end
                return out
            end
            if (delta > 0 and sum > delta) or (delta < 0 and sum < delta) then break end
        end
    end
    -- 3) ordinary action tags (no fixed amount), sign must agree
    for i, tg in ipairs(tags) do
        if not tg.expect and (not tg.sign or (tg.sign > 0) == (delta > 0)) then
            table.remove(tags, i)
            return { tg }
        end
    end
end

local CTX_RULES = {
    { "loot",     "LOOT",        "OTHER_OUT" },
    { "quest",    "QUEST",       "OTHER_OUT" },
    { "auction",  "AH_REFUND",   "AH_DEPOSIT" },
    { "merchant", "VENDOR_SALE", "VENDOR_BUY" },
    { "mail",     "MAIL_IN",     "MAIL_OUT" },
    { "trade",    "TRADE_IN",    "TRADE_OUT" },
    { "taxi",     "OTHER_IN",    "TRAVEL" },
    { "trainer",  "OTHER_IN",    "TRAINING" },
    { "bank",     "OTHER_IN",    "BANK" },
}

local function contextCat(delta)
    for _, r in ipairs(CTX_RULES) do
        if inCtx(r[1]) then return delta > 0 and r[2] or r[3] end
    end
    return delta > 0 and "OTHER_IN" or "OTHER_OUT"
end

local function record(e)
    local led = ns.db.ledger
    led[#led + 1] = e
    local max = ns.S.ledgerMax or 5000
    while #led > max do table.remove(led, 1) end
    ns:Fire("LEDGER_ENTRY", e)
end

local function book(delta, at)
    local list = takeTags(delta, GetTime())
    if not list then
        record({ t = at, c = ns.CharKey(), k = contextCat(delta), a = delta })
    else
        for _, tg in ipairs(list) do
            record({ t = at, c = ns.CharKey(), k = tg.cat, a = (#list > 1 and tg.expect) or delta,
                i = tg.item, q = tg.qty, n = tg.note, f = tg.fee, g = tg.gross })
        end
    end
    ns:RefreshPage("gl")
end

function L.Delete(entry)
    local led = ns.db.ledger
    for i = #led, 1, -1 do
        if led[i] == entry then table.remove(led, i) break end
    end
    ns:RefreshPage("gl")
end

local function flush()
    local now = GetTime()
    local i = 1
    while i <= #pending do
        local p = pending[i]
        if now - p.t >= 0.7 then
            table.remove(pending, i)
            book(p.d, p.at)
        else
            i = i + 1
        end
    end
    if #pending > 0 then C_Timer.After(0.3, flush) end
end

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------
local function hook(tbl, name, fn)
    if type(tbl) == "table" and type(tbl[name]) == "function" then
        hooksecurefunc(tbl, name, function(...)
            local ok, err = pcall(fn, ...)
            if not ok then geterrorhandler()(err) end
        end)
    end
end

local function itemLinkFromID(id)
    if not id then return nil end
    local _, link = ns.GetItemInfo(id)
    return link
end

function L.SubjectCapture(fmt, fallback)
    if type(fmt) ~= "string" then return fallback end
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)")
    return "^" .. p .. "$"
end

-- Inbox snapshot (by index) taken on every MAIL_INBOX_UPDATE: a fallback for when
-- the live header is already gone by the time our hook runs.
L.inbox = {}
ns:On("MAIL_INBOX_UPDATE", function()
    wipe(L.inbox)
    if not GetInboxNumItems then return end
    for i = 1, (GetInboxNumItems() or 0) do
        local _, _, sender, subject, money, _, daysLeft = GetInboxHeaderInfo(i)
        local s = { sender = sender, subject = subject, money = money, daysLeft = daysLeft }
        local it, name, buyer, bid, _, dep, cons, _, _, _, count = GetInboxInvoiceInfo(i)
        s.invoiceType, s.itemName, s.buyer, s.bid, s.deposit, s.consignment, s.count = it, name, buyer, bid, dep, cons, count
        L.inbox[i] = s
    end
end)

local function subjectPattern(fmt, fallback)
    if type(fmt) ~= "string" then return fallback end
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", ".+")
    return "^" .. p
end

local lastSell -- legacy AH sell slot snapshot

local function InstallHooks()
    -- Auction house: buying (legacy + modern API)
    hook(_G, "PlaceAuctionBid", function(listType, index, bid)
        local link = GetAuctionItemLink and GetAuctionItemLink(listType, index)
        local _, _, count, _, _, _, _, _, _, buyout = GetAuctionItemInfo(listType, index)
        if buyout and buyout > 0 and bid and bid >= buyout then
            L.Tag("AH_BUY", -1, { item = link, qty = count })
        else
            L.Tag("AH_BID", -1, { item = link, qty = count, note = "bid (refunded if outbid)" })
        end
    end)
    if C_AuctionHouse then
        hook(C_AuctionHouse, "PlaceBid", function(auctionID, amount)
            local a = ns.Market and ns.Market.LookupAuction(auctionID)
            if a and a.buyout and amount and amount < a.buyout then
                L.Tag("AH_BID", -1, { item = a.link, qty = a.qty, note = "bid (refunded if outbid)" })
            else
                L.Tag("AH_BUY", -1, { item = a and a.link, qty = a and a.qty })
            end
        end)
        hook(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, qty)
            L.Tag("AH_BUY", -1, { item = itemLinkFromID(itemID), qty = qty })
        end)
        local function modernPost(loc, _, qty)
            local link = C_Item and C_Item.GetItemLink and loc and C_Item.GetItemLink(loc)
            L.Tag("AH_DEPOSIT", -1, { item = link, qty = qty })
            if ns.Portfolio then ns.Portfolio:OnPosted(link, qty) end
        end
        hook(C_AuctionHouse, "PostItem", modernPost)
        hook(C_AuctionHouse, "PostCommodity", modernPost)
    end
    -- Auction house: posting (legacy)
    local function legacyPost(_, _, _, stackSize, numStacks)
        local item = lastSell and (lastSell.link or lastSell.name)
        local qty = stackSize and numStacks and (stackSize * numStacks) or (lastSell and lastSell.count)
        L.Tag("AH_DEPOSIT", -1, { item = item, qty = qty })
        if ns.Portfolio then ns.Portfolio:OnPosted(item, qty) end
    end
    hook(_G, "PostAuction", legacyPost)
    hook(_G, "StartAuction", legacyPost)

    -- Mailbox: collecting money. Every mail tag carries the exact amount it will pay,
    -- so it can only ever be matched to that money change.
    local outbidPat = subjectPattern(_G.AUCTION_OUTBID_MAIL_SUBJECT, "^Outbid on")
    local cancelPat = subjectPattern(_G.AUCTION_REMOVED_MAIL_SUBJECT, "^Auction cancelled")
    local soldCap = L.SubjectCapture(_G.AUCTION_SOLD_MAIL_SUBJECT, "^Auction successful: (.+)$")
    local function onTakeMoney(index)
        local _, _, sender, subject, money, cod, daysLeft = GetInboxHeaderInfo(index)
        local snap = L.inbox[index]
        if (not money or money <= 0) and snap then
            sender, subject, money, daysLeft = snap.sender, snap.subject, snap.money, snap.daysLeft
        end
        if not money or money <= 0 then return end
        local key = tostring(sender) .. "|" .. tostring(subject) .. "|" .. money .. "|" .. floor((daysLeft or 0) * 1440)

        local invoiceType, itemName, buyer, bid, _, deposit, consignment, _, _, _, count = GetInboxInvoiceInfo(index)
        if not invoiceType and GetInboxText and subject and subject:match(soldCap) then
            pcall(GetInboxText, index) -- invoice data is only available once the mail text is loaded
            invoiceType, itemName, buyer, bid, _, deposit, consignment, _, _, _, count = GetInboxInvoiceInfo(index)
        end
        if not invoiceType and snap and snap.invoiceType then
            invoiceType, itemName, buyer, bid, deposit, consignment, count =
                snap.invoiceType, snap.itemName, snap.buyer, snap.bid, snap.deposit, snap.consignment, snap.count
        end

        local soldName = subject and subject:match(soldCap)
        if invoiceType == "seller" or soldName then
            local name, qty = itemName, count
            if not name and soldName then
                name = soldName
                local n, c = soldName:match("^(.-)%s*%((%d+)%)$")
                if n then name, qty = n, tonumber(c) end
            end
            L.Tag("AH_SALE", 1, {
                expect = money, key = key, item = name, qty = qty, fee = consignment, gross = bid,
                note = bid and format("to %s · gross %s · cut %s", buyer or "?", ns.MoneyShort(bid or 0), ns.MoneyShort(consignment or 0)) or nil,
            })
        elseif subject and (subject:match(outbidPat) or subject:match(cancelPat)) then
            L.Tag("AH_REFUND", 1, { expect = money, key = key, note = subject })
        else
            L.Tag("MAIL_IN", 1, { expect = money, key = key, note = (sender or "?") .. ": " .. (subject or "") })
        end
    end
    -- Won bids: the cost was paid at bid time; book the basis when the item is collected
    local seenWon = {}
    local function onTakeItem(index)
        local invoiceType, itemName, _, bid, buyout, _, _, _, _, _, count = GetInboxInvoiceInfo(index)
        if invoiceType ~= "buyer" or not bid or bid <= 0 then return end
        if buyout and buyout > 0 and bid >= buyout then return end -- buyouts were booked at click time
        local _, _, _, subject, _, _, daysLeft = GetInboxHeaderInfo(index)
        local key = tostring(subject) .. bid .. floor((daysLeft or 0) * 1440)
        if seenWon[key] then return end
        seenWon[key] = true
        if ns.Portfolio then ns.Portfolio:OnBidWon(itemName, count, bid) end
    end
    hook(_G, "TakeInboxMoney", onTakeMoney)
    hook(_G, "AutoLootMailItem", onTakeMoney)
    hook(_G, "AutoLootMailItem", onTakeItem)
    hook(_G, "TakeInboxItem", onTakeItem)
    hook(_G, "SendMail", function(recipient, subject)
        L.Tag("MAIL_OUT", -1, { note = "to " .. tostring(recipient) .. (subject and subject ~= "" and (": " .. subject) or "") })
        if ns.Portfolio then ns.Portfolio:OnMailSent(recipient) end
    end)

    -- Merchant
    local function onUseItem(bag, slot)
        if not (MerchantFrame and MerchantFrame:IsShown()) then return end
        local link, count = ns.GetSlotInfo(bag, slot)
        if not link then return end
        local vendor = select(11, ns.GetItemInfo(link))
        if vendor and vendor > 0 then L.Tag("VENDOR_SALE", 1, { item = link, qty = count }) end
    end
    if C_Container then hook(C_Container, "UseContainerItem", onUseItem) end
    hook(_G, "UseContainerItem", onUseItem)
    hook(_G, "BuyMerchantItem", function(index, qty)
        local link = GetMerchantItemLink(index)
        local stack
        if GetMerchantItemInfo then
            stack = select(4, GetMerchantItemInfo(index))
        elseif C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local info = C_MerchantFrame.GetItemInfo(index)
            stack = info and info.stackCount
        end
        L.Tag("VENDOR_BUY", -1, { item = link, qty = qty or stack })
    end)
    hook(_G, "BuybackItem", function(index)
        L.Tag("VENDOR_BUY", -1, { item = GetBuybackItemLink and GetBuybackItemLink(index), note = "buyback" })
    end)
    hook(_G, "RepairAllItems", function(guild)
        if not guild then L.Tag("REPAIR", -1, {}) end
    end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local CTX_EVENTS = {
    MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
    AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction", false },
    MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
    TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
    TAXIMAP_OPENED = { "taxi", true }, TAXIMAP_CLOSED = { "taxi", false },
    TRAINER_SHOW = { "trainer", true }, TRAINER_CLOSED = { "trainer", false },
    BANKFRAME_OPENED = { "bank", true }, BANKFRAME_CLOSED = { "bank", false },
    LOOT_OPENED = { "loot", true }, LOOT_CLOSED = { "loot", false },
    QUEST_COMPLETE = { "quest", true }, QUEST_FINISHED = { "quest", false },
}
for ev, v in pairs(CTX_EVENTS) do
    ns:On(ev, function() setCtx(v[1], v[2]) end)
end

ns:On("CHAT_MSG_MONEY", function() L.Tag("LOOT", 1, {}) end)
ns:On("QUEST_TURNED_IN", function(_, _, money)
    if money and money > 0 then L.Tag("QUEST", 1, {}) end
end)
ns:On("NEW_AUCTION_UPDATE", function()
    if not GetAuctionSellItemInfo then return end
    local name, _, count, _, _, _, _, _, _, itemID = GetAuctionSellItemInfo()
    if name then lastSell = { name = name, count = count, link = itemLinkFromID(itemID) } end
end)

ns:On("PLAYER_MONEY", function()
    if not lastMoney then lastMoney = GetMoney() return end
    local m = GetMoney()
    local d = m - lastMoney
    lastMoney = m
    if d == 0 then return end
    pending[#pending + 1] = { d = d, t = GetTime(), at = time() }
    C_Timer.After(0.8, flush)
end)

ns:OnInit(function()
    lastMoney = GetMoney()
    InstallHooks()
end)

---------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------
local RANGES = { ["24H"] = 86400, ["7D"] = 7 * 86400, ["30D"] = 30 * 86400, ALL = nil }

function L.Query(range, group, scope)
    local out = {}
    local since = RANGES[range] and (time() - RANGES[range]) or 0
    local me = ns.CharKey()
    local led = ns.db.ledger
    for i = #led, 1, -1 do
        local e = led[i]
        if e.t < since then break end
        local cat = L.CATS[e.k]
        if (scope == "ALL" or e.c == me) and (group == "ALL" or (cat and cat[2] == group)) then
            out[#out + 1] = e
        end
    end
    return out
end

function L.Net(seconds, charOnly)
    local since, me, sum = time() - seconds, ns.CharKey(), 0
    local led = ns.db.ledger
    for i = #led, 1, -1 do
        local e = led[i]
        if e.t < since then break end
        if not charOnly or e.c == me then sum = sum + e.a end
    end
    return sum
end

function ns.CharLabel(key)
    local ch = ns.db.chars[key]
    local name = (key or "?"):match("^(.-)%-") or key
    if ch and ch.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[ch.class] then
        local cc = RAID_CLASS_COLORS[ch.class]
        return format("|cff%02x%02x%02x%s|r", math.floor(cc.r * 255), math.floor(cc.g * 255), math.floor(cc.b * 255), name)
    end
    return name
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local view = { range = "7D", group = "ALL", scope = "ALL" }

local function build(p)
    local W = ns.PAGE_W
    local rangeSeg = UI.Segment(p, { { "24H", "24H" }, { "7D", "7D" }, { "30D", "30D" }, { "ALL", "ALL" } },
        function(v) view.range = v; ns:RefreshPage("gl") end, 44, 20)
    rangeSeg:SetPoint("TOPLEFT", 0, 0)
    local groupSeg = UI.Segment(p, { { "ALL", "ALL" }, { "AH", "AUCTION" }, { "VENDOR", "VENDOR" }, { "LOOT", "LOOT" }, { "OTHER", "OTHER" } },
        function(v) view.group = v; ns:RefreshPage("gl") end, 64, 20)
    groupSeg:SetPoint("LEFT", rangeSeg, "RIGHT", 14, 0)
    local scopeSeg = UI.Segment(p, { { "ME", "THIS CHAR" }, { "ALL", "ALL CHARS" } },
        function(v) view.scope = v; ns:RefreshPage("gl") end, 78, 20)
    scopeSeg:SetPoint("TOPRIGHT", 0, 0)
    rangeSeg:Select(view.range); groupSeg:Select(view.group); scopeSeg:Select(view.scope)

    local kw = (W - 4 * 6) / 5
    p.kpi = {}
    local labels = { "Inflows", "Outflows", "Net cash flow", "AH net P&L", "AH turnover" }
    for i, l in ipairs(labels) do
        local k = UI.KPI(p, l, kw, 56)
        k:SetPoint("TOPLEFT", (i - 1) * (kw + 6), -28)
        p.kpi[i] = k
    end

    local listW, sideW = 566, W - 566 - 8
    local secL = UI.Section(p, "Journal entries", true); secL:SetPoint("TOPLEFT", 0, -92); secL:SetWidth(listW)
    p.secL = secL
    p.list = UI.Table(p, {
        { title = "Date", width = 76 },
        { title = "Acct", width = 78 },
        { title = "Type", width = 104 },
        { title = "Instrument", width = 174 },
        { title = "Qty", width = 34, justify = "RIGHT" },
        { title = "Amount", width = 90, justify = "RIGHT" },
    }, listW, ns.PAGE_H - 112, 16)
    p.list:SetPoint("TOPLEFT", 0, -112)
    p.list:SetEmptyText("No journal entries in this window.\nGo make (or spend) some money.")

    local secR = UI.Section(p, "Breakdown by account"); secR:SetPoint("TOPLEFT", listW + 8, -92); secR:SetWidth(sideW)
    p.side = UI.Table(p, {
        { title = "Category", width = 128 },
        { title = "#", width = 36, justify = "RIGHT" },
        { title = "Total", width = 116, justify = "RIGHT" },
    }, sideW, ns.PAGE_H - 112, 16)
    p.side:SetPoint("TOPLEFT", listW + 8, -112)
end

local function refresh(p)
    local rows = L.Query(view.range, view.group, view.scope == "ALL" and "ALL" or "ME")
    local inflow, outflow = 0, 0
    local ahBuy, ahSell, ahFee, ahRefund, ahTrades = 0, 0, 0, 0, 0
    local byCat = {}
    local data = {}
    for _, e in ipairs(rows) do
        if e.a > 0 then inflow = inflow + e.a else outflow = outflow + e.a end
        local bc = byCat[e.k] or { n = 0, sum = 0 }
        bc.n, bc.sum = bc.n + 1, bc.sum + e.a
        byCat[e.k] = bc
        if e.k == "AH_BUY" then ahBuy = ahBuy + e.a; ahTrades = ahTrades + 1
        elseif e.k == "AH_SALE" then ahSell = ahSell + e.a; ahTrades = ahTrades + 1
        elseif e.k == "AH_DEPOSIT" then ahFee = ahFee + e.a
        elseif e.k == "AH_REFUND" then ahRefund = ahRefund + e.a end

        local cat = L.CATS[e.k] or { e.k }
        local item = e.i or (e.n and ns.Color("grey", e.n)) or ns.Color("dim", "—")
        data[#data + 1] = {
            cells = {
                ns.Color("grey", date("%m-%d %H:%M", e.t)),
                ns.CharLabel(e.c),
                cat[1],
                item,
                e.q and tostring(e.q) or "",
                ns.PnL(e.a),
            },
            link = e.i and e.i:find("|H") and e.i or nil,
            tooltip = function(tt)
                if e.i and e.i:find("|H") then
                    pcall(tt.SetHyperlink, tt, e.i)
                    tt:AddLine(" ")
                end
                tt:AddLine(cat[1], 1, 0.55, 0.12)
                if e.i and not e.i:find("|H") then tt:AddLine(e.i, 1, 1, 1) end
                if e.n then tt:AddLine(e.n, 0.8, 0.8, 0.8, true) end
                tt:AddDoubleLine("Amount", ns.Money(e.a, true), 0.8, 0.8, 0.8, 1, 1, 1)
                if e.q and e.q > 0 then tt:AddDoubleLine("Per unit", ns.Money(math.abs(e.a) / e.q), 0.8, 0.8, 0.8, 1, 1, 1) end
                if e.f and e.f > 0 then tt:AddDoubleLine("AH cut", ns.Money(e.f), 0.8, 0.8, 0.8, 1, 1, 1) end
                if e.r then tt:AddDoubleLine("Realized vs avg cost", ns.Money(e.r, true), 0.8, 0.8, 0.8, 1, 1, 1) end
                tt:AddLine(date("%Y-%m-%d %H:%M:%S", e.t), 0.5, 0.5, 0.55)
                tt:AddLine("|cffffc238Right-click|r to delete this entry", 0.5, 0.5, 0.55)
            end,
            onClick = function(button)
                if button == "RightButton" then
                    UI.Confirm("Delete this ledger entry?\n" .. cat[1] .. "  " .. ns.MoneyShort(e.a, true), function() L.Delete(e) end)
                end
            end,
        }
    end
    p.list:SetData(data, true)
    p.secL.right:SetText(#rows .. " ENTRIES")

    local side = {}
    for k, v in pairs(byCat) do
        side[#side + 1] = { k = k, cells = { (L.CATS[k] or { k })[1], tostring(v.n), ns.PnL(v.sum) }, sum = v.sum }
    end
    table.sort(side, function(a, b) return a.sum > b.sum end)
    p.side:SetData(side)

    local net = inflow + outflow
    local ahNet = ahSell + ahBuy + ahFee + ahRefund
    p.kpi[1].value:SetText(ns.Color("green", ns.MoneyShort(inflow)))
    p.kpi[1].sub:SetText("money in")
    p.kpi[2].value:SetText(ns.Color("red", ns.MoneyShort(outflow)))
    p.kpi[2].sub:SetText("money out")
    p.kpi[3].value:SetText(ns.PnL(net))
    p.kpi[3].sub:SetText(view.range .. " · " .. (view.scope == "ALL" and "all characters" or "this character"))
    p.kpi[4].value:SetText(ns.PnL(ahNet))
    p.kpi[4].sub:SetText("sales " .. ns.MoneyShort(ahSell) .. " · fees " .. ns.MoneyShort(-ahFee))
    p.kpi[5].value:SetText(ns.Color("amber", ahTrades .. " fills"))
    p.kpi[5].sub:SetText("bought " .. ns.MoneyShort(-ahBuy) .. " · sold " .. ns.MoneyShort(ahSell))
end

ns:RegisterPage({ id = "gl", order = 6, code = "GL", title = "Ledger", build = build, refresh = refresh })

ns:AddTicker(function()
    if not ns.db then return end
    return "GL 24H NET " .. ns.PnL(L.Net(86400))
end)
