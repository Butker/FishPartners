-- Fish & Partners: group loot rules
-- When you're grouped with other Fish & Partners users and a session is running, every
-- desk in the group switches to the same "house rules", so everyone's party numbers agree:
--
--   1. Same pricing rules: the addon's defaults (gear +10%, everything else +5%, no AH cut
--      deducted, quest gold counts), not anyone's personal settings.
--   2. Same prices: when an item drops, each desk shares its Auctionator price for it if its
--      scan is newer than what the group already has. Everyone uses the newest scan.
--      (Two scans from the same day: the lower price wins, the conservative choice.)
--
-- Once house rules start, they stay on for the rest of that session.
--
-- Messages (prefix FPWM1):
--   H;version              "I run Fish & Partners"
--   P;key;price;scanDay    "my price for this item, from a scan made on this day"

local _, ns = ...
local UI, C = ns.UI, ns.C
local G = {}
ns.Group = G
local floor = math.floor

local PREFIX = "FPWM1"
G.HOUSE = { gearMargin = 10, otherMargin = 5, deductAHCut = false, ahCut = 5 }
G.peers = {}       -- name -> GetTime() last heard from
local lastSent = {} -- key -> { p, d, t }

local function sess() return ns.cdb and ns.cdb.session end
local function today() return floor(time() / 86400) end
local function grouped() return IsInGroup and IsInGroup() end
local function say(msg, tag) if grouped() then ns.Comm:Send(msg, nil, nil, tag) end end

---------------------------------------------------------------------------
-- Who runs Fish & Partners
---------------------------------------------------------------------------
local function rosterName(sender)
    local name = ns.Comm.Who(sender)
    local roster = ns.Party and ns.Party.Roster() or {}
    return name and roster[name] and name or nil
end

