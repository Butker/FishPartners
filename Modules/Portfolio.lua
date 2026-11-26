-- Fish & Partners: Portfolio Management
-- Every item on every character (bags, bank, mailbox, AH listings), with a cost basis.
--
-- Cost basis model (account-wide, per itemID), weighted average cost:
--   * BUY (AH buyout, won bid, vendor):  avg = (qty*avg + paid) / (qty + bought); qty += bought
--   * SELL (AH sale, vendor sale):       realized += sold * (price - avg); qty -= sold; avg unchanged
--   * Items that disappear (used, crafted, traded away) reduce qty; avg unchanged
--   * When qty reaches 0 the next buy starts fresh at the price you actually paid
--   * Looted/crafted units are "uncosted": they don't drag your average down
--   * You can set avg + qty manually at any time (for stock bought before the addon)

local _, ns = ...
local UI, C = ns.UI, ns.C
local P = {}
ns.Portfolio = P
local floor, min, max = math.floor, math.min, math.max

local LOCS = { { "b", "Bags" }, { "k", "Bank" }, { "m", "Mail" }, { "a", "AH" } }

ns:OnInit(function()
    ns.db.basis = ns.db.basis or {}
    ns.db.links = ns.db.links or {}
    ns.db.realized = ns.db.realized or 0
    ns.db.hidden = ns.db.hidden or {}
end)

---------------------------------------------------------------------------
-- Blacklist: hidden items are kept out of the portfolio, AUM inventory value and ticker
---------------------------------------------------------------------------
function P:IsHidden(id) return id and ns.db.hidden and ns.db.hidden[id] or false end
function ns.IsHiddenItem(linkOrID) return P:IsHidden(P.ID(linkOrID)) end

function P:SetHidden(id, hidden)
    if not id then return end
    ns.db.hidden[id] = hidden and true or nil
    local link = P.Link(id) or ("item " .. id)
    if hidden then
        ns.Print("Hidden " .. link .. ". Find it under " .. ns.Color("amber", "HIDDEN") .. " on the Portfolio page to restore.")
    else
        ns.Print("Restored " .. link .. " to the portfolio.")
    end
    if ns.Wealth then ns.Wealth:ScanBags() end
    -- bank value: drop/restore hidden items without needing a bank visit
    for _, ch in pairs(ns.db.chars) do
        local e = ch.inv and ch.inv[id]
        if e and e.k and ch.bankT and link then
            local unit = ns.Valuate(link, e.bound) or 0
            ch.bank = math.max(0, (ch.bank or 0) + (hidden and -1 or 1) * unit * e.k)
        end
    end
    self:Changed()
end

---------------------------------------------------------------------------
-- Money input helpers
---------------------------------------------------------------------------
-- Accepts "2g 50s 3c", "2.5g", "250s", "2,5" (gold), "2.5" (gold)
function ns.ParseMoney(s)
    s = (s or ""):lower():gsub("%s+", ""):gsub(",", ".")
    if s == "" then return nil end
    local total, matched = 0, false
    for num, unit in s:gmatch("([%d%.]+)([gsc])") do
        local n = tonumber(num)
        if not n then return nil end
        matched = true
        total = total + n * (unit == "g" and 10000 or unit == "s" and 100 or 1)
    end
    if matched then return floor(total + 0.5) end
    local n = tonumber(s)
    if n then return floor(n * 10000 + 0.5) end
end

