-- Fish & Partners: Intraday P&L (session gold tracker)
-- Realized  = raw coin looted (booked by the ledger as LOOT entries)
-- Unrealized = looted items marked to market (AH via Auctionator vs vendor, see Valuation.lua)

local _, ns = ...
local UI, C = ns.UI, ns.C
local S = {}
ns.Session = S

local function sess() return ns.cdb and ns.cdb.session end

---------------------------------------------------------------------------
-- Loot message parsing (localized via Blizzard global strings)
---------------------------------------------------------------------------
local function toPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    fmt = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    fmt = fmt:gsub("%%%%%d%%%$s", "(.+)"):gsub("%%%%%d%%%$d", "(%%d+)")
    fmt = fmt:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. fmt .. "$"
end
local PAT_MULTI  = toPattern(LOOT_ITEM_SELF_MULTIPLE) or "^You receive loot: (.+)x(%d+)%.$"
local PAT_SINGLE = toPattern(LOOT_ITEM_SELF) or "^You receive loot: (.+)%.$"
local PAT_PUSH_MULTI = toPattern(LOOT_ITEM_PUSHED_SELF_MULTIPLE) or "^You receive item: (.+)x(%d+)%.$"
local PAT_PUSH       = toPattern(LOOT_ITEM_PUSHED_SELF) or "^You receive item: (.+)%.$"

---------------------------------------------------------------------------
-- Session lifecycle
---------------------------------------------------------------------------
function S:IsRunning()
    local s = sess()
    return s and s.active and not s.paused
end

function S:Elapsed()
    local s = sess()
    if not s then return 0 end
    local e = s.elapsed or 0
    if s.active and not s.paused then e = e + (time() - s.resumed) end
    return e
end

function S:Start()
    local s = sess()
    if s and s.active then
        if s.paused then self:TogglePause() end
        return
    end
    ns.cdb.session = {
        active = true, paused = false, started = time(), resumed = time(), elapsed = 0,
        coin = 0, quest = 0, items = {}, tape = {}, curve = {}, lastCurve = 0, lootCount = 0,
    }
    ns.Print("Session opened. The market is |cff4af6c3OPEN|r. Happy hunting.")
    ns:Fire("SESSION_UPDATE")
end

function S:TogglePause()
    local s = sess()
    if not (s and s.active) then return end
    if s.paused then
        s.paused, s.resumed = false, time()
        ns.Print("Trading |cff4af6c3RESUMED|r.")
    else
        s.elapsed = self:Elapsed()
        s.paused = true
        ns.Print("Trading |cffffc238HALTED|r (session paused).")
    end
    ns:Fire("SESSION_UPDATE")
end

function S:ToggleStartPause()
    local s = sess()
    if s and s.active then self:TogglePause() else self:Start() end
end

function S:Stats()
    local s = sess()
    local st = { active = s and s.active or false, paused = s and s.paused or false }
    if not s then return st end
    local itemsValue, n = 0, 0
    for _, it in pairs(s.items) do
        itemsValue = itemsValue + (it.unit or 0) * it.qty
        n = n + 1
    end
    st.elapsed = self:Elapsed()
    st.coin = s.coin or 0
    st.quest = (ns.S.sessionQuest ~= false) and (s.quest or 0) or 0
    st.items = itemsValue
    st.distinct = n
    st.lootCount = s.lootCount or 0
    st.total = st.coin + st.quest + itemsValue
    st.gph = st.elapsed >= 60 and (st.total / (st.elapsed / 3600)) or nil
    return st
end