function G:PeerList()
    local roster = ns.Party and ns.Party.Roster() or {}
    local out = {}
    for name in pairs(self.peers) do
        if roster[name] then out[#out + 1] = name else self.peers[name] = nil end
    end
    table.sort(out)
    return out
end

function G:InEffect()
    local s = sess()
    return s and s.active and s.groupRules or false
end

---------------------------------------------------------------------------
-- Prices: own scan vs the group's newest
---------------------------------------------------------------------------
-- a better b?  newer scan day wins, same day -> lower price
local function better(p1, d1, p2, d2)
    if not p2 then return p1 ~= nil end
    if not p1 then return false end
    if d1 ~= d2 then return d1 > d2 end
    return p1 < p2
end

local function ownPrice(link, vendor)
    local ah, info = ns.MarketPrice(link, vendor)
    if not ah then return nil, nil, info end
    local day = info.age and (today() - info.age) or 0 -- unknown age: treat as the oldest
    return ah, day, info
end

local function groupPrice(link, vendor)
    local s = sess()
    local key = ns.ItemKey(link)
    local remote = s and s.groupPrices and s.groupPrices[key]
    local ah, day, info = ownPrice(link, vendor)
    if remote and better(remote.p, remote.d, ah, day) then
        local age = math.max(0, today() - remote.d)
        return remote.p, { age = age, from = remote.from, stale = age > ((ns.S and ns.S.priceStaleDays) or 7) }
    end
    return ah, info
end

local OPTS = { rules = G.HOUSE, price = groupPrice }

-- What sessions and the party view value items with
function ns.SessionValuate(link, isBound)
    if G:InEffect() then return ns.Valuate(link, isBound, OPTS) end
    return ns.Valuate(link, isBound)
end

-- A shared price arrived (or changed): re-mark every session and party entry for that item
-- (key nil = every item)
function G:Revalue(key)
    local function match(link) return key == nil or ns.ItemKey(link) == key end
    local s = sess()
    if not (s and s.active) then return end
    local units = {}
    local function unitFor(link)
        if units[link] == nil then units[link] = ns.SessionValuate(link) or false end
        return units[link]
    end
    for link, it in pairs(s.items or {}) do
        if match(link) then
            local unit, src, ah, vendor, _, info = ns.SessionValuate(link)
            if unit then it.unit, it.src, it.ah, it.vendor, it.note = unit, src, ah, vendor, ns.ValuationNote(info) end
        end
    end
    local function fixTape(tape)
        for _, e in ipairs(tape or {}) do
            if e.link and match(e.link) then
                local u = unitFor(e.link)
                if u then e.v = (e.convert and -1 or 1) * u * (e.qty or 1) end
            end
        end
    end
    fixTape(s.tape)
    fixTape(s.partyTape)
    for _, m in pairs(s.party or {}) do
        for link, it in pairs(m.items or {}) do
            if match(link) then
                local u, src = ns.SessionValuate(link)
                if u then it.unit, it.src = u, src or it.src end
            end
        end
        fixTape(m.tape)
        local best, bestV
        for link, it in pairs(m.items or {}) do
            local v = (it.unit or 0) * (it.qty or 0)
            if not bestV or v > bestV then best, bestV = link, v end
        end
        m.best, m.bestV = best, bestV
    end
    ns:Fire("SESSION_UPDATE")
    ns:RefreshPage("pnl")
end

-- An item dropped somewhere in the group: share our price if it's the newest we know of
local function offerPrice(link)
    if not G:InEffect() or #G:PeerList() == 0 then return end
    if ns.Eligibility(link) ~= "count" then return end
    ns.WhenItemReady(link, function()
        local _, _, _, _, _, _, _, _, _, _, vendor, _, _, bindType = ns.GetItemInfo(link)
        if bindType == 1 then return end -- BoP: vendor price for everyone anyway
        -- small random delay, so desks with the same scan don't all talk at once
        C_Timer.After(0.3 + math.random() * 1.2, function()
            local s = sess()
            if not (s and s.groupRules) then return end
            local key = ns.ItemKey(link)
            local ah, day = ownPrice(link, vendor or 0)
            if not ah then return end
            local remote = s.groupPrices and s.groupPrices[key]
            if remote and not better(ah, day, remote.p, remote.d) then return end
            local ls = lastSent[key]
            if ls and ls.p == ah and ls.d == day and GetTime() - ls.t < 600 then return end
            lastSent[key] = { p = ah, d = day, t = GetTime() }
            ns.Comm:SendBatched("P", format("%s;%d;%d", tostring(key), floor(ah), day))
        end)
    end)
end

ns:On("CHAT_MSG_LOOT", function(msg)
    if type(msg) ~= "string" or not G:InEffect() then return end
    local link = msg:match("|c%x+|Hitem:.-|h.-|h|r")
    if link then offerPrice(link) end
end)

---------------------------------------------------------------------------
-- House rules on
---------------------------------------------------------------------------
local toast
local function buildToast()
    toast = CreateFrame("Frame", "FishPartnersHouseRules", UIParent)
    toast:SetSize(360, 64)
    toast:SetPoint("TOP", 0, -70)
    toast:SetFrameStrata("HIGH")
    UI.Fill(toast, C.bg, 0.95)
    UI.Border(toast, C.orange)
    local head = UI.Panel(toast, C.orange, false)
    head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1); head:SetHeight(16)
    local k = UI.Text(head, 9, { 0, 0, 0 }, "LEFT", UI.FONT, ""); k:SetPoint("LEFT", 8, 0)
    k:SetText("GROUP LOOT RULES IN EFFECT")
    local brand = UI.Text(head, 9, { 0, 0, 0 }, "RIGHT"); brand:SetPoint("RIGHT", -8, 0)
    brand:SetText("FISH & PARTNERS")
    toast.line1 = UI.Text(toast, 11, C.white, "LEFT"); toast.line1:SetPoint("TOPLEFT", 10, -22); toast.line1:SetWidth(340)
    toast.line2 = UI.Text(toast, 10, C.amber, "LEFT"); toast.line2:SetPoint("TOPLEFT", 10, -40); toast.line2:SetWidth(340)
    toast:EnableMouse(true)
    toast:SetScript("OnMouseUp", function() toast:Hide() end)
    toast:Hide()
end

function G:RulesText()
    local H = self.HOUSE
    return format("Gear +%d%% · Other +%d%% over vendor · %s · newest scan wins", H.gearMargin, H.otherMargin,
        H.deductAHCut and ("AH cut " .. H.ahCut .. "% deducted") or "no AH cut")
end