function ns.MoneyPlain(c)
    c = floor((c or 0) + 0.5)
    local g, s, cc = floor(c / 10000), floor(c / 100) % 100, c % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. "g" end
    if s > 0 then out[#out + 1] = s .. "s" end
    if cc > 0 or #out == 0 then out[#out + 1] = cc .. "c" end
    return table.concat(out, " ")
end

---------------------------------------------------------------------------
-- Inventory model: db.chars[key].inv[itemID] = { b=bags, k=bank, m=mail, a=listed, bound=bool }
---------------------------------------------------------------------------
function P.ID(x)
    if not x then return nil end
    if type(x) == "number" then return x end
    local id = x:match("item:(%d+)")
    if id then return tonumber(id) end
    local _, link = ns.GetItemInfo(x)
    if link then return tonumber(link:match("item:(%d+)")) end
    for iid, l in pairs(ns.db.links) do
        if ns.LinkName(l) == x then return iid end
    end
end

function P.Link(id)
    local l = ns.db.links[id]
    if l then return l end
    local _, link = ns.GetItemInfo(id)
    if link then ns.db.links[id] = link end
    return link
end

local function invOf(key)
    local ch = ns.db.chars[key or ns.CharKey()]
    if not ch then return nil end
    ch.inv = ch.inv or {}
    return ch.inv
end

local function prune(t, id)
    local e = t[id]
    if e and not (e.b or e.k or e.m or e.a) then t[id] = nil end
end

-- Replace one location for the current character. counts[id] = { q=, link=, bound= }
function P:SetLocation(loc, counts)
    local t = invOf()
    if not t then return end
    for id, e in pairs(t) do e[loc] = nil end
    for id, c in pairs(counts) do
        local e = t[id] or {}
        t[id] = e
        if c.q and c.q > 0 then e[loc] = c.q end
        if c.bound then e.bound = true end
        if c.link and not ns.db.links[id] then ns.db.links[id] = c.link end
    end
    for id in pairs(t) do prune(t, id) end
    self:Changed()
end

function P:Add(key, loc, id, q)
    local t = invOf(key)
    if not t or not id or not q then return end
    local e = t[id] or {}
    t[id] = e
    e[loc] = max(0, (e[loc] or 0) + q)
    if e[loc] == 0 then e[loc] = nil end
    prune(t, id)
end

function P:Held(id, scopeKey, loc)
    local n = 0
    for key, ch in pairs(ns.db.chars) do
        if (not scopeKey or key == scopeKey) and ch.inv and ch.inv[id] then
            local e = ch.inv[id]
            if loc then n = n + (e[loc] or 0)
            else n = n + (e.b or 0) + (e.k or 0) + (e.m or 0) + (e.a or 0) end
        end
    end
    return n
end

---------------------------------------------------------------------------
-- Cost basis
---------------------------------------------------------------------------
function P:Basis(id) return ns.db.basis[id] end

-- Safe = we have a full picture of this character (bank scanned) and no AH/mail
-- transaction is mid-flight. Otherwise we never shrink a basis.
function P:SafeToReconcile(ignoreCtx)
    local ch = ns.db.chars[ns.CharKey()]
    if not ch or not ch.bankT then return false end
    if not ignoreCtx and ns.Ledger and (ns.Ledger.InCtx("auction", 4) or ns.Ledger.InCtx("mail", 4)) then return false end
    return true
end

function P:Reconcile(id, ignoreCtx)
    if not self:SafeToReconcile(ignoreCtx) then return end
    local function one(iid, b)
        local h = self:Held(iid)
        if h < b.qty then b.qty = h end
    end
    if id then
        if ns.db.basis[id] then one(id, ns.db.basis[id]) end
    else
        for iid, b in pairs(ns.db.basis) do one(iid, b) end
    end
end

function P:Buy(id, q, paid)
    if not id or not q or q <= 0 or not paid or paid <= 0 then return end
    self:Reconcile(id, true)
    local b = ns.db.basis[id] or { qty = 0, avg = 0, realized = 0 }
    local newQ = b.qty + q
    b.avg = (b.qty * b.avg + paid) / newQ
    b.qty = newQ
    b.t = time()
    b.src = "auto"
    ns.db.basis[id] = b
end

function P:Sell(id, q, proceeds)
    local b = id and ns.db.basis[id]
    if not b or b.qty <= 0 or not q or q <= 0 then return nil end
    local cq = min(q, b.qty)
    local r = cq * (proceeds / q - b.avg)
    b.realized = (b.realized or 0) + r
    ns.db.realized = (ns.db.realized or 0) + r
    b.qty = b.qty - cq
    return r
end

function P:SetBasis(id, avg, qty)
    local old = ns.db.basis[id]
    ns.db.basis[id] = { qty = max(0, qty or 0), avg = max(0, avg or 0), t = time(), src = "manual",
        realized = old and old.realized or 0 }
    self:Changed()
end

function P:ClearBasis(id)
    ns.db.basis[id] = nil
    self:Changed()
end

---------------------------------------------------------------------------
-- Change pipeline (throttled): reconcile, value mail/listings for AUM, refresh pages
---------------------------------------------------------------------------
local pendingChange
function P:Changed()
    if pendingChange then return end
    pendingChange = true
    C_Timer.After(0.5, function()
        pendingChange = nil
        P:Reconcile()
        -- value of mail + AH listings per character (feeds AUM)
        for _, ch in pairs(ns.db.chars) do
            local v = 0
            for id, e in pairs(ch.inv or {}) do
                local q = (e.m or 0) + (e.a or 0)
                if q > 0 and not P:IsHidden(id) then
                    local link = P.Link(id)
                    local unit = link and ns.Valuate(link, e.bound)
                    v = v + (unit or 0) * q
                end
            end
            ch.otherV = v
        end
        if ns.Wealth then ns.Wealth:Snapshot() end
        ns:RefreshPage("port")
        ns:RefreshPage("aum")
    end)
end

---------------------------------------------------------------------------
-- Feeds: mailbox, AH listings, mail to alts, ledger events
---------------------------------------------------------------------------
-- Mail item APIs gained an itemID return in newer clients:
--   GetInboxItem:    modern 6 returns (name, itemID, tex, count, ...), legacy 5 (name, tex, count, ...)
--   GetSendMailItem: modern 5 returns (name, itemID, tex, count, q),   legacy 4 (name, tex, count, q)
local function countArg(modernN, ...)
    if select("#", ...) >= modernN then return (select(4, ...)) end
    return (select(3, ...))
end

local mailThrottle
ns:On("MAIL_INBOX_UPDATE", function()
    if not ns.db or mailThrottle then return end
    mailThrottle = true
    C_Timer.After(0.5, function()
        mailThrottle = nil
        if not GetInboxNumItems then return end
        local counts = {}
        for i = 1, (GetInboxNumItems() or 0) do
            for a = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
                local link = GetInboxItemLink and GetInboxItemLink(i, a)
                if link then
                    local id = P.ID(link)
                    local q = tonumber(countArg(6, GetInboxItem(i, a))) or 1
                    if id then
                        local c = counts[id] or { q = 0, link = link }
                        c.q = c.q + q
                        counts[id] = c
                    end
                end
            end
        end
        P:SetLocation("m", counts)
    end)
end)

local function scanOwnedLegacy()
    if not GetNumAuctionItems then return end
    local counts = {}
    for i = 1, (GetNumAuctionItems("owner") or 0) do
        local _, _, count = GetAuctionItemInfo("owner", i)
        local link = GetAuctionItemLink("owner", i)
        local id = P.ID(link)
        if id and count and count > 0 then
            local c = counts[id] or { q = 0, link = link }
            c.q = c.q + count
            counts[id] = c
        end
    end
    P:SetLocation("a", counts)
end
local function scanOwnedModern()
    if not (C_AuctionHouse and C_AuctionHouse.GetNumOwnedAuctions) then return end
    local counts = {}
    for i = 1, (C_AuctionHouse.GetNumOwnedAuctions() or 0) do
        local info = C_AuctionHouse.GetOwnedAuctionInfo(i)
        local id = info and info.itemKey and info.itemKey.itemID
        if id then
            local c = counts[id] or { q = 0, link = info.itemLink }
            c.q = c.q + (info.quantity or 1)
            counts[id] = c
        end
    end
    P:SetLocation("a", counts)
end
ns:On("AUCTION_OWNED_LIST_UPDATE", function() if ns.db then scanOwnedLegacy() end end)
ns:On("OWNED_AUCTIONS_UPDATED", function() if ns.db then scanOwnedModern() end end)
ns:On("AUCTION_HOUSE_CLOSED", function() if ns.db then C_Timer.After(5, function() P:Changed() end) end end)
ns:On("MAIL_CLOSED", function() if ns.db then C_Timer.After(5, function() P:Changed() end) end end)

-- Called by ledger hooks
function P:OnPosted(linkOrID, qty)
    local id = P.ID(linkOrID)
    if id and qty and qty > 0 then self:Add(nil, "a", id, qty) end
end

function P:OnBidWon(itemName, count, bid)
    local id = P.ID(itemName)
    if id then self:Buy(id, count or 1, bid); self:Changed() end
end

function P:OnMailSent(recipient)
    if not recipient or recipient == "" then return end
    local key = recipient:find("-") and recipient or (recipient .. "-" .. (GetRealmName() or ""))
    local target
    for k in pairs(ns.db.chars) do
        if k:lower() == key:lower() then target = k end
    end
    if not target or target == ns.CharKey() then return end
    for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
        local link = GetSendMailItemLink and GetSendMailItemLink(i)
        if link then
            local id = P.ID(link)
            local q = tonumber(countArg(5, GetSendMailItem(i))) or 1
            if id then
                if not ns.db.links[id] then ns.db.links[id] = link end
                self:Add(target, "m", id, q)
            end
        end
    end
    self:Changed()
end

ns:Listen("LEDGER_ENTRY", function(e)
    if e.c ~= ns.CharKey() then return end
    local id = P.ID(e.i)
    if not id or not e.q or e.q <= 0 then return end
    if e.k == "AH_BUY" then
        P:Buy(id, e.q, -e.a)
        P:Add(nil, "m", id, e.q) -- in transit to the mailbox
    elseif e.k == "VENDOR_BUY" then
        P:Buy(id, e.q, -e.a)
    elseif e.k == "AH_SALE" then
        e.r = P:Sell(id, e.q, e.a)
        P:Add(nil, "a", id, -e.q)
    elseif e.k == "VENDOR_SALE" then
        e.r = P:Sell(id, e.q, e.a)
    else
        return
    end
    P:Changed()
end)

ns:Listen("VALUATION_CHANGED", function() P:Changed() end)

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local view = { scope = "ALL", loc = "ALL", sort = "VALUE", search = "", hidden = false }

local function Input(parent, w, numeric)
    local box = UI.Panel(parent, { 0, 0, 0 })
    box:SetSize(w, 22)
    local eb = CreateFrame("EditBox", nil, box)
    eb:SetPoint("TOPLEFT", 6, 0); eb:SetPoint("BOTTOMRIGHT", -6, 0)
    eb:SetFont(UI.FONT, 12, "")
    eb:SetTextColor(C.amber[1], C.amber[2], C.amber[3])
    eb:SetAutoFocus(false)
    if numeric then eb:SetNumeric(true) end
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusGained", function() UI.SetBorderColor(box, C.orange) end)
    eb:SetScript("OnEditFocusLost", function() UI.SetBorderColor(box, C.line) end)
    box.eb = eb
    return box
end

local function BuildEditor(p)
    local ed = UI.Panel(p, C.panel2)
    UI.SetBorderColor(ed, C.orange)
    ed:SetSize(420, 214)
    ed:SetPoint("CENTER", 0, 10)
    ed:SetFrameLevel(p:GetFrameLevel() + 30)
    ed:EnableMouse(true)
    ed:Hide()

    local head = UI.Panel(ed, C.orange, false)
    head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1); head:SetHeight(20)
    local ht = UI.Text(head, 11, { 0, 0, 0 }, "LEFT", UI.FONT, "")
    ht:SetPoint("LEFT", 8, 0); ht:SetText("COST BASIS  ·  SET YOUR BUY PRICE")

    ed.item = UI.Text(ed, 13, C.white); ed.item:SetPoint("TOPLEFT", 12, -30); ed.item:SetWidth(396)
    ed.info = UI.Text(ed, 10, C.grey); ed.info:SetPoint("TOPLEFT", 12, -50); ed.info:SetWidth(396)
    ed.cur = UI.Text(ed, 10, C.grey); ed.cur:SetPoint("TOPLEFT", 12, -64); ed.cur:SetWidth(396)

    local l1 = UI.Text(ed, 11, C.white); l1:SetPoint("TOPLEFT", 12, -92); l1:SetText("Avg buy price per unit")
    ed.price = Input(ed, 150); ed.price:SetPoint("TOPRIGHT", -12, -88)
    local h1 = UI.Text(ed, 9, C.dim); h1:SetPoint("TOPRIGHT", ed.price, "BOTTOMRIGHT", 0, -2); h1:SetText("e.g.  2g 50s   ·   2.5   ·   75s")
    local l2 = UI.Text(ed, 11, C.white); l2:SetPoint("TOPLEFT", 12, -130); l2:SetText("Units at this price")
    ed.qty = Input(ed, 150, true); ed.qty:SetPoint("TOPRIGHT", -12, -126)
    ed.preview = UI.Text(ed, 11, C.white); ed.preview:SetPoint("TOPLEFT", 12, -158); ed.preview:SetWidth(396)

    local set = UI.Button(ed, "SET BASIS", 110, 22, "primary"); set:SetPoint("BOTTOMRIGHT", -12, 10)
    local cancel = UI.Button(ed, "CANCEL", 80, 22, "default"); cancel:SetPoint("RIGHT", set, "LEFT", -6, 0)
    local clear = UI.Button(ed, "CLEAR BASIS", 100, 22, "danger"); clear:SetPoint("BOTTOMLEFT", 12, 10)

    local function preview()
        local avg = ns.ParseMoney(ed.price.eb:GetText())
        local q = tonumber(ed.qty.eb:GetText())
        if not avg or not q then ed.preview:SetText(ns.Color("dim", "Enter a price and quantity.")) return end
        local cost = avg * q
        local mv = (ed.unit or 0) * q
        local d = mv - cost
        ed.preview:SetText("Cost " .. ns.MoneyShort(cost) .. "   ·   Mkt " .. ns.MoneyShort(mv) .. "   ·   P&L " .. ns.PnL(d)
            .. (cost > 0 and ns.Color("grey", format("  (%s)", ns.Pct(100 * d / cost, true))) or ""))
    end
    ed.price.eb:SetScript("OnTextChanged", preview)
    ed.qty.eb:SetScript("OnTextChanged", preview)
    local function apply()
        local avg = ns.ParseMoney(ed.price.eb:GetText())
        local q = tonumber(ed.qty.eb:GetText())
        if not avg or not q then ns.Print("Enter a valid price (e.g. 2g 50s) and quantity.") return end
        P:SetBasis(ed.id, avg, q)
        ns.Print("Cost basis booked: " .. (P.Link(ed.id) or ed.id) .. " " .. q .. " @ " .. ns.Money(avg))
        ed:Hide()
    end
    ed.price.eb:SetScript("OnEnterPressed", apply)
    ed.qty.eb:SetScript("OnEnterPressed", apply)
    ed.price.eb:SetScript("OnTabPressed", function() ed.qty.eb:SetFocus() end)
    ed.qty.eb:SetScript("OnTabPressed", function() ed.price.eb:SetFocus() end)
    set:SetScript("OnClick", apply)
    cancel:SetScript("OnClick", function() ed:Hide() end)
    clear:SetScript("OnClick", function() P:ClearBasis(ed.id); ed:Hide() end)

    function ed:Open(id)
        self.id = id
        local link = P.Link(id) or ("item:" .. id)
        local held = P:Held(id)
        local b = P:Basis(id)
        self.unit = select(1, ns.Valuate(link)) or 0
        self.item:SetText(link)
        self.info:SetText(format("Held across all accounts: %s   ·   Market: %s / unit", ns.Color("white", held), ns.MoneyShort(self.unit)))
        if b then
            self.cur:SetText(format("Current basis: %s on %d units (%s, %s)", ns.MoneyShort(b.avg), b.qty, b.src or "auto",
                b.t and date("%Y-%m-%d", b.t) or "?"))
            self.price.eb:SetText(ns.MoneyPlain(b.avg))
        else
            self.cur:SetText(ns.Color("dim", "No cost basis yet: this position is uncosted."))
            self.price.eb:SetText("")
        end
        self.qty.eb:SetText(tostring(held))
        self:Show()
        self.price.eb:SetFocus()
        self.price.eb:HighlightText()
        preview()
    end
    return ed