function S:Stop()
    local s = sess()
    if not (s and s.active) then ns.Print("No open session.") return end
    local st = self:Stats()
    local best, bestV
    for link, it in pairs(s.items) do
        local v = (it.unit or 0) * it.qty
        if not bestV or v > bestV then best, bestV = link, v end
    end
    local partySummary
    if ns.Party then partySummary = ns.Party:Summary(s) end
    table.insert(ns.cdb.archive, 1, {
        start = s.started, dur = st.elapsed, coin = st.coin, quest = st.quest, items = st.items,
        total = st.total, gph = st.gph, loot = st.lootCount, best = best, party = partySummary,
    })
    while #ns.cdb.archive > 30 do table.remove(ns.cdb.archive) end
    ns.cdb.session = nil
    ns.Print(format("Session booked: %s in %s (%s/hr).", ns.Money(st.total), ns.Duration(st.elapsed),
        st.gph and ns.MoneyShort(st.gph) or "--"))
    ns:Fire("SESSION_UPDATE")
end

function S:Discard()
    ns.cdb.session = nil
    ns:Fire("SESSION_UPDATE")
end

function S:Remark()
    local s = sess()
    if not s then return end
    for link, it in pairs(s.items) do
        local unit, src, ah, vendor = ns.Valuate(link)
        if unit then it.unit, it.src, it.ah, it.vendor = unit, src, ah, vendor end
    end
    ns:Fire("SESSION_UPDATE")
end

---------------------------------------------------------------------------
-- Feeds
---------------------------------------------------------------------------
local function pushTape(s, entry)
    table.insert(s.tape, 1, entry)
    while #s.tape > 60 do table.remove(s.tape) end
end

local function addItem(link, qty, reward)
    local s = sess()
    ns.WhenItemReady(link, function()
        if sess() ~= s or not (s and s.active) then return end
        local unit, src, ah, vendor = ns.Valuate(link)
        unit = unit or 0
        local it = s.items[link]
        if not it then it = { qty = 0 }; s.items[link] = it end
        it.qty = it.qty + qty
        it.unit, it.src, it.ah, it.vendor = unit, src or "---", ah, vendor
        if reward then it.reward = true end
        s.lootCount = (s.lootCount or 0) + qty
        pushTape(s, { t = time(), link = link, qty = qty, v = unit * qty, src = src, reward = reward or nil })
        ns:Fire("SESSION_UPDATE")
    end)
end

ns:On("CHAT_MSG_LOOT", function(msg)
    if not S:IsRunning() or type(msg) ~= "string" then return end
    local link, qty = msg:match(PAT_MULTI)
    if not link then link = msg:match(PAT_SINGLE); qty = 1 end
    if link and link:find("|H") then
        addItem(link, tonumber(qty) or 1)
        return
    end
    -- Quest reward items arrive as "You receive item: [X]" (a "pushed" item).
    -- Only count those right around a quest turn-in, never vendor buys or crafts.
    local plink, pqty = msg:match(PAT_PUSH_MULTI)
    if not plink then plink = msg:match(PAT_PUSH); pqty = 1 end
    if plink and plink:find("|H") and S:InQuestWindow() and not S:RecentQuestLoot(plink) then
        S.pushedReward = S.pushedReward or {}
        S.pushedReward[plink] = GetTime()
        addItem(plink, tonumber(pqty) or 1, true)
    end
end)

-- Quest reward bookkeeping
local questTurnIn = 0
local questLoot = {}   -- link -> GetTime() when QUEST_LOOT_RECEIVED booked it

function S:InQuestWindow()
    return (GetTime() - questTurnIn) < 4 or (ns.Ledger and ns.Ledger.InCtx("quest", 3))
end

function S:RecentQuestLoot(link)
    local t = questLoot[link]
    return t and (GetTime() - t) < 5
end

ns:On("QUEST_TURNED_IN", function() questTurnIn = GetTime() end)

-- Modern clients announce reward items directly; book them here and let the
-- chat line above skip the same item.
ns:On("QUEST_LOOT_RECEIVED", function(questID, itemLink, quantity)
    if not S:IsRunning() or type(itemLink) ~= "string" or not itemLink:find("|H") then return end
    questLoot[itemLink] = GetTime()
    local pushed = S.pushedReward and S.pushedReward[itemLink]
    if pushed and GetTime() - pushed < 5 then return end -- chat line already booked it
    addItem(itemLink, tonumber(quantity) or 1, true)
end)