function G:Ring()
    if not toast then buildToast() end
    local peers = self:PeerList()
    toast.line1:SetText("Desks in sync with " .. (#peers > 0 and table.concat(peers, ", ") or "your group") .. ". House rules for this session.")
    toast.line2:SetText(self:RulesText())
    local recent = toast:IsShown() and toast.shownAt and GetTime() - toast.shownAt < 20
    toast.shownAt = GetTime()
    toast:Show()
    if not recent and PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.AUCTION_WINDOW_OPEN) or 5274) end
    if toast.timer then toast.timer:Cancel() end
    toast.timer = C_Timer.NewTimer(10, function() toast:Hide() end)
end

function G:Check()
    local s = sess()
    if not (s and s.active) or s.groupRules then return end
    if not grouped() or (ns.S and ns.S.groupRules == false) then return end
    if #self:PeerList() == 0 then return end
    s.groupRules = true
    s.groupPrices = s.groupPrices or {}
    self:Revalue(nil)
    self:Ring()
    ns.Print(ns.Color("orange", "Group loot rules in effect") .. " with " .. table.concat(self:PeerList(), ", ") ..
        ns.Color("grey", ". " .. self:RulesText() .. "."))
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
local lastHello = 0
local function hello(force)
    if not grouped() then return end
    if not force and GetTime() - lastHello < 10 then return end
    lastHello = GetTime()
    say("H;" .. (ns.VERSION or "dev"), "H")
end

ns:On("CHAT_MSG_ADDON", function(prefix, text, _, sender)
    if prefix ~= PREFIX or type(text) ~= "string" then return end
    local name = rosterName(sender)
    if not name or ns.Comm.IsMe(sender) then return end
    local kind = strsplit(";", text)
    if kind ~= "H" and kind ~= "P" and kind ~= "S" then return end
    local isNew = not G.peers[name]
    G.peers[name] = GetTime()
    if isNew and kind == "H" then hello() end -- let them know about us too
    if kind == "P" then
        local s = sess()
        if not (s and s.active and s.groupRules) then G:Check(); s = sess() end
        if not (s and s.groupRules) then return end
        -- P;key;price;day[;key;price;day...]  (several drops in one message)
        local f = { strsplit(";", text) }
        s.groupPrices = s.groupPrices or {}
        for i = 2, #f - 2, 3 do
            local key = tonumber(f[i]) or f[i]
            local p, d = tonumber(f[i + 1]), tonumber(f[i + 2])
            if key and key ~= "" and p and d and p > 0 then
                local cur = s.groupPrices[key]
                if better(p, d, cur and cur.p, cur and cur.d) then
                    s.groupPrices[key] = { p = p, d = d, from = name }
                    G:Revalue(key)
                end
            end
        end
        return
    end
    G:Check()
end)

ns:On("GROUP_ROSTER_UPDATE", function()
    if not ns.db then return end
    C_Timer.After(2, function() hello(); G:Check() end)
end)
ns:On("PLAYER_ENTERING_WORLD", function()
    if not ns.db then return end
    C_Timer.After(3, function()
        hello(true)
        -- ring again on entering a dungeon or raid with house rules already on
        local inside, kind = IsInInstance()
        if inside and (kind == "party" or kind == "raid") and G:InEffect() and #G:PeerList() > 0 then G:Ring() end
    end)
end)
ns:Listen("SESSION_UPDATE", function()
    local s = sess()
    if s and s.active and not s.groupRules and grouped() then G:Check() end
end)

ns:AddTicker(function()
    if G:InEffect() and #G:PeerList() > 0 then
        return ns.Color("orange", "HOUSE RULES") .. ns.Color("grey", " with " .. table.concat(G:PeerList(), ", "))
    end
end)

function G:Print()
    local peers = self:PeerList()
    ns.Print(ns.Color("orange", "GROUP LOOT RULES"))
    ns.Print("Fish & Partners users in your group: " .. (#peers > 0 and table.concat(peers, ", ") or "none"))
    local s = sess()
    if self:InEffect() then
        local n = 0
        for _ in pairs(s.groupPrices or {}) do n = n + 1 end
        ns.Print("In effect for this session. " .. self:RulesText() .. ". Shared prices: " .. n .. ".")
    elseif ns.S.groupRules == false then
        ns.Print("Off (Compliance tab).")
    else
        ns.Print("Not in effect: they start when a session runs while you're grouped with another user.")
    end
end
