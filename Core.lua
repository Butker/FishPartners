-- Fish & Partners Wealth Management
-- Core: namespace, saved variables, event + message bus, formatting, API compat.

local ADDON, ns = ...
_G.FishPartners = ns

ns.NAME    = "Fish & Partners"
ns.SUB     = "WEALTH MANAGEMENT"
ns.VERSION = ((C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata or function() end)(ADDON, "Version") or "dev"
ns.CALLER  = "FishPartners" -- Auctionator API caller id

local floor, abs, format, tostring = math.floor, math.abs, string.format, tostring

---------------------------------------------------------------------------
-- API compatibility (modern C_ namespaces with legacy fallbacks)
---------------------------------------------------------------------------
ns.GetItemInfo        = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
ns.GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or _G.GetItemInfoInstant

function ns.GetNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag) or 0
    end
    return (_G.GetContainerNumSlots and _G.GetContainerNumSlots(bag)) or 0
end

-- returns link, count, isBound, itemID
function ns.GetSlotInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.hyperlink, info.stackCount or 1, info.isBound, info.itemID end
        return nil
    end
    if _G.GetContainerItemInfo then
        local _, count, _, _, _, _, link, _, _, itemID, isBound = _G.GetContainerItemInfo(bag, slot)
        return link, count or 1, isBound, itemID
    end
end

function ns.CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local DEFAULTS = {
    settings = {
        gearMargin     = 10,   -- % AH must beat vendor for weapons/armor
        otherMargin    = 5,    -- % AH must beat vendor for mats & everything else
        deductAHCut    = false,
        ahCut          = 5,
        sessionQuest   = true,  -- count quest gold in session P&L
        aumItems       = true,  -- include bags/bank inventory value in AUM
        dealPct        = 30,    -- dip: cheapest units this % under the live market median
        dealMinProfit  = 5000,  -- dip: min est. profit (copper)
        minDepth       = 10,    -- dip: min units listed for the median to count
        alertMinProfit = 50000, -- chat alert for deals at least this profitable
        alertSound     = true,
        vendorFlips    = true,
        targetMargin   = 15,    -- posting desk target profit %
        dailyReport    = true,
        ahBanner       = true,
        saleChat       = true,
        postingDesk    = true,
        hudAuto        = true,
        hudScale       = 1.0,
        instanceBell   = true,
        afkPause       = true,  -- pause the session while WoW marks you AFK
        groupRules     = true,  -- house rules + shared prices when grouped with other users
        priceStaleDays = 7,     -- AH prices older than this are marked stale  -- ask to open/book a session when entering a dungeon or raid  -- open the mini session window when a session starts
        minimapHide    = false,
        minimapAngle   = 200,
        scale          = 1.0,
        ledgerMax      = 5000,
        tickerSpeed    = 45,
    },
    chars   = {},
    ledger  = {},
    history = {},
    frame   = {},
}

local CHAR_DEFAULTS = {
    session = nil,
    archive = {},
}

local function merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

---------------------------------------------------------------------------
-- Event dispatcher (safe register: unknown events on this client are skipped)
---------------------------------------------------------------------------
local evFrame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        local ok = pcall(evFrame.RegisterEvent, evFrame, event)
        if not ok then handlers[event].dead = true end
    end
    table.insert(handlers[event], fn)
end

evFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end)

-- Internal message bus
local listeners = {}
function ns:Listen(msg, fn)
    listeners[msg] = listeners[msg] or {}
    table.insert(listeners[msg], fn)
end
function ns:Fire(msg, ...)
    local list = listeners[msg]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end

