-- Fish & Partners: Party desk
-- Tracks what everyone in your group loots during your session, valued with the
-- same pricing rules as your own book (Auctionator vs vendor, BoP -> vendor).
--
-- What the game shows you about other players:
--   * every item they loot ("X receives loot: [item]") -> tracked exactly
--   * their coin: not shown, BUT group coin is split evenly, so each member's coin
--     share equals yours for the time they were in the group (shown as an estimate)
--   * party members who also run Fish & Partners broadcast their own session totals
--     (incl. quest gold), shown as "reported" figures

local _, ns = ...
local UI, C = ns.UI, ns.C
local PT = {}
ns.Party = PT
local floor, min, max = math.floor, math.min, math.max

local PREFIX = "FPWM1"
local function sess() return ns.cdb and ns.cdb.session end
local function running() return ns.Session and ns.Session:IsRunning() end

---------------------------------------------------------------------------
-- Roster
---------------------------------------------------------------------------
local function unitKey(unit)
    local name, realm = UnitName(unit)
    if not name then return nil end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

function PT.Roster()
    local out = {}
    if not IsInGroup or not IsInGroup() then return out end
    local raid = IsInRaid and IsInRaid()
    local n = raid and (GetNumGroupMembers() or 0) or (GetNumSubgroupMembers and GetNumSubgroupMembers() or 4)
    for i = 1, n do
        local unit = raid and ("raid" .. i) or ("party" .. i)
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local key = unitKey(unit)
            if key then out[key] = { unit = unit, class = select(2, UnitClass(unit)), guid = UnitGUID and UnitGUID(unit) } end
        end
    end
    return out
end

local function member(s, name)
    s.party = s.party or {}
    s.partyCoin = s.partyCoin or 0
    local m = s.party[name]
    if not m then
        m = {
            name = name, items = {}, tape = {}, value = 0, fills = 0,
            coinBase = s.partyCoin, coinIn = 0, joinElapsed = ns.Session:Elapsed(), present = true,
        }
        s.party[name] = m
    end
    return m
end

-- Keep membership current: who's in, who left (their coin share stops growing)
local function syncRoster()
    local s = sess()
    if not (s and s.active) then return end
    local roster = PT.Roster()
    s.party = s.party or {}
    for name, info in pairs(roster) do
        local m = member(s, name)
        m.class = info.class or m.class
        if not m.present then
            m.present = true
            m.coinBase = (s.partyCoin or 0) - (m.coinIn or 0) -- resume accrual
        end
    end
    for name, m in pairs(s.party) do
        if m.present and not roster[name] then
            m.present = false
            m.coinIn = (s.partyCoin or 0) - (m.coinBase or 0) -- freeze accrued share
        end
    end
end
ns:On("GROUP_ROSTER_UPDATE", function() if ns.db then syncRoster(); ns:RefreshPage("pnl") end end)
ns:Listen("SESSION_UPDATE", function() syncRoster() end)

local function coinOf(s, m)
    if m.present then return (s.partyCoin or 0) - (m.coinBase or 0) end
    return m.coinIn or 0
end

---------------------------------------------------------------------------
-- Loot feed (other players)
---------------------------------------------------------------------------
local function toPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    fmt = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    fmt = fmt:gsub("%%%%%d%%%$s", "(.+)"):gsub("%%%%%d%%%$d", "(%%d+)")
    fmt = fmt:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. fmt .. "$"