end

local function build(p)
    local W = ns.PAGE_W
    local scopeSeg = UI.Segment(p, { { "ALL", "ALL CHARS" }, { "SPLIT", "BY CHAR" }, { "ME", "THIS CHAR" } },
        function(v) view.scope = v; ns:RefreshPage("port") end, 66, 20)
    scopeSeg.buttons[2].tip = "One foldable group per character. Click a character to fold it out; Shift-click to fold all."
    scopeSeg:SetPoint("TOPLEFT", 0, 0); scopeSeg:Select(view.scope)
    local locSeg = UI.Segment(p, { { "ALL", "ALL" }, { "b", "BAGS" }, { "k", "BANK" }, { "m", "MAIL" }, { "a", "AH" } },
        function(v) view.loc = v; ns:RefreshPage("port") end, 44, 20)
    locSeg:SetPoint("LEFT", scopeSeg, "RIGHT", 10, 0); locSeg:Select(view.loc)
    local hidSeg = UI.Segment(p, { { false, "ACTIVE" }, { true, "HIDDEN" } },
        function(v) view.hidden = v; ns:RefreshPage("port") end, 50, 20)
    hidSeg:SetPoint("LEFT", locSeg, "RIGHT", 10, 0); hidSeg:Select(view.hidden)
    hidSeg.buttons[2].tip = "Items you Ctrl-clicked away. Ctrl-click one here to restore it."
    local sortSeg = UI.Segment(p, { { "VALUE", "VALUE" }, { "PNL", "P&L" }, { "NAME", "A-Z" } },
        function(v) view.sort = v; ns:RefreshPage("port") end, 46, 20)
    sortSeg:SetPoint("TOPRIGHT", 0, 0); sortSeg:Select(view.sort)
    local search = Input(p, 120)
    search:SetHeight(20)
    search:SetPoint("RIGHT", sortSeg, "LEFT", -10, 0)
    local sh = UI.Text(search, 10, C.dim); sh:SetPoint("LEFT", 6, 0); sh:SetText("search ticker…")
    search.eb:SetScript("OnTextChanged", function(self)
        view.search = (self:GetText() or ""):lower()
        sh:SetShown(view.search == "")
        ns:RefreshPage("port")
    end)

    local kw = (W - 4 * 6) / 5
    local labels = { "Market value", "Cost basis", "Unrealized P&L", "Realized P&L · lifetime", "Basis coverage" }
    p.kpi = {}
    for i, l in ipairs(labels) do
        local k = UI.KPI(p, l, kw, 56)
        k:SetPoint("TOPLEFT", (i - 1) * (kw + 6), -28)
        p.kpi[i] = k
    end

    local sec = UI.Section(p, "Positions · click a row to set your buy price", true)
    sec:SetPoint("TOPLEFT", 0, -92); sec:SetWidth(W - 190)
    p.sec = sec
    local base = UI.Button(p, "BASELINE UNCOSTED @ MKT", 180, 18, "default")
    base:SetPoint("TOPRIGHT", 0, -91)
    base.label:SetFont(UI.FONT, 10, "")
    base.tip = "Give every uncosted position a cost basis equal to today's market price. Good starting point right after installing."
    base:SetScript("OnClick", function()
        UI.Confirm("Set cost basis = current market price for every position that has no basis?", function()
            local n = 0
            local seen = {}
            for _, ch in pairs(ns.db.chars) do
                for id, e in pairs(ch.inv or {}) do
                    if not seen[id] and not P:IsHidden(id) then
                        seen[id] = true
                        local b = P:Basis(id)
                        local held = P:Held(id)
                        local link = P.Link(id)
                        local unit = link and ns.Valuate(link, e.bound)
                        if held > 0 and unit and unit > 0 and (not b or b.qty == 0) then
                            P:SetBasis(id, unit, held); n = n + 1
                        end
                    end
                end
            end
            ns.Print("Baselined " .. n .. " positions at market.")
        end)
    end)

    p.list = UI.Table(p, {
        { title = "Instrument", width = 214 },
        { title = "Held", width = 50, justify = "RIGHT" },
        { title = "Avg cost", width = 82, justify = "RIGHT" },
        { title = "Mkt", width = 80, justify = "RIGHT" },
        { title = "Src", width = 38, justify = "CENTER" },
        { title = "Mkt value", width = 94, justify = "RIGHT" },
        { title = "Cost basis", width = 94, justify = "RIGHT" },
        { title = "Unreal P&L", width = 100, justify = "RIGHT" },
        { title = "P&L %", width = 64, justify = "RIGHT" },
    }, W, ns.PAGE_H - 112, 16)
    p.list:SetPoint("TOPLEFT", 0, -112)
    p.list:SetEmptyText("No positions yet. Open your bags, and visit your bank once per character.")

    p.editor = BuildEditor(p)