ns:Listen("LEDGER_ENTRY", function(e)
    if not S:IsRunning() or e.c ~= ns.CharKey() then return end
    local s = sess()
    if e.k == "LOOT" then
        s.coin = s.coin + e.a
        pushTape(s, { t = e.t, coin = true, v = e.a })
        ns:Fire("SESSION_UPDATE")
    elseif e.k == "QUEST" then
        s.quest = (s.quest or 0) + e.a
        if ns.S.sessionQuest ~= false then
            pushTape(s, { t = e.t, quest = true, v = e.a })
            ns:Fire("SESSION_UPDATE")
        end
    end
end)

ns:Listen("VALUATION_CHANGED", function() S:Remark() end)

-- Auto-pause on logout; auto-resume after a /reload (short gap)
ns:On("PLAYER_LOGOUT", function()
    local s = sess()
    if s and s.active and not s.paused then
        s.elapsed = S:Elapsed()
        s.paused = true
        s.autoPaused = time()
    end
end)

ns:OnInit(function()
    if not ns.db.migQuestGold then ns.S.sessionQuest = true; ns.db.migQuestGold = true end
    local s = sess()
    if s and s.autoPaused then
        if time() - s.autoPaused < 300 then
            s.paused, s.resumed = false, time()
        else
            ns.Print("Your session was paused while you were offline. Resume it from |cfffb8b1ePNL <GO>|r.")
        end
        s.autoPaused = nil
    end
    -- 1s heartbeat: P&L curve sampling + live page refresh
    C_Timer.NewTicker(1, function()
        local cur = sess()
        if cur and cur.active and not cur.paused then
            local e = S:Elapsed()
            if e - (cur.lastCurve or 0) >= 60 then
                cur.lastCurve = e
                table.insert(cur.curve, { e = e, v = S:Stats().total })
                if #cur.curve > 120 then
                    local thin = {}
                    for i = 1, #cur.curve, 2 do thin[#thin + 1] = cur.curve[i] end
                    cur.curve = thin
                end
            end
        end
        ns:RefreshPage("pnl")
    end)
end)

ns:Listen("SESSION_UPDATE", function() ns:RefreshPage("pnl") end)

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local SRC_COLOR = { AH = "cyan", VND = "grey", ["---"] = "dim" }