end
-- Other players' loot lines. We accept only "X receives loot" style messages (not
-- rolls, crafts or pushed quest items), then:
--   * looter: event GUID -> roster, else event name arg, else the name in the text
--     (player hyperlinks and realm suffixes stripped)
--   * item:   the item hyperlink anywhere in the line; quantity = "xN" right after it
local OTHER_PATTERNS = {}
for _, g in ipairs({ "LOOT_ITEM_MULTIPLE", "LOOT_ITEM", "LOOT_ITEM_BONUS_ROLL_MULTIPLE", "LOOT_ITEM_BONUS_ROLL" }) do
    local pat = toPattern(_G[g])
    if pat then OTHER_PATTERNS[#OTHER_PATTERNS + 1] = pat end
end
if #OTHER_PATTERNS == 0 then
    OTHER_PATTERNS = { "^(.+) receives loot: (.+)x(%d+)%.$", "^(.+) receives loot: (.+)%.$" }
end

local function plainName(s)
    if not s then return nil end
    s = s:gsub("|Hplayer:[^|]*|h%[?([^%]|]*)%]?|h", "%1")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function findItem(msg)
    local link = msg:match("(|c%x+|Hitem:.-|h.-|h|r)") or msg:match("(|Hitem:.-|h.-|h)")
    if not link then return nil end
    local i = msg:find(link, 1, true)
    local rest = msg:sub(i + #link)
    local q = rest:match("^%s*[xX](%d+)") or rest:match("^%s*\195\151(%d+)") -- "x5" or "×5"
    return link, tonumber(q) or 1
end

local function isOthersLoot(msg)
    for _, pat in ipairs(OTHER_PATTERNS) do
        local a, b = msg:match(pat)
        if a then
            -- the capture without an item link is the looter's name
            if a:find("|Hitem:") then return b end
            return a
        end
    end
end

local function resolveLooter(roster, guid, nameArg, textName)
    if guid and guid ~= "" then
        for key, info in pairs(roster) do if info.guid == guid then return key end end
    end
    for i = 1, 2 do
        local cand = plainName(i == 1 and nameArg or textName)
        if cand and cand ~= "" then
            if roster[cand] then return cand end
            -- "Baraca One" / "Baraca-One" / "Baraca": same person
            local nk, base = ns.NameKey(cand), ns.BaseName(cand)
            for key in pairs(roster) do
                if ns.NameKey(key) == nk then return key end
            end
            for key in pairs(roster) do
                if ns.BaseName(key) == base then return key end
            end
        end
    end
end

PT.debug = false
local function dbg(msg, why)
    if PT.debug then ns.Print(ns.Color("dim", "[party] ") .. why .. ns.Color("dim", " :: ") .. (msg:gsub("|", "||"))) end
end

ns:On("CHAT_MSG_LOOT", function(msg, nameArg, _, _, nameArg2, _, _, _, _, _, _, guid)
    if type(msg) ~= "string" then return end
    if not msg:find("|Hitem:") then return end
    local textName = isOthersLoot(msg)
    if not textName then dbg(msg, "not a party loot line") return end
    if not running() then dbg(msg, "no running session") return end
    if guid and UnitGUID and guid == UnitGUID("player") then return end
    local roster = PT.Roster()
    local name = resolveLooter(roster, guid, nameArg ~= "" and nameArg or nameArg2, textName)
    if not name then dbg(msg, "looter not in your group") return end
    local link, qty = findItem(msg)
    if not link then dbg(msg, "no item link") return end
    if ns.IsQuestItem(link) then dbg(msg, "quest item (no value), skipped") return end
    dbg(msg, ns.Color("green", "booked ") .. name .. " x" .. qty)

    local s = sess()
    ns.WhenItemReady(link, function()
        if sess() ~= s or not s.active then return end
        local m = member(s, name)
        m.class = roster[name] and roster[name].class or m.class
        local unit, src = ns.SessionValuate(link)
        unit = unit or 0
        local it = m.items[link]
        if not it then it = { qty = 0 }; m.items[link] = it end
        it.qty, it.unit, it.src = it.qty + qty, unit, src or "---"
        m.fills = m.fills + qty
        local v = unit * qty
        if not m.best or v > (m.bestV or 0) then m.best, m.bestV = link, v end
        table.insert(m.tape, 1, { t = time(), link = link, qty = qty, v = v })
        while #m.tape > 30 do table.remove(m.tape) end
        s.partyTape = s.partyTape or {}
        table.insert(s.partyTape, 1, { t = time(), who = name, link = link, qty = qty, v = v, src = src })
        while #s.partyTape > 60 do table.remove(s.partyTape) end
        ns:RefreshPage("pnl")
    end)
end)

-- Your coin while grouped = everyone's equal share
ns:Listen("LEDGER_ENTRY", function(e)
    if e.k ~= "LOOT" or e.c ~= ns.CharKey() or not running() then return end
    if not (IsInGroup and IsInGroup()) then return end
    local s = sess()
    syncRoster()
    s.partyCoin = (s.partyCoin or 0) + e.a
end)

---------------------------------------------------------------------------
-- Desk-to-desk sync (party members running Fish & Partners)
---------------------------------------------------------------------------
local function broadcast()
    if not (IsInGroup and IsInGroup()) or not ns.Session then return end
    local st = ns.Session:Stats()
    if not st.active then return end
    local msg = format("S;%d;%d;%d;%d;%d", floor(st.total or 0), floor(st.coin or 0), floor(st.quest or 0),
        floor(st.items or 0), floor(st.elapsed or 0))
    ns.Comm:Send(msg, nil, nil, "S") -- a newer total replaces one still waiting to go out
end

ns:On("CHAT_MSG_ADDON", function(prefix, text, _, sender)
    if prefix ~= PREFIX or type(text) ~= "string" then return end
    local s = sess()
    if not (s and s.active) or not sender or ns.Comm.IsMe(sender) then return end
    local name = ns.Comm.Who(sender)
    local kind, total, coin, quest, items, elapsed = strsplit(";", text)
    if kind ~= "S" then return end
    local roster = PT.Roster()
    if not roster[name] then return end
    local m = member(s, name)
    m.sync = { total = tonumber(total), coin = tonumber(coin), quest = tonumber(quest), items = tonumber(items),
        elapsed = tonumber(elapsed), t = time() }
    ns:RefreshPage("pnl")
end)

ns:OnInit(function()
    C_Timer.NewTicker(20, broadcast)
end)
ns:Listen("SESSION_UPDATE", function()
    -- small debounce so a burst of loot sends one update
    if PT.pendingSend then return end
    PT.pendingSend = true
    C_Timer.After(3, function() PT.pendingSend = false; broadcast() end)
end)

---------------------------------------------------------------------------
-- Numbers
---------------------------------------------------------------------------
function PT:MemberStats(s, m)
    local value = 0
    for _, it in pairs(m.items) do value = value + (it.unit or 0) * it.qty end
    local coin = coinOf(s, m)
    local total = value + coin
    local live = m.sync and (time() - m.sync.t) < 90
    local dur = max(0, ns.Session:Elapsed() - (m.joinElapsed or 0))
    return {
        value = value, coin = coin, total = total,
        reported = m.sync and m.sync.total, live = live,
        gph = dur >= 60 and (total / (dur / 3600)) or nil, dur = dur,
    }
end

function PT:Summary(s)
    if not s or not s.party then return nil end
    local out = {}
    for name, m in pairs(s.party) do
        local ms = self:MemberStats(s, m)
        if ms.total > 0 or m.fills > 0 then out[#out + 1] = { name = name, total = ms.reported or ms.total } end
    end
    table.sort(out, function(a, b) return a.total > b.total end)
    while #out > 8 do table.remove(out) end
    return #out > 0 and out or nil
end

local function classColored(name, class)
    local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not cc then return name end
    return format("|cff%02x%02x%02x%s|r", floor(cc.r * 255), floor(cc.g * 255), floor(cc.b * 255), name)
end

---------------------------------------------------------------------------
-- View (inside the PNL page)
---------------------------------------------------------------------------
local selected

function PT:BuildView(pv)
    local W, H = ns.PAGE_W, ns.PAGE_H
    local leftW, rightW = 524, W - 524 - 8

    local s1 = UI.Section(pv, "Party book · who's looting what", true)
    s1:SetPoint("TOPLEFT", 0, -98); s1:SetWidth(leftW)
    pv.secBoard = s1
    pv.board = UI.Table(pv, {
        { title = "Member", width = 130 },
        { title = "Fills", width = 40, justify = "RIGHT" },
        { title = "Items", width = 76, justify = "RIGHT" },
        { title = "Coin*", width = 70, justify = "RIGHT" },
        { title = "Total", width = 80, justify = "RIGHT" },
        { title = "Share", width = 52, justify = "RIGHT" },
        { title = "G/hr", width = 68, justify = "RIGHT" },
    }, leftW, 206, 18)
    pv.board:SetPoint("TOPLEFT", 0, -116)
    pv.board:SetEmptyText("Not in a group, or no session running.\nJoin a party and start a session.")

    local s2 = UI.Section(pv, "Member holdings")
    s2:SetPoint("TOPLEFT", leftW + 8, -98); s2:SetWidth(rightW)
    pv.secHold = s2
    pv.hold = UI.Table(pv, {
        { title = "Instrument", width = 172 },
        { title = "Qty", width = 40, justify = "RIGHT" },
        { title = "Value", width = 108, justify = "RIGHT" },
    }, rightW, 206, 16)
    pv.hold:SetPoint("TOPLEFT", leftW + 8, -116)
    pv.hold:SetEmptyText("Click a member to see their haul.")

    local s3 = UI.Section(pv, "Party tape")
    s3:SetPoint("TOPLEFT", 0, -328); s3:SetWidth(leftW)
    pv.tape = UI.Table(pv, {
        { title = "Time", width = 60 },
        { title = "Member", width = 100 },
        { title = "Fill", width = 250 },
        { title = "Value", width = 96, justify = "RIGHT" },
    }, leftW, H - 346, 15)
    pv.tape:SetPoint("TOPLEFT", 0, -346)
    pv.tape:SetEmptyText("Waiting for party fills…")

    local s4 = UI.Section(pv, "Desk notes")
    s4:SetPoint("TOPLEFT", leftW + 8, -328); s4:SetWidth(rightW)
    pv.notes = UI.Text(pv, 10, C.grey, "LEFT")
    pv.notes:SetPoint("TOPLEFT", leftW + 8, -348)
    pv.notes:SetWidth(rightW)
    pv.notes:SetWordWrap(true)
    pv.notes:SetJustifyV("TOP")
end

function PT:RefreshView(pv)
    local s = sess()
    local st = ns.Session:Stats()
    local rows, partyTotal = {}, 0
    local list = {}

    if s and s.active then
        -- you
        list[#list + 1] = { name = UnitName("player"), you = true, class = select(2, UnitClass("player")),
            fills = st.lootCount or 0, value = st.items or 0, coin = (st.coin or 0) + (st.quest or 0), total = st.total or 0, gph = st.gph }
        for name, m in pairs(s.party or {}) do
            local ms = self:MemberStats(s, m)
            list[#list + 1] = { name = name, m = m, class = m.class, fills = m.fills, value = ms.value, coin = ms.coin,
                total = ms.total, gph = ms.gph, reported = ms.reported, live = ms.live, present = m.present }
        end
    end
    for _, r in ipairs(list) do partyTotal = partyTotal + r.total end
    table.sort(list, function(a, b) return a.total > b.total end)
    local ME = "__me"
    if not selected or (selected ~= ME and not (s and s.party and s.party[selected])) then
        selected = nil
        for _, r in ipairs(list) do if not r.you then selected = r.name break end end
        selected = selected or ME
    end

    for _, r in ipairs(list) do
        local label = classColored(r.name, r.class)
        if r.you then label = ns.Color("orange", "» ") .. label .. ns.Color("dim", " (you)") end
        local heard = not r.you and ns.Comm and ns.Comm.stats.from[r.name]
        if r.live then label = label .. ns.Color("green", " FP")
        elseif heard and time() - heard.t < 900 then label = label .. ns.Color("grey", " FP") end
        if r.present == false then label = label .. ns.Color("dim", " left") end
        local isSel = (r.you and selected == ME) or (not r.you and r.name == selected)
        if isSel then label = ns.Color("amber", "> ") .. label end
        rows[#rows + 1] = {
            selected = isSel,
            cells = {
                label, tostring(r.fills), ns.MoneyShort(r.value),
                r.you and ns.MoneyShort(r.coin) or ns.Color("grey", "~" .. ns.MoneyShort(r.coin)),
                ns.Color("white", ns.MoneyShort(r.total)),
                partyTotal > 0 and ns.Color("amber", format("%.0f%%", 100 * r.total / partyTotal)) or "",
                r.gph and ns.MoneyShort(r.gph) or ns.Color("dim", "--"),
            },
            tooltip = function(tt)
                tt:AddLine(classColored(r.name, r.class) .. (r.you and " (you)" or ""))
                tt:AddDoubleLine("Items looted (valued)", ns.Money(r.value), 0.8, 0.8, 0.8, 1, 1, 1)
                tt:AddDoubleLine(r.you and "Coin + quests" or "Coin share (est.)", ns.Money(r.coin), 0.8, 0.8, 0.8, 1, 1, 1)
                tt:AddDoubleLine("Total", ns.Money(r.total), 0.8, 0.8, 0.8, 1, 1, 1)
                if r.m and r.m.best then tt:AddDoubleLine("Top drop", r.m.best .. " " .. ns.MoneyShort(r.m.bestV or 0), 0.8, 0.8, 0.8) end
                if r.reported then
                    tt:AddLine(" ")
                    tt:AddLine("Reported by their Fish & Partners desk", 0.29, 0.96, 0.76)
                    local sy = r.m.sync
                    tt:AddDoubleLine("Their session P&L", ns.Money(sy.total or 0), 0.8, 0.8, 0.8, 1, 1, 1)
                    tt:AddDoubleLine("Coin / quests / items", ns.MoneyShort(sy.coin or 0) .. " / " .. ns.MoneyShort(sy.quest or 0) ..
                        " / " .. ns.MoneyShort(sy.items or 0), 0.8, 0.8, 0.8, 1, 1, 1)
                    tt:AddDoubleLine("Their clock", ns.Duration(sy.elapsed or 0) .. (r.live and "" or "  (stale)"), 0.8, 0.8, 0.8, 1, 1, 1)
                end
                tt:AddLine("|cffffc238Click|r to see " .. (r.you and "your" or "their") .. " haul", 0.8, 0.8, 0.8)
            end,
            onClick = function(button)
                if button ~= "LeftButton" then return end
                selected = r.you and ME or r.name
                if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) or 856) end
                ns:RefreshPage("pnl")
            end,
        }
    end
    pv.board:SetData(rows, true)
    local members = 0
    for _ in pairs(PT.Roster()) do members = members + 1 end
    pv.secBoard.right:SetText(ns.MoneyShort(partyTotal) .. " PARTY TOTAL")

    -- selected member holdings
    local hold = {}
    local items, who
    if selected == ME and s then
        items, who = s.items, (UnitName("player") or "you") .. " (you)"
    else
        local m = s and s.party and selected and s.party[selected]
        if m then items, who = m.items, selected end
    end
    local holdTotal = 0
    for link, it in pairs(items or {}) do
        local v = (it.unit or 0) * it.qty
        holdTotal = holdTotal + v
        hold[#hold + 1] = { v = v, link = link, cells = { link, tostring(it.qty), ns.MoneyShort(v) .. ns.Color("dim", " " .. (it.src or "")) } }
    end
    table.sort(hold, function(a, b) return a.v > b.v end)
    pv.secHold.title:SetText(who and ("HAUL · " .. who):upper() or "MEMBER HAUL")
    pv.hold:SetData(hold, true)
    pv.hold:SetEmptyText(who and (who .. " hasn't looted any items yet.") or "Click a member to see their haul.")

    -- party tape
    local tape = {}
    for _, t in ipairs(s and s.partyTape or {}) do
        local mm = s.party and s.party[t.who]
        tape[#tape + 1] = {
            link = t.link,
            cells = {
                ns.Color("grey", date("%H:%M:%S", t.t)), classColored(t.who, mm and mm.class),
                t.link .. (t.qty > 1 and ns.Color("grey", " x" .. t.qty) or ""), ns.PnL(t.v),
            },
        }
    end
    pv.tape:SetData(tape, true)

    -- notes
    local synced = 0
    for _, r in ipairs(list) do if r.live then synced = synced + 1 end end
    pv.notes:SetText(
        ns.Color("white", "Group: ") .. members .. " other member" .. (members == 1 and "" or "s") ..
        "   ·   " .. ns.Color("white", "FP desks: ") .. synced .. "\n\n" ..
        ((s and s.groupRules) and (ns.Color("orange", "House rules in effect: ") .. "everyone's desk values items with the same rules and the newest AH scan in the group.\n\n")
            or "Items: tracked from loot messages, valued with your pricing rules.\n\n") ..
        "Coin*: the game doesn't show other players' coin. Group coin is split evenly, so each member's share is estimated from yours while they were in the group.\n\n" ..
        ns.Color("green", "FP") .. " = member runs Fish & Partners (grey: no session running). Hover them for their exact session P&L. Not showing? Both type /fp sync.")
end