-- Data upgrades: each module registers numbered steps; at login every step newer than
-- the saved data version runs once, in order. One place for all data cleanups.
local migrations = {}
function ns:Migration(version, name, fn)
    migrations[#migrations + 1] = { v = version, name = name, fn = fn }
end
local function runMigrations()
    table.sort(migrations, function(a, b) return a.v < b.v end)
    local current = ns.db.schema or 0
    for _, m in ipairs(migrations) do
        if m.v > current then
            local ok, err = pcall(m.fn)
            if not ok then geterrorhandler()("FishPartners upgrade " .. m.v .. " (" .. m.name .. "): " .. tostring(err)) end
            current = m.v
        end
    end
    ns.db.schema = current
end

-- Init callbacks run at PLAYER_LOGIN once saved vars are merged
local inits = {}
function ns:OnInit(fn) table.insert(inits, fn) end

ns:On("PLAYER_LOGIN", function()
    FishPartnersDB     = merge(FishPartnersDB or {}, DEFAULTS)
    FishPartnersCharDB = merge(FishPartnersCharDB or {}, CHAR_DEFAULTS)
    ns.db, ns.cdb = FishPartnersDB, FishPartnersCharDB
    ns.S = ns.db.settings
    runMigrations()
    for i = 1, #inits do
        local ok, err = pcall(inits[i])
        if not ok then geterrorhandler()(err) end
    end
    ns.Print("Desk open. |cfffb8b1e/fp|r to launch the terminal.")
end)

---------------------------------------------------------------------------
-- Colors
---------------------------------------------------------------------------
ns.C = {
    bg      = { 0.015, 0.015, 0.02 },
    panel   = { 0.055, 0.055, 0.07 },
    panel2  = { 0.085, 0.085, 0.105 },
    line    = { 0.20, 0.20, 0.24 },
    orange  = { 0.98, 0.545, 0.118 },
    amber   = { 1.00, 0.76, 0.22 },
    green   = { 0.29, 0.96, 0.76 },
    red     = { 1.00, 0.26, 0.24 },
    blue    = { 0.00, 0.41, 1.00 },
    cyan    = { 0.35, 0.80, 1.00 },
    white   = { 0.93, 0.93, 0.93 },
    grey    = { 0.52, 0.52, 0.58 },
    dim     = { 0.32, 0.32, 0.37 },
}
ns.HEX = {
    orange = "fffb8b1e", amber = "ffffc238", green = "ff4af6c3", red = "ffff433d",
    blue = "ff0068ff", cyan = "ff59ccff", white = "ffededed", grey = "ff85858f", dim = "ff52525e",
    gold = "ffffd100", silver = "ffc7c7cf", copper = "ffeda55f",
}
function ns.Color(hexKey, text) return "|c" .. ns.HEX[hexKey] .. text .. "|r" end

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cfffb8b1eF&P|r |cff85858f>|r " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Number / money formatting
---------------------------------------------------------------------------
function ns.Commas(n)
    local s = tostring(floor(abs(n)))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if out:sub(1, 1) == "," then out = out:sub(2) end
    return (n < 0 and "-" or "") .. out
end

-- Full: 1,234g 05s 09c  (colored)
function ns.Money(copper, signed)
    copper = floor((copper or 0) + 0.5)
    local neg = copper < 0
    copper = abs(copper)
    local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = "|c" .. ns.HEX.gold .. ns.Commas(g) .. "g|r" end
    if g > 0 or s > 0 then parts[#parts + 1] = "|c" .. ns.HEX.silver .. (g > 0 and format("%02d", s) or s) .. "s|r" end
    parts[#parts + 1] = "|c" .. ns.HEX.copper .. ((g > 0 or s > 0) and format("%02d", c) or c) .. "c|r"
    local sign = neg and "-" or (signed and copper > 0 and "+" or "")
    return sign .. table.concat(parts, " ")
end

-- Compact gold: 1,234.5g / 45s / 12c (no color)
function ns.MoneyShort(copper, signed)
    copper = floor((copper or 0) + 0.5)
    local neg = copper < 0
    local a = abs(copper)
    local str
    if a >= 1000000000 then
        str = format("%.2fMg", a / 10000 / 1000000)
    elseif a >= 100000000 then
        str = ns.Commas(floor(a / 10000)) .. "g"
    elseif a >= 1000000 then
        str = ns.Commas(floor(a / 10000)) .. format(".%dg", floor(a / 1000) % 10)
    elseif a >= 10000 then
        str = format("%.2fg", a / 10000)
    elseif a >= 100 then
        str = floor(a / 100) .. "s"
    else
        str = a .. "c"
    end
    if neg then return "-" .. str end
    if signed and a > 0 then return "+" .. str end
    return str
end

-- Signed + colored green/red
function ns.PnL(copper)
    copper = copper or 0
    local txt = ns.MoneyShort(copper, true)
    if copper > 0 then return ns.Color("green", txt) end
    if copper < 0 then return ns.Color("red", txt) end
    return ns.Color("grey", txt)
end

function ns.Duration(sec)
    sec = floor(sec or 0)
    return format("%02d:%02d:%02d", floor(sec / 3600), floor(sec / 60) % 60, sec % 60)
end

function ns.Pct(x, signed)
    if not x then return "--" end
    local s = format("%.1f%%", x)
    if signed and x > 0 then s = "+" .. s end
    return s
end

-- Item cache helper: run fn once item data is available
function ns.WhenItemReady(link, fn)
    if not link then return end
    if ns.GetItemInfo(link) then fn() return end
    if Item and Item.CreateFromItemLink then
        local item = Item:CreateFromItemLink(link)
        if item and not item:IsItemEmpty() then
            item:ContinueOnItemLoad(fn)
            return
        end
    end
    local tries = 0
    local function retry()
        tries = tries + 1
        if ns.GetItemInfo(link) or tries > 20 then fn() else C_Timer.After(0.25, retry) end
    end
    C_Timer.After(0.25, retry)
end

function ns.LinkName(link)
    if not link then return "" end
    return link:match("%[(.-)%]") or link
end

function ns.Today() return date("%Y-%m-%d") end