local function build(p)
    local W = ns.PAGE_W

    -- Control bar
    p.state = UI.Text(p, 14, C.white, "LEFT", UI.FONT, "")
    p.state:SetPoint("TOPLEFT", 0, -3)
    p.btnStart = UI.Button(p, "START SESSION", 128, 22, "go")
    p.btnStart:SetScript("OnClick", function() S:ToggleStartPause() end)
    p.btnStop = UI.Button(p, "STOP & BOOK", 104, 22, "primary")
    p.btnStop.tip = "Close the session and book it to your archive."
    p.btnStop:SetScript("OnClick", function() S:Stop() end)
    p.btnDiscard = UI.Button(p, "DISCARD", 76, 22, "danger")
    p.btnDiscard:SetScript("OnClick", function()
        UI.Confirm("Discard the current session without booking it?", function() S:Discard() end)
    end)
    p.btnMtm = UI.Button(p, "MARK TO MARKET", 118, 22, "default")
    p.btnMtm.tip = "Re-price every holding with the latest Auctionator scan."
    p.btnMtm:SetScript("OnClick", function() S:Remark() end)
    p.btnMtm:SetPoint("TOPRIGHT", 0, 0)
    p.btnDiscard:SetPoint("RIGHT", p.btnMtm, "LEFT", -6, 0)
    p.btnStop:SetPoint("RIGHT", p.btnDiscard, "LEFT", -6, 0)
    p.btnStart:SetPoint("RIGHT", p.btnStop, "LEFT", -6, 0)

    -- KPIs
    local kw = (W - 4 * 6) / 5
    local labels = { "Session clock", "Realized · coin + quests", "Unrealized · items MTM", "Total session P&L", "Gold per hour" }
    p.kpi = {}
    for i, l in ipairs(labels) do
        local k = UI.KPI(p, l, kw, 60, i == 5 and 20 or 17)
        k:SetPoint("TOPLEFT", (i - 1) * (kw + 6), -30)
        p.kpi[i] = k
    end
    p.kpi[5].accent:SetColorTexture(C.green[1], C.green[2], C.green[3], 1)

    local leftW, rightW = 524, W - 524 - 8
    -- two views below the KPIs: your own book, and the party
    local mv = CreateFrame("Frame", nil, p); mv:SetAllPoints(p); p.myView = mv
    local pv = CreateFrame("Frame", nil, p); pv:SetAllPoints(p); p.partyView = pv; pv:Hide()
    p.view = "me"
    p.viewSeg = UI.Segment(p, { { "me", "MY BOOK" }, { "party", "PARTY" } }, function(v)
        p.view = v
        ns:RefreshPage("pnl")
    end, 64, 20)
    p.viewSeg:SetPoint("TOPLEFT", 272, 0)
    p.viewSeg:Select("me")
    p.viewSeg.buttons[2].tip = "What everyone in your group is looting, valued with your pricing rules."
    p.state:SetWidth(266)
    if ns.Party then ns.Party:BuildView(pv) end
    -- Holdings
    local s1 = UI.Section(mv, "Holdings · looted inventory", true)
    s1:SetPoint("TOPLEFT", 0, -98); s1:SetWidth(leftW)
    p.secHold = s1
    p.hold = UI.Table(mv, {
        { title = "Instrument", width = 206 },
        { title = "Qty", width = 40, justify = "RIGHT" },
        { title = "Unit", width = 76, justify = "RIGHT" },
        { title = "Src", width = 42, justify = "CENTER" },
        { title = "Mkt value", width = 92, justify = "RIGHT" },
        { title = "Wt", width = 50, justify = "RIGHT" },
    }, leftW, 206, 16)
    p.hold:SetPoint("TOPLEFT", 0, -116)
    p.hold:SetEmptyText("No positions. Go loot something.")

    -- Chart
    local s2 = UI.Section(mv, "Cumulative P&L")
    s2:SetPoint("TOPLEFT", leftW + 8, -98); s2:SetWidth(rightW)
    p.chart = UI.BarChart(mv, rightW, 206)
    p.chart:SetPoint("TOPLEFT", leftW + 8, -116)
    p.chart.empty:SetText("Curve samples once per minute.")

    -- Tape
    local s3 = UI.Section(mv, "Time & sales · loot tape")
    s3:SetPoint("TOPLEFT", 0, -328); s3:SetWidth(leftW)
    p.tape = UI.Table(mv, {
        { title = "Time", width = 62 },
        { title = "Fill", width = 300 },
        { title = "Value", width = 96, justify = "RIGHT" },
        { title = "Src", width = 50, justify = "CENTER" },
    }, leftW, ns.PAGE_H - 346, 15)
    p.tape:SetPoint("TOPLEFT", 0, -346)
    p.tape:SetEmptyText("Waiting for fills…")

    -- Archive
    local s4 = UI.Section(mv, "Booked sessions")
    s4:SetPoint("TOPLEFT", leftW + 8, -328); s4:SetWidth(rightW)
    p.arch = UI.Table(mv, {
        { title = "Date", width = 74 },
        { title = "Dur", width = 62 },
        { title = "P&L", width = 92, justify = "RIGHT" },
        { title = "G/hr", width = 92, justify = "RIGHT" },
    }, rightW, ns.PAGE_H - 346, 15)
    p.arch:SetPoint("TOPLEFT", leftW + 8, -346)
    p.arch:SetEmptyText("No booked sessions yet.")
    p.archCount = -1
end