end

local SRC_COLOR = { AH = "cyan", VND = "grey", ["---"] = "dim" }

local function sortRows(rows)
    if view.sort == "PNL" then
        table.sort(rows, function(x, y) return x.upl < y.upl end)
    elseif view.sort == "NAME" then
        table.sort(rows, function(x, y) return x.name < y.name end)
    else
        table.sort(rows, function(x, y) return x.mv > y.mv end)
    end
end

-- Build item rows for one character (scopeKey) or all (nil).
-- The account-wide cost basis is allocated pro-rata to the units each character holds,
-- so per-character figures add up to the combined view.
local function buildRows(p, scopeKey, loc, indent)
    local agg = {}
    for key, ch in pairs(ns.db.chars) do
        if not scopeKey or key == scopeKey then
            for id, e in pairs(ch.inv or {}) do
                local q = loc and (e[loc] or 0) or ((e.b or 0) + (e.k or 0) + (e.m or 0) + (e.a or 0))
                if q > 0 then
                    local a = agg[id] or { q = 0 }
                    a.q = a.q + q
                    if e.bound then a.bound = true end
                    agg[id] = a
                end
            end
        end
    end
    local rows = {}
    local tMV, tCost, tCostedMV, tUPL = 0, 0, 0, 0
    for id, a in pairs(agg) do
        local link = P.Link(id)
        local name = link and ns.LinkName(link) or ("item " .. id)
        if (P:IsHidden(id) == view.hidden) and (view.search == "" or name:lower():find(view.search, 1, true)) then
            local unit, src = nil, "..."
            if link then unit, src = ns.Valuate(link, a.bound) end
            unit = unit or 0
            local mv = unit * a.q
            local b = P:Basis(id)
            local heldAll = P:Held(id)
            local cq = 0
            if b and heldAll > 0 then cq = min(b.qty, heldAll) * min(1, a.q / heldAll) end
            local cost = b and cq * b.avg or 0
            local upl = b and (cq * unit - cost) or 0
            tMV, tCost, tUPL = tMV + mv, tCost + cost, tUPL + upl
            tCostedMV = tCostedMV + cq * unit
            local avgTxt
            if b and b.qty > 0 then
                avgTxt = ns.MoneyShort(b.avg) .. (b.src == "manual" and ns.Color("orange", "*") or "")
                if cq < a.q - 0.001 then avgTxt = ns.Color("amber", "~") .. avgTxt end
            else
                avgTxt = ns.Color("dim", "set…")
            end
            rows[#rows + 1] = {
                mv = mv, upl = upl, name = name,
                cells = {
                    (indent or "") .. (link or name),
                    tostring(a.q),
                    avgTxt,
                    ns.MoneyShort(unit),
                    ns.Color(SRC_COLOR[src] or "grey", src or "---"),
                    ns.Color("white", ns.MoneyShort(mv)),
                    b and b.qty > 0 and ns.MoneyShort(cost) or ns.Color("dim", "—"),
                    b and b.qty > 0 and ns.PnL(upl) or ns.Color("dim", "uncosted"),
                    (cost > 0) and ((upl >= 0) and ns.Color("green", ns.Pct(100 * upl / cost, true)) or ns.Color("red", ns.Pct(100 * upl / cost))) or "",
                },
                tooltip = function(tt)
                    if link then pcall(tt.SetHyperlink, tt, link) else tt:AddLine(name) end
                    tt:AddLine(" ")
                    tt:AddLine("Where it is", 0.98, 0.55, 0.12)
                    for key, ch in pairs(ns.db.chars) do
                        local e = ch.inv and ch.inv[id]
                        if e then
                            local parts = {}
                            for _, L in ipairs(LOCS) do
                                if e[L[1]] then parts[#parts + 1] = L[2] .. " " .. e[L[1]] end
                            end
                            if #parts > 0 then tt:AddDoubleLine(ns.CharLabel(key), table.concat(parts, "  ·  "), 1, 1, 1, 0.85, 0.85, 0.85) end
                        end
                    end
                    if ns.Market then
                        local st = ns.Market.Stats(id)
                        if st.med7 or st.med30 or st.live then
                            tt:AddLine(" ")
                            tt:AddLine("Market", 0.98, 0.55, 0.12)
                            if st.live then
                                tt:AddDoubleLine("Live median", ns.MoneyShort(st.live.med) .. "  (" .. ns.Commas(st.live.qty) .. " listed, low " ..
                                    ns.MoneyShort(st.live.low) .. ")", 0.8, 0.8, 0.8, 1, 1, 1)
                            end
                            tt:AddDoubleLine("7D / 30D median", (st.med7 and ns.MoneyShort(st.med7) or "--") .. "  /  " ..
                                (st.med30 and ns.MoneyShort(st.med30) or "--"), 0.8, 0.8, 0.8, 1, 1, 1)
                        end
                    end
                    tt:AddLine(" ")
                    tt:AddLine("Cost basis", 0.98, 0.55, 0.12)
                    if b then
                        tt:AddDoubleLine("Avg cost", ns.Money(b.avg), 0.8, 0.8, 0.8, 1, 1, 1)
                        tt:AddDoubleLine("Units covered", min(b.qty, P:Held(id)) .. " of " .. P:Held(id), 0.8, 0.8, 0.8, 1, 1, 1)
                        tt:AddDoubleLine("Source", (b.src == "manual" and "set by you" or "recorded purchases") ..
                            (b.t and (" · " .. date("%Y-%m-%d", b.t)) or ""), 0.8, 0.8, 0.8, 1, 1, 1)
                        if b.realized and b.realized ~= 0 then
                            tt:AddDoubleLine("Realized to date", ns.Money(b.realized, true), 0.8, 0.8, 0.8, 1, 1, 1)
                        end
                    else
                        tt:AddLine("Uncosted (looted, crafted, or bought before install)", 0.6, 0.6, 0.65)
                    end
                    tt:AddLine(" ")
                    if view.hidden then
                        tt:AddLine("|cffffc238Ctrl-click|r to restore to portfolio", 0.8, 0.8, 0.8)
                    else
                        tt:AddLine("|cffffc238Click|r to set your buy price", 0.8, 0.8, 0.8)
                        tt:AddLine("|cffffc238Ctrl-click|r to hide (gear you use, junk…)", 0.8, 0.8, 0.8)
                        if ns.Market then tt:AddLine("|cffffc238Alt-click|r price history chart", 0.8, 0.8, 0.8) end
                    end
                end,
                onClick = function(button)
                    if button == "LeftButton" and IsControlKeyDown() then
                        P:SetHidden(id, not view.hidden)
                        return
                    end
                    if button == "LeftButton" and IsAltKeyDown() and ns.Market then
                        ns.Market:Select(id); ns:ShowPage("mkt")
                        return
                    end
                    if view.hidden then return end
                    if button == "LeftButton" and not IsModifiedClick("CHATLINK") then p.editor:Open(id) end
                end,
            }
        end
    end

    sortRows(rows)
    return rows, { mv = tMV, cost = tCost, costedMV = tCostedMV, upl = tUPL }
end

local function pctTxt(upl, cost)
    if not cost or cost <= 0 then return "" end
    return upl >= 0 and ns.Color("green", ns.Pct(100 * upl / cost, true)) or ns.Color("red", ns.Pct(100 * upl / cost))
end

local function refresh(p)
    local me = ns.CharKey()
    local loc = view.loc ~= "ALL" and view.loc or nil
    ns.db.portFold = ns.db.portFold or {}
    local fold = ns.db.portFold
    local rows, T

    if view.scope == "SPLIT" then
        rows, T = {}, { mv = 0, cost = 0, costedMV = 0, upl = 0 }
        local groups = {}
        for key in pairs(ns.db.chars) do
            local r, t = buildRows(p, key, loc, "    ")
            if #r > 0 then groups[#groups + 1] = { key = key, rows = r, t = t } end
            for k, v in pairs(t) do T[k] = T[k] + v end
        end
        table.sort(groups, function(x, y) return x.t.mv > y.t.mv end)
        for _, g in ipairs(groups) do
            local key, t = g.key, g.t
            local open = fold[key]
            if open == nil then open = (key == me) end
            local ch = ns.db.chars[key]
            rows[#rows + 1] = {
                header = true,
                cells = {
                    ns.Color("amber", open and "[-] " or "[+] ") .. (key == me and ns.Color("orange", "» ") or "")
                        .. ns.CharLabel(key) .. ns.Color("dim", "  " .. (ch.realm or "")),
                    ns.Color("grey", #g.rows .. " pos"),
                    "", "", "",
                    ns.Color("amber", ns.MoneyShort(t.mv)),
                    t.cost > 0 and ns.MoneyShort(t.cost) or ns.Color("dim", "—"),
                    t.cost > 0 and ns.PnL(t.upl) or ns.Color("dim", "uncosted"),
                    pctTxt(t.upl, t.cost),
                },
                tooltip = function(tt)
                    tt:AddLine(ns.CharLabel(key) .. ns.Color("grey", " - " .. (ch.realm or "")))
                    tt:AddDoubleLine("Positions", #g.rows, 0.8, 0.8, 0.8, 1, 1, 1)
                    tt:AddDoubleLine("Market value", ns.Money(t.mv), 0.8, 0.8, 0.8, 1, 1, 1)
                    tt:AddDoubleLine("Cost basis", ns.Money(t.cost), 0.8, 0.8, 0.8, 1, 1, 1)
                    tt:AddDoubleLine("Unrealized", ns.Money(t.upl, true), 0.8, 0.8, 0.8, 1, 1, 1)
                    if not ch.bankT then tt:AddLine("Bank not scanned yet: log in and visit the bank", 1, 0.76, 0.22) end
                    tt:AddLine(" ")
                    tt:AddLine("|cffffc238Click|r fold / unfold   ·   |cffffc238Shift-click|r all", 0.8, 0.8, 0.8)
                end,
                onClick = function(button)
                    if button ~= "LeftButton" then return end
                    if IsShiftKeyDown() then
                        local target = not open
                        for _, gg in ipairs(groups) do fold[gg.key] = target end
                    else
                        fold[key] = not open
                    end
                    ns:RefreshPage("port")
                end,
            }
            if open then
                for _, r in ipairs(g.rows) do rows[#rows + 1] = r end
            end
        end
    else
        rows, T = buildRows(p, view.scope == "ME" and me or nil, loc)
    end
    local tMV, tCost, tCostedMV, tUPL = T.mv, T.cost, T.costedMV, T.upl
    p.list:SetData(rows, true)
    local nh = 0
    for _ in pairs(ns.db.hidden) do nh = nh + 1 end
    local npos = 0
    for _, r in ipairs(rows) do if not r.header then npos = npos + 1 end end
    if view.scope == "SPLIT" then npos = npos .. " SHOWN" end
    p.sec.right:SetText(npos .. (view.hidden and " HIDDEN" or " POSITIONS") .. (not view.hidden and nh > 0 and ns.Color("dim", "  ·  " .. nh .. " hidden") or ""))
    p.sec.title:SetText(view.hidden and "HIDDEN ITEMS · CTRL-CLICK TO RESTORE" or "POSITIONS · CLICK TO SET BUY PRICE · CTRL-CLICK TO HIDE")
    p.list:SetEmptyText(view.hidden and "Nothing hidden. Ctrl-click a position to hide it."
        or "No positions yet. Open your bags, and visit your bank once per character.")

    p.kpi[1].value:SetText(ns.Color("amber", ns.MoneyShort(tMV)))
    p.kpi[1].sub:SetText(view.scope == "ME" and "this character" or "all accounts")
    p.kpi[2].value:SetText(ns.MoneyShort(tCost))
    p.kpi[2].sub:SetText("on costed units")
    p.kpi[3].value:SetText(ns.PnL(tUPL))
    p.kpi[3].sub:SetText(tCost > 0 and (ns.Pct(100 * tUPL / tCost, true) .. " vs cost") or "set some buy prices")
    p.kpi[4].value:SetText(ns.PnL(ns.db.realized or 0))
    p.kpi[4].sub:SetText("AH + vendor sales vs avg cost")
    p.kpi[5].value:SetText(tMV > 0 and ns.Pct(100 * tCostedMV / tMV) or "--")
    p.kpi[5].sub:SetText("of market value has a basis")

    local ch = ns.db.chars[me]
    if ch and not ch.bankT then
        ns:SetStatus(ns.Color("amber", "Visit your bank once on this character so the portfolio is complete."))
    end
end

ns:RegisterPage({ id = "port", order = 3, code = "PORT", title = "Portfolio", build = build, refresh = refresh })

ns:AddTicker(function()
    if not ns.db or not ns.db.basis then return end
    local upl = 0
    for id, b in pairs(ns.db.basis) do
        if b.qty > 0 and not P:IsHidden(id) then
            local held = P:Held(id)
            local link = P.Link(id)
            local unit = link and ns.Valuate(link) or 0
            local cq = min(b.qty, held)
            upl = upl + cq * ((unit or 0) - b.avg)
        end
    end
    return "PORT UNREAL " .. ns.PnL(upl) .. "   REAL " .. ns.PnL(ns.db.realized or 0)
end)