local function refresh(p)
    local s = sess()
    local st = S:Stats()

    -- state + buttons
    if not st.active then
        p.state:SetText(ns.Color("grey", "MARKET CLOSED") .. ns.Color("dim", "  ·  press START SESSION to open the book"))
        p.btnStart:SetText("START SESSION"); p.btnStart:SetStyle("go")
    elseif st.paused then
        p.state:SetText(ns.Color("amber", "TRADING HALTED") .. ns.Color("dim", "  ·  session paused"))
        p.btnStart:SetText("RESUME"); p.btnStart:SetStyle("go")
    else
        p.state:SetText(ns.Color("green", "MARKET OPEN") .. ns.Color("dim", "  ·  opened " .. date("%H:%M", s.started)))
        p.btnStart:SetText("PAUSE"); p.btnStart:SetStyle("default")
    end
    p.btnStop:SetEnabled(st.active); p.btnStop:SetAlpha(st.active and 1 or 0.4)
    p.btnDiscard:SetEnabled(st.active); p.btnDiscard:SetAlpha(st.active and 1 or 0.4)

    -- KPIs
    p.kpi[1].value:SetText(ns.Color(st.active and (st.paused and "amber" or "white") or "dim", ns.Duration(st.elapsed or 0)))
    p.kpi[1].sub:SetText(st.active and ((st.lootCount or 0) .. " items looted") or "no session")
    p.kpi[2].value:SetText(ns.PnL(st.coin or 0))
    p.kpi[2].sub:SetText("coin " .. ns.MoneyShort(st.coin or 0) .. " · quests " .. ns.MoneyShort(st.quest or 0))
    p.kpi[3].value:SetText(ns.PnL(st.items or 0))
    p.kpi[3].sub:SetText((st.distinct or 0) .. " instruments")
    p.kpi[4].value:SetText(ns.PnL(st.total or 0))
    p.kpi[4].sub:SetText(st.total and st.total > 0 and ("realized " .. format("%.0f%%", 100 * ((st.coin or 0) + (st.quest or 0)) / st.total)) or "")
    p.kpi[5].value:SetText(st.gph and ns.Color("green", ns.MoneyShort(st.gph) .. "/h") or ns.Color("dim", "--"))
    p.kpi[5].sub:SetText(st.gph and (ns.MoneyShort(st.gph / 60) .. " per minute") or "needs 1 min of data")

    if not p:IsVisible() then return end

    if p.view == "party" then
        p.myView:Hide(); p.partyView:Show()
        if ns.Party then ns.Party:RefreshView(p.partyView) end
        return
    end
    p.partyView:Hide(); p.myView:Show()

    -- Holdings
    local rows = {}
    if s then
        for link, it in pairs(s.items) do
            local v = (it.unit or 0) * it.qty
            rows[#rows + 1] = {
                v = v, link = link,
                cells = {
                    link, tostring(it.qty), ns.MoneyShort(it.unit or 0),
                    ns.Color(SRC_COLOR[it.src] or "grey", it.src or "---"),
                    ns.Color("white", ns.MoneyShort(v)),
                    (st.items and st.items > 0) and ns.Color("grey", format("%.0f%%", 100 * v / st.items)) or "",
                },
                tooltip = function(tt)
                    pcall(tt.SetHyperlink, tt, link)
                    tt:AddLine(" ")
                    tt:AddLine("Fish & Partners valuation", 0.98, 0.55, 0.12)
                    tt:AddDoubleLine("Vendor", it.vendor and ns.Money(it.vendor) or "--", 0.8, 0.8, 0.8, 1, 1, 1)
                    tt:AddDoubleLine("AH (Auctionator)", it.ah and ns.Money(it.ah) or "no scan", 0.8, 0.8, 0.8, 1, 1, 1)
                    tt:AddDoubleLine("Marked at", (it.src or "---") .. "  " .. ns.Money(it.unit or 0), 0.8, 0.8, 0.8, 1, 1, 1)
                    tt:AddDoubleLine("Position", it.qty .. " × = " .. ns.MoneyShort(v), 0.8, 0.8, 0.8, 1, 1, 1)
                end,
            }
        end
    end
    table.sort(rows, function(a, b) return a.v > b.v end)
    p.hold:SetData(rows, true)
    p.secHold.right:SetText((#rows) .. " POSITIONS")

    -- Tape
    local tape = {}
    if s then
        for _, t in ipairs(s.tape) do
            local fill
            if t.coin then fill = ns.Color("amber", "COIN") .. "  " .. ns.Money(t.v)
            elseif t.quest then fill = ns.Color("cyan", "QUEST") .. "  " .. ns.Money(t.v)
            else fill = (t.reward and (ns.Color("cyan", "REWARD") .. "  ") or "") .. t.link .. (t.qty > 1 and ns.Color("grey", " x" .. t.qty) or "") end
            tape[#tape + 1] = {
                link = t.link,
                cells = {
                    ns.Color("grey", date("%H:%M:%S", t.t)), fill, ns.PnL(t.v),
                    t.coin and ns.Color("amber", "CASH") or ns.Color(SRC_COLOR[t.src] or "grey", t.src or "---"),
                },
            }
        end
    end
    p.tape:SetData(tape, true)

    -- Chart
    local pts = {}
    if s then
        for _, c in ipairs(s.curve) do pts[#pts + 1] = { v = c.v, label = ns.Duration(c.e) } end
        if st.active and #pts > 0 then pts[#pts + 1] = { v = st.total, label = "now" } end
    end
    p.chart:SetData(pts, #pts > 0 and "00:00:00" or "", #pts > 0 and ns.Duration(st.elapsed) or "", "orange")

    -- Archive (rebuild only when changed)
    local arch = ns.cdb.archive
    if p.archCount ~= #arch or (arch[1] and p.archTop ~= arch[1].start) then
        p.archCount, p.archTop = #arch, arch[1] and arch[1].start
        local ar = {}
        for _, a in ipairs(arch) do
            ar[#ar + 1] = {
                cells = {
                    ns.Color("grey", date("%m-%d %H:%M", a.start)), ns.Duration(a.dur), ns.PnL(a.total),
                    a.gph and ns.Color("amber", ns.MoneyShort(a.gph)) or "--",
                },
                tooltip = function(tt)
                    tt:AddLine("Booked session", 0.98, 0.55, 0.12)
                    tt:AddDoubleLine("Opened", date("%Y-%m-%d %H:%M", a.start), 0.8, 0.8, 0.8, 1, 1, 1)
                    tt:AddDoubleLine("Duration", ns.Duration(a.dur), 0.8, 0.8, 0.8, 1, 1, 1)
                    tt:AddDoubleLine("Coin looted", ns.Money(a.coin), 0.8, 0.8, 0.8, 1, 1, 1)
                    tt:AddDoubleLine("Items (MTM)", ns.Money(a.items), 0.8, 0.8, 0.8, 1, 1, 1)
                    tt:AddDoubleLine("Total", ns.Money(a.total), 0.8, 0.8, 0.8, 1, 1, 1)
                    tt:AddDoubleLine("Gold / hour", a.gph and ns.Money(a.gph) or "--", 0.8, 0.8, 0.8, 1, 1, 1)
                    if a.quest and a.quest > 0 then tt:AddDoubleLine("Quest gold", ns.Money(a.quest), 0.8, 0.8, 0.8, 1, 1, 1) end
                    if a.best then tt:AddDoubleLine("Top position", a.best, 0.8, 0.8, 0.8) end
                    if a.party and #a.party > 0 then
                        tt:AddLine(" ")
                        tt:AddLine("Party", 0.98, 0.55, 0.12)
                        for _, m in ipairs(a.party) do tt:AddDoubleLine(m.name, ns.MoneyShort(m.total), 1, 1, 1, 1, 1, 1) end
                    end
                end,
            }
        end
        p.arch:SetData(ar)
    end
end

ns:RegisterPage({ id = "pnl", order = 1, code = "PNL", title = "Intraday P&L", build = build, refresh = refresh })

ns:AddTicker(function()
    local st = S:Stats()
    if not st.active then return ns.Color("grey", "PNL SESSION CLOSED") end
    return "PNL " .. ns.PnL(st.total) .. "   G/HR " .. (st.gph and ns.Color("amber", ns.MoneyShort(st.gph)) or "--")
end)
